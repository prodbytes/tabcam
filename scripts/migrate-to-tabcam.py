"""Moves TabScan's cloud data to TabCam's stacks, once, before the cutover.

    python3 -I scripts/migrate-to-tabcam.py            # dry run: counts only
    python3 -I scripts/migrate-to-tabcam.py --apply    # does it

A profile's folder is its Cognito identity in the identity pool, and the new
pool (developer provider login.tabcam.profiles) gives every profile a new
identity. So, for each profile in the old profiles table:

1. its identity in the new pool (GetOpenIdTokenForDeveloperIdentity, as the
   share API does at sign-in), the map old identity -> new;
2. its folder copied from the old bucket to the new one under the new
   identity (server-side copies; event.json's `owner` rewritten); OCR
   results (ocr/) too;
3. the tables copied with identities mapped: profiles (identityId), sign-ins
   (as they are), shares (`capture` = owner#capture, `owner`), links
   (`owner`), and the cloud OCR service's accounts (identityId).

Link codes (10 minutes) and profile keys aren't copied: profiles get new
key pairs from the new KMS key at their next request. It stops if any
capture is already encrypted (its key would be lost). Folders of sign-in
identities that aren't a profile's (local web builds, from before profiles)
aren't moved: their captures moved into the profile when it was made.

Idempotent: objects and items already there are copied again (same
content). Prints counts, never addresses, names or titles.
"""

import argparse
import json
import sys

import boto3

REGION = "us-east-1"
OLD = {"share_api": "tabscan-share-api", "identity": "tabscan-identity",
       "user_data": "tabscan-user-data", "accounts": "tabscan-accounts",
       "provider": "login.tabscan.profiles"}
NEW = {"share_api": "tabcam-share-api", "identity": "tabcam-identity",
       "user_data": "tabcam-user-data", "accounts": "tabcam-accounts",
       "provider": "login.tabcam.profiles"}


def outputs(cfn, stack):
    out = cfn.describe_stacks(StackName=stack)["Stacks"][0].get("Outputs", [])
    return {o["OutputKey"]: o["OutputValue"] for o in out}


def resource(cfn, stack, logical):
    return cfn.describe_stack_resource(StackName=stack, LogicalResourceId=logical)[
        "StackResourceDetail"]["PhysicalResourceId"]


def scan(table):
    kwargs = {}
    while True:
        page = table.scan(**kwargs)
        yield from page["Items"]
        if "LastEvaluatedKey" not in page:
            return
        kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]


def keys_under(s3, bucket, prefix):
    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix=prefix):
        for o in page.get("Contents", []):
            yield o["Key"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="copy (default: count only)")
    args = parser.parse_args()
    apply = args.apply

    cfn = boto3.client("cloudformation", region_name=REGION)
    ddb = boto3.resource("dynamodb", region_name=REGION)
    s3 = boto3.client("s3", region_name=REGION)
    cognito = boto3.client("cognito-identity", region_name=REGION)

    old_bucket = outputs(cfn, OLD["user_data"])["UserDataBucketName"]
    new_bucket = outputs(cfn, NEW["user_data"])["UserDataBucketName"]
    new_pool = outputs(cfn, NEW["identity"])["IdentityPoolId"]
    table = {}
    for name in ("ProfilesTable", "SubjectsTable", "SharesTable", "LinksTable"):
        table[("old", name)] = ddb.Table(resource(cfn, OLD["share_api"], name))
        table[("new", name)] = ddb.Table(resource(cfn, NEW["share_api"], name))
    old_accounts, new_accounts = ddb.Table(OLD["accounts"]), ddb.Table(NEW["accounts"])
    if old_bucket == new_bucket:
        sys.exit("error: the old and new buckets are the same")

    # 1. Every profile's new identity.
    profiles = list(scan(table[("old", "ProfilesTable")]))
    ids = {}
    for p in profiles:
        old_id = p.get("identityId")
        if not old_id:
            continue  # never had a folder
        if apply:
            new_id = cognito.get_open_id_token_for_developer_identity(
                IdentityPoolId=new_pool, Logins={NEW["provider"]: p["id"]},
                TokenDuration=60)["IdentityId"]
        else:
            new_id = f"<new identity of {old_id[-6:]}>"
        ids[old_id] = new_id
    print(f"profiles: {len(profiles)}, with a folder: {len(ids)}")

    # 2. Folders: every object of every profile's identity.
    objects = sealed = 0
    for old_id, new_id in ids.items():
        for key in keys_under(s3, old_bucket, f"{old_id}/"):
            objects += 1
            rest = key[len(old_id) + 1:]
            if key.endswith("/event.json"):
                body = s3.get_object(Bucket=old_bucket, Key=key)["Body"].read()
                event = json.loads(body)
                if "sealed" in event:
                    sealed += 1
                if event.get("owner") == old_id:
                    event["owner"] = new_id
                if apply:
                    s3.put_object(Bucket=new_bucket, Key=f"{new_id}/{rest}",
                                  Body=json.dumps(event).encode(),
                                  ContentType="application/json")
            elif apply:
                s3.copy_object(Bucket=new_bucket, Key=f"{new_id}/{rest}",
                               CopySource={"Bucket": old_bucket, "Key": key},
                               MetadataDirective="COPY")
    if sealed:
        sys.exit(f"error: {sealed} captures are encrypted; their keys would be lost")
    others = {k.split("/", 1)[0] for k in keys_under(s3, old_bucket, "")} - set(ids)
    print(f"objects: {objects} (folders that aren't a profile's, left: {len(others)})")

    # 3. Tables, identities mapped.
    def mapped(identity):
        return ids.get(identity, identity)

    counts = {}

    def put(name, item, target):
        counts[name] = counts.get(name, 0) + 1
        if apply:
            target.put_item(Item=item)

    for p in profiles:
        p = dict(p)
        if p.get("identityId"):
            p["identityId"] = mapped(p["identityId"])
        put("profiles", p, table[("new", "ProfilesTable")])
    for s in scan(table[("old", "SubjectsTable")]):
        put("sign-ins", s, table[("new", "SubjectsTable")])
    unmapped = 0
    for g in scan(table[("old", "SharesTable")]):
        g = dict(g)
        owner, _, capture = g["capture"].partition("#")
        unmapped += owner not in ids
        g["capture"] = f"{mapped(owner)}#{capture}"
        if "owner" in g:
            g["owner"] = mapped(g["owner"])
        put("shares", g, table[("new", "SharesTable")])
    for link in scan(table[("old", "LinksTable")]):
        link = dict(link)
        unmapped += link["owner"] not in ids
        link["owner"] = mapped(link["owner"])
        put("links", link, table[("new", "LinksTable")])
    for a in scan(old_accounts):
        a = dict(a)
        if a["identityId"] not in ids:
            continue  # not a profile's identity
        a["identityId"] = mapped(a["identityId"])
        put("accounts", a, new_accounts)
    print("items:", ", ".join(f"{n} {c}" for n, c in counts.items()) or "none",
          f"(shares and links of folders that aren't a profile's: {unmapped})")
    print("applied" if apply else "dry run: nothing written (--apply to copy)")


if __name__ == "__main__":
    main()
