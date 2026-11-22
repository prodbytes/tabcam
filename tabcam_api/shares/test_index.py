"""Tests for the share API, with in-memory stand-ins for DynamoDB, Cognito
and STS. Run: python3 -m unittest discover -s tabcam_api/shares"""

import base64
import datetime
import json
import os
import unittest
from decimal import Decimal

os.environ.update(
    PROFILE_KEY_ID="arn:aws:kms:us-east-1:1:key/profiles",
    TABLE="shares",
    BUCKET="nu01-user-events-1",
    IDENTITY_POOL_ID="us-east-1:pool",
    ACCESS_ROLE_ARN="arn:aws:iam::1:role/tabcam-share-access",
    EMAIL_ISSUER="https://cognito-idp.us-east-1.amazonaws.com/us-east-1_Email",
    EMAIL_USER_POOL_ID="us-east-1_Email",
    SESSION_ISSUER="https://api.example.com/session",
)

import index  # noqa: E402
import keys  # noqa: E402
import profiles  # noqa: E402

OWNER = "us-east-1:11111111-1111-1111-1111-111111111111"
OTHER = "us-east-1:22222222-2222-2222-2222-222222222222"


class Table:
    def __init__(self, page_size=None):
        self.items = {}
        # Queries answer this many items a page, as DynamoDB pages by size.
        self.page_size = page_size
        self.queries = 0

    def put_item(self, Item):
        # DynamoDB hands numbers back as Decimals.
        self.items[(Item["capture"], Item["email"])] = {
            k: Decimal(v) if isinstance(v, int) else v for k, v in Item.items()
        }

    def delete_item(self, Key):
        self.items.pop((Key["capture"], Key["email"]), None)

    def get_item(self, Key):
        item = self.items.get((Key["capture"], Key["email"]))
        return {"Item": item} if item else {}

    def update_item(self, Key, UpdateExpression, ExpressionAttributeNames,
                    ConditionExpression=None, ExpressionAttributeValues=None):
        """`SET #a = :v` or `REMOVE #a`, on an item that must be there."""
        k = (Key["capture"], Key["email"])
        if ConditionExpression == "attribute_exists(#c)" and k not in self.items:
            raise ConditionalCheckFailedException()
        action, name, *rest = UpdateExpression.split()
        attr = ExpressionAttributeNames[name]
        if action == "SET":
            self.items[k][attr] = ExpressionAttributeValues[rest[1]]
        else:
            self.items[k].pop(attr, None)

    def query(self, KeyConditionExpression, ExpressionAttributeNames,
              ExpressionAttributeValues, IndexName=None, ExclusiveStartKey=None):
        self.queries += 1
        name = list(ExpressionAttributeNames.values())[0]
        value = list(ExpressionAttributeValues.values())[0]
        items = [i for i in self.items.values() if i[name] == value]
        start = ExclusiveStartKey or 0
        if self.page_size is None or start + self.page_size >= len(items):
            return {"Items": items[start:]}
        end = start + self.page_size
        return {"Items": items[start:end], "LastEvaluatedKey": end}


class ConditionalCheckFailedException(Exception):
    pass


class KeyTable:
    """A one-key table (profiles, subjects, link codes) with its indexes
    (name -> attribute) and conditional writes."""

    def __init__(self, key, indexes=None):
        self.key = key
        self.indexes = indexes or {}
        self.items = {}

    def get_item(self, Key, ConsistentRead=False):
        item = self.items.get(Key[self.key])
        return {"Item": dict(item)} if item else {}

    def put_item(self, Item, ConditionExpression=None):
        k = Item[self.key]
        if ConditionExpression and "attribute_not_exists" in ConditionExpression and k in self.items:
            raise ConditionalCheckFailedException()
        if (ConditionExpression and "attribute_exists" in ConditionExpression
                and "attribute_not_exists" not in ConditionExpression and k not in self.items):
            raise ConditionalCheckFailedException()
        self.items[k] = {kk: Decimal(v) if isinstance(v, int) else v for kk, v in Item.items()}

    def delete_item(self, Key, ConditionExpression=None):
        k = Key[self.key]
        if ConditionExpression and "attribute_exists" in ConditionExpression and k not in self.items:
            raise ConditionalCheckFailedException()
        self.items.pop(k, None)

    def query(self, IndexName, KeyConditionExpression, ExpressionAttributeNames,
              ExpressionAttributeValues, ExclusiveStartKey=None):
        attr = self.indexes[IndexName]
        value = list(ExpressionAttributeValues.values())[0]
        return {"Items": [dict(i) for i in self.items.values() if i.get(attr) == value]}


class Captures(KeyTable):
    """The captures table: each capture's visibility, its owner index, and
    the sparse public index (only items with `listed`), by updatedAt."""

    def __init__(self):
        super().__init__("capture", {"byOwner": "owner"})
        # Items the public index handed out, and at most how many a page.
        self.read = 0
        self.page_size = None

    def query(self, IndexName, KeyConditionExpression, ExpressionAttributeNames,
              ExpressionAttributeValues, ExclusiveStartKey=None, ScanIndexForward=True,
              Limit=None):
        if IndexName != "public":
            return super().query(IndexName, KeyConditionExpression, ExpressionAttributeNames,
                                 ExpressionAttributeValues, ExclusiveStartKey)
        assert ExpressionAttributeNames == {"#l": "listed"}
        value = ExpressionAttributeValues[":l"]
        items = sorted((i for i in self.items.values() if i.get("listed") == value),
                       key=lambda i: (i["updatedAt"], i["capture"]),
                       reverse=not ScanIndexForward)
        start = ExclusiveStartKey or 0
        end = len(items) if Limit is None else min(len(items), start + Limit)
        if self.page_size is not None:
            end = min(end, start + self.page_size)
        self.read += end - start
        return {"Items": [dict(i) for i in items[start:end]],
                **({"LastEvaluatedKey": end} if end < len(items) else {})}


class FakeRbacr:
    def __init__(self, roles=None):
        self.by_email = roles or {}

    def union(self, emails):
        roles = set()
        for e in emails:
            roles |= set(self.by_email.get(e, ["free"]))
        return sorted(roles), []


def store():
    return profiles.Store(
        KeyTable("id", {"byIdentity": "identityId"}),
        KeyTable("subject", {"byProfile": "profileId", "byEmail": "email"}),
        KeyTable("code"),
        now=lambda: 1_800_000_000,
        keys=KeyTable("profileId"),
    )


GOOGLE = "https://accounts.google.com"
APPLE = "https://appleid.apple.com"
EMAIL_ISSUER = "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_Email"


class Accounts:
    """The cloud OCR service's identity -> address table."""

    def __init__(self, items):
        self.items = dict(items)

    def delete_item(self, Key):
        self.items.pop(Key["identityId"], None)


APPLE_OWNER = "us-east-1:22222222-2222-2222-2222-222222222222"


class Cognito:
    def __init__(self):
        # A profile's developer identity, made the first time it's asked for.
        self.identities = {}
        self.tokens = []
        self.deleted = []
        self.unprocessed = False

    def get_open_id_token_for_developer_identity(self, IdentityPoolId, Logins, TokenDuration, IdentityId=None):
        ((provider, profile_id),) = Logins.items()
        assert provider == "login.tabcam.profiles"
        identity = self.identities.setdefault(
            profile_id, IdentityId or f"us-east-1:{len(self.identities) + 1:08d}-0000-0000-0000-000000000000")
        self.tokens.append(profile_id)
        return {"IdentityId": identity, "Token": f"openid-{profile_id}"}

    def delete_identities(self, IdentityIdsToDelete):
        if self.unprocessed:
            return {"UnprocessedIdentityIds": [
                {"IdentityId": i, "ErrorCode": "InternalServerError"}
                for i in IdentityIdsToDelete]}
        self.deleted += IdentityIdsToDelete
        return {"UnprocessedIdentityIds": []}


class Sts:
    def __init__(self):
        self.calls = []

    def assume_role(self, **kwargs):
        self.calls.append(kwargs)
        return {
            "Credentials": {
                "AccessKeyId": "ASIA",
                "SecretAccessKey": "secret",
                "SessionToken": "session",
                "Expiration": datetime.datetime(2026, 10, 10, 13, tzinfo=datetime.timezone.utc),
            }
        }


class S3:
    def __init__(self):
        self.keys = []

    def list_objects_v2(self, Bucket, Prefix, MaxKeys):
        # At most two keys a page, to list more than once.
        found = [k for k in self.keys if k.startswith(Prefix)]
        page = found[:min(MaxKeys, 2)]
        return {**({"Contents": [{"Key": k} for k in page]} if page else {}),
                "IsTruncated": len(found) > len(page)}

    def delete_object(self, Bucket, Key):
        self.keys.remove(Key)


class NoSuchKey(Exception):
    pass


class Objects:
    """The user-data bucket's objects, read with whatever credentials."""

    def __init__(self):
        self.objects = {}
        self.reads = []

    def as_(self, creds):
        self.reads.append(creds["accessKeyId"])
        return self

    def get_object(self, Bucket, Key):
        import io
        if Key not in self.objects:
            raise NoSuchKey(Key)
        return {"Body": io.BytesIO(self.objects[Key])}


_PAIR = None


def _pair():
    """One RSA_3072 pair for every test (making them is slow)."""
    global _PAIR
    if _PAIR is None:
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import rsa
        key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
        _PAIR = (
            key.public_key().public_bytes(serialization.Encoding.DER,
                                          serialization.PublicFormat.SubjectPublicKeyInfo),
            key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8,
                              serialization.NoEncryption()),
        )
    return _PAIR


class Kms:
    """KMS: key pairs wrapped by the one key, opened only with the same
    encryption context."""

    def __init__(self):
        self.made = 0
        self.decrypts = 0

    def generate_data_key_pair_without_plaintext(self, KeyId, KeyPairSpec, EncryptionContext):
        assert KeyId == os.environ["PROFILE_KEY_ID"] and KeyPairSpec == "RSA_3072"
        self.made += 1
        public, private = _pair()
        blob = json.dumps({"ctx": EncryptionContext, "n": self.made}).encode() + b"|" + private
        return {"PublicKey": public, "PrivateKeyCiphertextBlob": blob}

    def decrypt(self, CiphertextBlob, KeyId, EncryptionContext):
        head, _, private = CiphertextBlob.partition(b"|")
        if json.loads(head)["ctx"] != EncryptionContext:
            raise Exception("InvalidCiphertextException")
        self.decrypts += 1
        return {"Plaintext": private}


def seal(capture_id, event, content_key):
    """An encrypted event.json, as the app writes it."""
    import base64
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    public = serialization.load_der_public_key(_pair()[0])
    wrapped = public.encrypt(content_key, padding.OAEP(
        mgf=padding.MGF1(algorithm=hashes.SHA256()), algorithm=hashes.SHA256(),
        label=f"tabcam:{capture_id}".encode()))
    nonce = os.urandom(12)
    sealed = nonce + AESGCM(content_key).encrypt(nonce, json.dumps(event).encode(), capture_id.encode())
    return json.dumps({
        "v": 1, "id": capture_id, "updated": event.get("updated", 1),
        "key": {"alg": "RSA-OAEP-256", "wrapped": base64.b64encode(wrapped).decode()},
        "sealed": base64.b64encode(sealed).decode(),
    }).encode()


def seed(clients, issuer, token, email, profile_id, identity):
    """A profile that's been around: its owner's sign-in and its identity."""
    st = clients["store"]
    st.save_profile({"id": profile_id, "createdAt": 1, "ownerSubject": f"{issuer}#{token}",
                     "ownerEmail": email, "identityId": identity})
    st.link(f"{issuer}#{token}", profile_id, email, "google" if issuer == GOOGLE else "apple")
    clients["cognito"].identities[profile_id] = identity


class ShareApiTest(unittest.TestCase):
    def setUp(self):
        self.clients = {"table": Table(), "cognito": Cognito(), "sts": Sts(),
                        "accounts": Accounts({OWNER: "julio@example.com",
                                              OTHER: "olga@example.com"}),
                        "store": store(), "rbacr": FakeRbacr(), "s3": S3(),
                        "links": KeyTable("keyHash", {"byOwner": "owner"}),
                        "captures": Captures(),
                        "kms": Kms()}
        self.clients["keys"] = self.clients["store"].keys
        self.objects = Objects()
        self.clients["s3_as"] = self.objects.as_
        keys.forget("brave_calm_otter")
        seed(self.clients, GOOGLE, "owner-token", "julio@example.com", "brave_calm_otter", OWNER)
        seed(self.clients, GOOGLE, "other-token", "olga@example.com", "quiet_bold_heron", OTHER)
        seed(self.clients, APPLE, "apple-owner-token", "riff@example.com", "shy_tall_lynx", APPLE_OWNER)

    def call(self, route, email, token="owner-token", path=None, query=None,
             body=None, verified="true", iss=None, aud=None):
        # The issuer the route's authorizer takes, unless the test says.
        if iss is None:
            where = route.split(" ", 1)[1]
            iss = (APPLE if where.startswith("/apple/") else
                   EMAIL_ISSUER if where.startswith("/email/") else GOOGLE)
        claims = {"iss": iss, "email_verified": verified, "sub": token}
        if aud is not None:
            claims["aud"] = aud
        if email is not None:
            claims["email"] = email
        event = {
            "routeKey": route,
            "headers": {"authorization": f"Bearer {token}"},
            "requestContext": {"authorizer": {"jwt": {"claims": claims}}},
            "pathParameters": path,
            "queryStringParameters": query,
            "body": json.dumps(body) if body is not None else None,
        }
        response = index.handler(event, None, self.clients)
        return response["statusCode"], json.loads(response["body"])

    def grant(self, email, role=None):
        body = {"email": email} if role is None else {"email": email, "role": role}
        return self.call("PUT /shares/{captureId}", "julio@example.com",
                         path={"captureId": "abc"}, body=body)

    def test_a_grant_is_to_read_and_is_listed(self):
        status, body = self.grant(" Ana@Example.com ")
        self.assertEqual(status, 200)
        self.assertEqual(body["grants"][0]["email"], "ana@example.com")
        self.assertEqual(body["grants"][0]["role"], "read")
        status, body = self.call("GET /shares/{captureId}", "julio@example.com",
                                 path={"captureId": "abc"})
        self.assertEqual([g["email"] for g in body["grants"]], ["ana@example.com"])

    def test_read_only_grants_and_bad_input(self):
        self.assertEqual(self.grant("bo@example.com", "read")[1]["grants"][0]["role"], "read")
        self.assertEqual(self.grant("bo@example.com", "admin")[0], 400)
        # Only the owner changes a capture: no grant to edit.
        self.assertEqual(self.grant("bo@example.com", "edit")[0], 400)
        self.assertEqual(self.grant("not an email")[0], 400)
        self.assertEqual(self.grant("julio@example.com")[0], 400)  # oneself
        status, _ = self.call("PUT /shares/{captureId}", "julio@example.com",
                              path={"captureId": "../x"}, body={"email": "a@b.co"})
        self.assertEqual(status, 400)

    def test_unverified_addresses_are_refused(self):
        status, _ = self.call("GET /shared", "ana@example.com", verified="false")
        self.assertEqual(status, 403)

    def test_the_grantee_lists_gets_credentials_and_leaves(self):
        self.grant("ana@example.com")
        status, body = self.call("GET /shared", "ana@example.com", token="ana")
        self.assertEqual(body["shared"], [{
            "owner": OWNER, "captureId": "abc",
            "ownerEmail": "julio@example.com", "role": "read"}])

        path = {"owner": OWNER, "captureId": "abc"}
        status, creds = self.call("POST /shared/{owner}/{captureId}/credentials",
                                  "ana@example.com", token="ana", path=path)
        self.assertEqual(status, 200)
        self.assertEqual(creds["prefix"], f"{OWNER}/events/abc/")
        policy = json.loads(self.clients["sts"].calls[0]["Policy"])
        objects = policy["Statement"][0]
        self.assertEqual(objects["Resource"],
                         f"arn:aws:s3:::nu01-user-events-1/{OWNER}/events/abc/*")
        self.assertEqual(objects["Action"], ["s3:GetObject"])

        self.call("DELETE /shared/{owner}/{captureId}", "ana@example.com",
                  token="ana", path=path)
        status, body = self.call("GET /shared", "ana@example.com", token="ana")
        self.assertEqual(body["shared"], [])

    def test_read_only_credentials_only_read(self):
        self.grant("bo@example.com", "read")
        self.call("POST /shared/{owner}/{captureId}/credentials", "bo@example.com",
                  token="bo", path={"owner": OWNER, "captureId": "abc"})
        actions = json.loads(self.clients["sts"].calls[0]["Policy"])["Statement"][0]["Action"]
        self.assertEqual(actions, ["s3:GetObject"])

    def test_no_grant_no_credentials(self):
        status, _ = self.call("POST /shared/{owner}/{captureId}/credentials",
                              "eve@example.com", token="eve",
                              path={"owner": OWNER, "captureId": "abc"})
        self.assertEqual(status, 404)
        self.assertEqual(self.clients["sts"].calls, [])

    def test_the_owner_revokes(self):
        self.grant("ana@example.com")
        status, body = self.call("DELETE /shares/{captureId}", "julio@example.com",
                                 path={"captureId": "abc"},
                                 query={"email": "ana@example.com"})
        self.assertEqual(body["grants"], [])

    def grants_left(self):
        return sorted(self.clients["table"].items)

    def share_both_ways(self):
        """Julio shares abc with Ana and Bo; Olga shares xyz with Julio and
        Ana."""
        self.grant("ana@example.com")
        self.grant("bo@example.com", "read")
        for email in ("julio@example.com", "ana@example.com"):
            self.call("PUT /shares/{captureId}", "olga@example.com",
                      token="other-token", path={"captureId": "xyz"},
                      body={"email": email})

    def test_deleting_the_account_deletes_only_the_callers_grants(self):
        self.share_both_ways()
        status, body = self.call("DELETE /account", "julio@example.com")
        self.assertEqual(status, 200)
        self.assertEqual(body, {"grantsMade": 2, "grantsToMe": 1, "links": 0, "captures": 0,
                                "contributions": 0, "appleTokensRevoked": False})
        # Olga's share with Ana stays; everything of Julio's is gone.
        self.assertEqual(self.grants_left(), [(f"{OTHER}#xyz", "ana@example.com")])
        self.assertEqual(self.clients["cognito"].deleted, [OWNER])
        self.assertEqual(self.clients["accounts"].items, {OTHER: "olga@example.com"})
        # Julio's shares are gone for Ana too.
        status, body = self.call("GET /shared", "ana@example.com", token="ana")
        self.assertEqual([s["owner"] for s in body["shared"]], [OTHER])

    def test_deleting_the_account_follows_every_page(self):
        self.clients["table"].page_size = 1
        self.share_both_ways()
        self.call("DELETE /account", "julio@example.com")
        self.assertEqual(self.grants_left(), [(f"{OTHER}#xyz", "ana@example.com")])

    def test_deleting_the_account_without_the_ocr_service(self):
        del self.clients["accounts"]
        self.grant("ana@example.com")
        status, _ = self.call("DELETE /account", "julio@example.com")
        self.assertEqual(status, 200)
        self.assertEqual(self.grants_left(), [])

    def test_an_identity_cognito_kept_is_an_error_to_retry(self):
        self.grant("ana@example.com")
        self.clients["cognito"].unprocessed = True
        status, body = self.call("DELETE /account", "julio@example.com")
        self.assertEqual(status, 502)
        self.assertIn("try again", body["message"])
        self.clients["cognito"].unprocessed = False
        status, _ = self.call("DELETE /account", "julio@example.com")
        self.assertEqual(status, 200)
        self.assertEqual(self.clients["cognito"].deleted, [OWNER])

    def test_an_unverified_address_deletes_nothing(self):
        self.share_both_ways()
        status, _ = self.call("DELETE /account", "julio@example.com",
                              verified="false")
        self.assertEqual(status, 403)
        self.assertEqual(len(self.grants_left()), 4)
        self.assertEqual(self.clients["cognito"].deleted, [])


    # Sign in with Apple: the same routes under /apple, with Apple's claims
    # (made up here, as the authorizer would pass them).

    def test_apple_routes_take_apple_tokens_and_their_own_identity(self):
        status, body = self.call("PUT /apple/shares/{captureId}", "riff@example.com",
                                 token="apple-owner-token", path={"captureId": "abc"},
                                 body={"email": "ana@example.com"})
        self.assertEqual(status, 200)
        item = self.clients["table"].items[(f"{APPLE_OWNER}#abc", "ana@example.com")]
        self.assertEqual(item["owner"], APPLE_OWNER)
        self.assertEqual(item["ownerEmail"], "riff@example.com")

    def test_apple_users_delete_their_account_under_apple(self):
        status, _ = self.call("PUT /apple/shares/{captureId}", "riff@example.com",
                              token="apple-owner-token", path={"captureId": "abc"},
                              body={"email": "ana@example.com"})
        self.assertEqual(status, 200)
        status, body = self.call("DELETE /apple/account", "riff@example.com",
                                 token="apple-owner-token")
        self.assertEqual(status, 200)
        self.assertEqual(body["grantsMade"], 1)
        self.assertEqual(self.clients["cognito"].deleted, [APPLE_OWNER])

    def apple_revoking(self, apple):
        from test_apple_revoke import made_up_key
        _, key = made_up_key()
        self.clients["apple_key"] = lambda: key
        self.clients["apple_open"] = apple
        os.environ["APPLE_CLIENT_ID"] = "com.nu01.tabcam"
        self.addCleanup(os.environ.pop, "APPLE_CLIENT_ID", None)

    def test_deleting_an_apple_account_revokes_its_apple_tokens(self):
        from test_apple_revoke import FakeApple
        apple = FakeApple(sub="apple-owner-token")
        self.apple_revoking(apple)
        status, body = self.call("DELETE /apple/account", "riff@example.com",
                                 token="apple-owner-token",
                                 body={"appleAuthorizationCode": "c0de.1"})
        self.assertEqual(status, 200)
        self.assertTrue(body["appleTokensRevoked"])
        self.assertEqual([u for u, _ in apple.calls],
                         ["https://appleid.apple.com/auth/token",
                          "https://appleid.apple.com/auth/revoke"])
        self.assertEqual(self.clients["cognito"].deleted, [APPLE_OWNER])

    def test_an_android_apple_account_revokes_with_the_services_id(self):
        from test_apple_revoke import FakeApple
        apple = FakeApple(sub="apple-owner-token")
        self.apple_revoking(apple)
        os.environ["APPLE_SERVICES_ID"] = "com.nu01.tabcam.signin"
        self.addCleanup(os.environ.pop, "APPLE_SERVICES_ID", None)
        status, body = self.call("DELETE /apple/account", "riff@example.com",
                                 token="apple-owner-token", aud="com.nu01.tabcam.signin",
                                 body={"appleAuthorizationCode": "c0de.1"})
        self.assertEqual(status, 200)
        self.assertTrue(body["appleTokensRevoked"])
        self.assertEqual({f["client_id"] for _, f in apple.calls}, {"com.nu01.tabcam.signin"})

    def test_an_unknown_audience_revokes_with_the_bundle_id(self):
        from test_apple_revoke import FakeApple
        apple = FakeApple(sub="apple-owner-token")
        self.apple_revoking(apple)
        status, _ = self.call("DELETE /apple/account", "riff@example.com",
                              token="apple-owner-token", aud="com.example.other",
                              body={"appleAuthorizationCode": "c0de.1"})
        self.assertEqual(status, 200)
        self.assertEqual({f["client_id"] for _, f in apple.calls}, {"com.nu01.tabcam"})

    def test_apple_refusing_to_revoke_deletes_nothing(self):
        from test_apple_revoke import FakeApple
        self.apple_revoking(FakeApple(sub="apple-owner-token", token_status=400))
        status, _ = self.call("DELETE /apple/account", "riff@example.com",
                              token="apple-owner-token",
                              body={"appleAuthorizationCode": "c0de"})
        self.assertEqual(status, 502)
        self.assertEqual(self.clients["cognito"].deleted, [])

    def test_another_apple_ids_code_deletes_nothing(self):
        from test_apple_revoke import FakeApple
        self.apple_revoking(FakeApple(sub="someone-else"))
        status, _ = self.call("DELETE /apple/account", "riff@example.com",
                              token="apple-owner-token",
                              body={"appleAuthorizationCode": "c0de"})
        self.assertEqual(status, 502)
        self.assertEqual(self.clients["cognito"].deleted, [])

    def test_without_the_apple_key_the_account_is_deleted_unrevoked(self):
        self.clients["apple_key"] = lambda: None
        status, body = self.call("DELETE /apple/account", "riff@example.com",
                                 token="apple-owner-token",
                                 body={"appleAuthorizationCode": "c0de"})
        self.assertEqual(status, 200)
        self.assertFalse(body["appleTokensRevoked"])
        status, _ = self.call("DELETE /apple/account", "riff@example.com",
                              token="apple-owner-token",
                              body={"appleAuthorizationCode": "not a code!"})
        self.assertEqual(status, 400)

    def test_apple_users_get_what_is_shared_with_their_address(self):
        self.grant("x7k2@privaterelay.appleid.com", "read")
        status, body = self.call("GET /apple/shared", "X7K2@privaterelay.appleid.com",
                                 token="apple-ana")
        self.assertEqual(status, 200)
        self.assertEqual(body["shared"][0]["role"], "read")
        path = {"owner": OWNER, "captureId": "abc"}
        status, creds = self.call("POST /apple/shared/{owner}/{captureId}/credentials",
                                  "x7k2@privaterelay.appleid.com", token="apple-ana",
                                  path=path)
        self.assertEqual(status, 200)
        self.assertEqual(creds["role"], "read")

    def test_apple_email_verified_may_be_a_boolean_or_a_string(self):
        for verified in (True, "true", "TRUE"):
            status, _ = self.call("GET /apple/shared", "riff@example.com",
                                  token="apple-ana", verified=verified)
            self.assertEqual(status, 200, verified)
        for verified in (False, "false", None):
            status, _ = self.call("GET /apple/shared", "riff@example.com",
                                  token="apple-ana", verified=verified)
            self.assertEqual(status, 403, verified)

    def test_a_token_must_be_its_paths_issuer(self):
        # A Google token on an Apple path, an Apple token on a Google path,
        # anyone else's anywhere: refused before anything is read.
        for route, iss in (("GET /apple/shared", "https://accounts.google.com"),
                           ("GET /shared", "https://appleid.apple.com"),
                           ("GET /shared", "https://evil.example"),
                           ("GET /apple/shared", "")):
            status, _ = self.call(route, "riff@example.com", iss=iss)
            self.assertEqual(status, 401, (route, iss))
        self.assertEqual(self.clients["cognito"].tokens, [])
        self.assertEqual(len(self.clients["store"].subjects.items), 3)

    def test_email_sign_ins_use_the_email_routes_with_the_pools_tokens(self):
        # A first request makes the email sign-in's profile, as Google's.
        status, body = self.call("GET /email/profile", "Mia@Example.com", token="email-mia",
                                 verified=True)
        self.assertEqual(status, 200)
        subject = f"{EMAIL_ISSUER}#email-mia"
        self.assertIn(subject, self.clients["store"].subjects.items)
        # A Google token on an email path, or the pool's on a Google one: no.
        for route, iss in (("GET /email/shared", GOOGLE),
                           ("GET /shared", EMAIL_ISSUER),
                           ("GET /email/shared", APPLE)):
            status, _ = self.call(route, "mia@example.com", token="email-mia", iss=iss)
            self.assertEqual(status, 401, (route, iss))

    def test_deleting_an_email_account_deletes_its_pool_user(self):
        deleted = []

        class Idp:
            def admin_delete_user(self, UserPoolId, Username):
                deleted.append((UserPoolId, Username))

        self.clients["cognito_idp"] = Idp()
        status, _ = self.call("GET /email/profile", "mia@example.com", token="email-mia")
        self.assertEqual(status, 200)
        status, _ = self.call("DELETE /email/account", "mia@example.com", token="email-mia")
        self.assertEqual(status, 200)
        self.assertEqual(deleted, [("us-east-1_Email", "email-mia")])

    def test_deleting_a_google_account_deletes_no_pool_user(self):
        deleted = []

        class Idp:
            def admin_delete_user(self, UserPoolId, Username):
                deleted.append(Username)

        self.clients["cognito_idp"] = Idp()
        status, _ = self.call("DELETE /account", "julio@example.com")
        self.assertEqual(status, 200)
        self.assertEqual(deleted, [])

    def test_an_apple_token_without_an_email_is_refused(self):
        status, body = self.call("GET /apple/shared", None, token="apple-ana")
        self.assertEqual(status, 403)
        self.assertIn("email", body["message"])

    def test_unknown_apple_routes_are_not_found(self):
        status, _ = self.call("GET /apple/other", "riff@example.com", token="apple-ana")
        self.assertEqual(status, 404)

    # --- links: anyone with a capture's link reads it --------------------

    KEY = "riffkey-0123456789abcdefghijklmnopqrstu"

    def publish(self, key=None, capture="abc", token="owner-token", email="julio@example.com"):
        return self.call("PUT /links/{captureId}", email, token=token,
                         path={"captureId": capture}, body={"key": key or self.KEY})

    def open_link(self, capture="abc", key=None, body=None):
        event = {
            "routeKey": index.PUBLIC_ROUTE,
            "pathParameters": {"captureId": capture},
            "body": json.dumps(body if body is not None else {"key": key or self.KEY}),
        }
        response = index.handler(event, None, self.clients)
        return response["statusCode"], json.loads(response["body"])

    # --- profile keys: captures encrypted at rest --------------------------

    CONTENT_KEY = bytes(range(32))

    def store_capture(self, capture="abc", event=None, owner=OWNER):
        """The capture's event.json in its owner's folder, encrypted with
        CONTENT_KEY (or [event] as is, when it's bytes)."""
        body = event if isinstance(event, bytes) else seal(
            capture, event or {"id": capture, "title": "Morning riff"}, self.CONTENT_KEY)
        self.objects.objects[f"{owner}/events/{capture}/event.json"] = body

    def key_of(self, token="owner-token", email="julio@example.com", capture="abc", owner=OWNER):
        return self.call("POST /keys/{owner}/{captureId}", email, token=token,
                         path={"owner": owner, "captureId": capture})

    def test_a_profile_has_its_keys_from_its_first_request(self):
        status, body = self.call("GET /profile", "julio@example.com")
        self.assertEqual(status, 200)
        self.assertEqual(body["keyAlgorithm"], "RSA-OAEP-256")
        from cryptography.hazmat.primitives import serialization
        import base64
        public = serialization.load_der_public_key(base64.b64decode(body["publicKey"]))
        self.assertEqual(public.key_size, 3072)
        # Made once, kept: the same key at every request.
        made = self.clients["kms"].made
        self.assertEqual(self.call("GET /profile", "julio@example.com")[1]["publicKey"], body["publicKey"])
        self.assertEqual(self.clients["kms"].made, made)
        # Kept: the public key, and the private key only wrapped by KMS.
        item = self.clients["keys"].items["brave_calm_otter"]
        self.assertEqual(set(item), {"profileId", "publicKey", "privateKeyWrapped", "keySpec", "createdAt"})

    def test_a_new_profile_gets_keys_at_its_first_sign_in(self):
        self.call("GET /shared", "new@example.com", token="new-token")
        profile = self.clients["store"].link_of("https://accounts.google.com#new-token")["profileId"]
        self.assertIn(profile, self.clients["keys"].items)

    def test_the_owner_and_people_its_shared_with_get_the_content_key(self):
        import base64
        self.call("GET /profile", "julio@example.com")
        self.store_capture()
        status, body = self.key_of()
        self.assertEqual(status, 200, body)
        self.assertEqual(base64.b64decode(body["contentKey"]), self.CONTENT_KEY)
        # Read with the folder's read-only credentials.
        self.assertEqual(self.objects.reads[-1], "ASIA")
        # Someone it isn't shared with: nothing.
        self.assertEqual(self.key_of("other-token", "olga@example.com")[0], 404)
        self.grant("olga@example.com", "read")
        status, body = self.key_of("other-token", "olga@example.com")
        self.assertEqual(status, 200, body)
        self.assertEqual(base64.b64decode(body["contentKey"]), self.CONTENT_KEY)

    def test_a_wrapped_key_only_opens_its_own_capture(self):
        self.call("GET /profile", "julio@example.com")
        self.store_capture("abc")
        # The other capture's event.json carries abc's wrapped key.
        abc = json.loads(self.objects.objects[f"{OWNER}/events/abc/event.json"])
        self.store_capture("xyz", json.dumps({"id": "xyz", "key": abc["key"], "sealed": abc["sealed"]}).encode())
        self.assertEqual(self.key_of(capture="xyz")[0], 409)

    def test_a_capture_that_isnt_encrypted_has_no_key(self):
        self.call("GET /profile", "julio@example.com")
        self.store_capture(event=json.dumps({"id": "abc", "title": "Old riff"}).encode())
        self.assertEqual(self.key_of()[0], 404)
        self.assertEqual(self.key_of(capture="nothere")[0], 404)

    def test_a_link_opens_an_encrypted_capture_with_its_key(self):
        import base64
        self.call("GET /profile", "julio@example.com")
        self.publish()
        self.store_capture()
        status, creds = self.open_link()
        self.assertEqual(status, 200)
        self.assertEqual(base64.b64decode(creds["contentKey"]), self.CONTENT_KEY)
        # Not encrypted (yet): no key, as before.
        self.store_capture(event=json.dumps({"id": "abc"}).encode())
        self.assertNotIn("contentKey", self.open_link()[1])

    def test_a_link_previews_an_encrypted_capture(self):
        self.call("GET /profile", "julio@example.com")
        self.publish()
        self.store_capture(event=None)
        event = {
            "routeKey": index.PREVIEW_ROUTE,
            "pathParameters": {"captureId": "abc", "key": self.KEY},
            "headers": {},
        }
        page = index.handler(event, None, self.clients)["body"]
        self.assertIn('<meta property="og:title" content="Morning riff">', page)

    def test_deleting_the_account_deletes_its_keys(self):
        self.call("GET /profile", "julio@example.com")
        self.assertIn("brave_calm_otter", self.clients["keys"].items)
        self.assertEqual(self.call("DELETE /account", "julio@example.com")[0], 200)
        self.assertNotIn("brave_calm_otter", self.clients["keys"].items)

    def test_the_sealed_formats_open(self):
        import struct
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
        import sealed
        key = self.CONTENT_KEY
        event = json.loads(seal("abc", {"id": "abc", "title": "Riff"}, key))
        self.assertEqual(sealed.open_event(event, key)["title"], "Riff")
        with self.assertRaises(sealed.SealError):
            sealed.open_event(event, bytes(32))
        # A file of three chunks (5 bytes each, the last short).
        data, prefix, aes = b"e|--3--5--7--|", b"\x01" * 7, AESGCM(key)
        aad = sealed.file_aad("abc", "p1.img")
        chunks = [data[i:i + 5] for i in range(0, len(data), 5)]
        blob = b"TSE1" + struct.pack(">I", 5) + prefix + b"".join(
            aes.encrypt(prefix + struct.pack(">IB", n, 1 if n == len(chunks) - 1 else 0), c, aad)
            for n, c in enumerate(chunks))
        self.assertEqual(sealed.open_file(blob, key, "abc", "p1.img"), data)
        # Another file's name, or a chunk dropped: it doesn't open.
        with self.assertRaises(sealed.SealError):
            sealed.open_file(blob, key, "abc", "p2.img")
        with self.assertRaises(sealed.SealError):
            sealed.open_file(blob[:-21], key, "abc", "p1.img")

    # --- link previews: chat apps' crawlers see the capture's title --------

    def preview(self, capture="abc", key=None, site=None, capture_json=None):
        """GET /preview/{captureId}/{key}, with [capture_json] as the
        capture's event.json; the page, and the S3 credentials it read with."""
        used = []

        class Objects:
            def get_object(self, Bucket, Key):
                used.append(Key)
                import io
                return {"Body": io.BytesIO(json.dumps(capture_json or {}).encode())}

        def s3_as(creds):
            used.append(creds["accessKeyId"])
            return Objects()

        self.clients["s3_as"] = s3_as
        event = {
            "routeKey": index.PREVIEW_ROUTE,
            "pathParameters": {"captureId": capture, "key": key or self.KEY},
            "headers": {"X-TabCam-Site": site} if site else {},
        }
        response = index.handler(event, None, self.clients)
        self.assertEqual(response["statusCode"], 200)
        self.assertIn("text/html", response["headers"]["content-type"])
        self.response = response
        return response["body"], used

    RIFF = {
        "id": "abc", "title": "Morning <riff>", "artist": "Me",
        "pages": [{"id": "p1", "kind": "image"}, {"id": "p2", "kind": "image"},
                  {"id": "p3", "kind": "pdf"}, {"id": "p4", "kind": "link"}],
        "tabText": "e|--3--5--|",
    }

    def test_a_links_preview_has_the_captures_title_and_contents(self):
        self.publish()
        page, used = self.preview(capture_json=self.RIFF, site="rc.tabcam.nu01.com")
        # Escaped, with the artist; what it holds.
        self.assertIn('<meta property="og:title" content="Morning &lt;riff&gt; – Me">', page)
        self.assertIn("<title>Morning &lt;riff&gt; – Me</title>", page)
        self.assertIn('content="Me · 2 pages, 1 PDF, 1 link, a text tab. Shared with tabs.cam."', page)
        # Its short link, on the site that asked.
        link = f"https://rc.tabcam.nu01.com/s/{self.KEY}"
        self.assertIn(f'<meta property="og:url" content="{link}">', page)
        # Read with the link's own read-only credentials, its folder alone.
        self.assertEqual(used, ["ASIA", f"{OWNER}/events/abc/event.json"])
        policy = json.loads(self.clients["sts"].calls[-1]["Policy"])
        self.assertEqual(policy["Statement"][0]["Action"], ["s3:GetObject"])

    def test_a_wrong_key_previews_as_tabcam_and_reads_nothing(self):
        self.publish()
        page, used = self.preview(key="x" * 32, capture_json=self.RIFF)
        self.assertIn('<meta property="og:title" content="tabs.cam">', page)
        self.assertNotIn("riff", page)
        self.assertEqual(used, [])
        # Another site than ours: production's is named.
        page, _ = self.preview(key="x" * 32, site="evil.example.com")
        self.assertIn("https://tabs.cam/app/", page)
        # The old name still is ours (it redirects, path and query kept).
        page, _ = self.preview(key="x" * 32, site="tabcam.nu01.com")
        self.assertIn("https://tabcam.nu01.com/app/", page)
        self.assertNotIn("evil", page)

    # --- short links: /s/<key> redirects to the full link -------------------

    def short(self, key, query=None, site=None):
        """GET /s/{key} (from [site]'s CloudFront): its status and headers."""
        event = {"routeKey": index.SHORT_ROUTE, "pathParameters": {"key": key},
                 "queryStringParameters": query,
                 "headers": {"x-tabcam-site": site} if site else {}}
        response = index.handler(event, None, self.clients)
        return response["statusCode"], response["headers"]

    def test_a_short_link_redirects_to_the_full_one(self):
        self.publish()
        status, headers = self.short(self.KEY)
        self.assertEqual(status, 302)
        self.assertEqual(headers["location"], f"/app/?c=abc&k={self.KEY}")
        self.assertEqual(headers["cache-control"], "public, max-age=86400")
        # A file's keeps its ID; a bad one is dropped.
        _, headers = self.short(self.KEY, {"f": "p1"})
        self.assertEqual(headers["location"], f"/app/?c=abc&k={self.KEY}&f=p1")
        _, headers = self.short(self.KEY, {"f": "../x"})
        self.assertEqual(headers["location"], f"/app/?c=abc&k={self.KEY}")
        # A file's edit view keeps e=1, only with a file.
        _, headers = self.short(self.KEY, {"f": "p1", "e": "1"})
        self.assertEqual(headers["location"], f"/app/?c=abc&k={self.KEY}&f=p1&e=1")
        _, headers = self.short(self.KEY, {"e": "1"})
        self.assertEqual(headers["location"], f"/app/?c=abc&k={self.KEY}")
        _, headers = self.short(self.KEY, {"f": "p1", "e": "yes"})
        self.assertEqual(headers["location"], f"/app/?c=abc&k={self.KEY}&f=p1")
        # HEAD too.
        event = {"routeKey": "HEAD /s/{key}", "pathParameters": {"key": self.KEY}}
        response = index.handler(event, None, self.clients)
        self.assertEqual(response["headers"]["location"], f"/app/?c=abc&k={self.KEY}")

    def test_a_12_character_key_makes_a_short_link(self):
        key = "Ab3dEf9hJk2L"
        self.assertEqual(self.publish(key=key)[0], 200)
        _, headers = self.short(key)
        self.assertEqual(headers["location"], f"/app/?c=abc&k={key}")

    def test_an_unknown_short_link_goes_to_the_app_briefly_cached(self):
        self.publish()
        for key in ("x" * 12, "Ab3dEf9hJk2", "<script>", ""):
            status, headers = self.short(key)
            self.assertEqual(status, 302)
            self.assertEqual(headers["location"], "/app/")
            self.assertEqual(headers["cache-control"], "public, max-age=60")

    def test_only_a_public_captures_short_link_on_tabs_cam_is_indexed(self):
        self.publish()
        _, headers = self.short(self.KEY, site="tabs.cam")
        self.assertEqual(headers["x-robots-tag"], "noindex")  # unlisted
        self.visible("public", title="Morning Riff")
        _, headers = self.short(self.KEY, site="tabs.cam")
        self.assertNotIn("x-robots-tag", headers)
        self.assertEqual(headers["location"], f"/app/?c=abc&k={self.KEY}")
        for site in ("rc.tabs.cam", None):
            _, headers = self.short(self.KEY, site=site)
            self.assertEqual(headers["x-robots-tag"], "noindex", site)
        self.visible("private")
        _, headers = self.short(self.KEY, site="tabs.cam")
        self.assertEqual(headers["x-robots-tag"], "noindex")
        # Private still redirects: the owner opens their own link.
        self.assertEqual(headers["location"], f"/app/?c=abc&k={self.KEY}")

    def test_a_deleted_capture_previews_as_tabcam(self):
        self.publish()
        page, _ = self.preview(capture_json={"id": "abc", "deleted": 1})
        self.assertIn('<meta property="og:title" content="tabs.cam">', page)

    def test_a_malformed_link_previews_as_tabcam(self):
        page, used = self.preview(capture="<script>", key="k")
        self.assertIn('<meta property="og:title" content="tabs.cam">', page)
        self.assertEqual(page.count("<script>"), 1)  # the page's own alone
        self.assertEqual(used, [])

    def test_a_published_link_gives_anyone_read_only_credentials(self):
        self.assertEqual(self.publish()[0], 200)
        self.assertEqual(self.publish()[0], 200)  # again: the same
        # Only the key's hash is kept.
        self.assertNotIn(self.KEY, json.dumps(list(self.clients["links"].items.values()), default=str))
        status, creds = self.open_link()
        self.assertEqual(status, 200)
        self.assertEqual(creds["owner"], OWNER)
        self.assertEqual(creds["role"], "read")
        self.assertEqual(creds["prefix"], f"{OWNER}/events/abc/")
        policy = json.loads(self.clients["sts"].calls[-1]["Policy"])
        self.assertEqual(policy["Statement"][0]["Action"], ["s3:GetObject"])
        self.assertEqual(policy["Statement"][0]["Resource"],
                         f"arn:aws:s3:::nu01-user-events-1/{OWNER}/events/abc/*")

    def test_a_wrong_key_or_capture_opens_nothing(self):
        self.publish()
        self.assertEqual(self.open_link(key="riffkey-wrong-0123456789abcdefghijklmn")[0], 404)
        self.assertEqual(self.open_link(capture="xyz")[0], 404)
        self.assertEqual(self.open_link(key="short")[0], 400)
        self.assertEqual(self.open_link(capture="../x")[0], 400)
        self.assertEqual(self.open_link(body=[])[0], 400)
        self.assertEqual(self.clients["sts"].calls, [])

    def test_a_key_is_one_captures(self):
        self.publish()
        self.assertEqual(self.publish(capture="xyz")[0], 409)
        self.assertEqual(self.publish(token="other-token", email="olga@example.com")[0], 409)
        self.assertEqual(self.publish(key="bad key")[0], 400)

    # --- contributions ------------------------------------------------------

    def reader_credentials(self, email="bo@example.com", token="bo"):
        return self.call("POST /shared/{owner}/{captureId}/credentials", email,
                         token=token, path={"owner": OWNER, "captureId": "abc"})

    def test_a_readers_credentials_add_their_own_contribution_alone(self):
        self.grant("bo@example.com", "read")
        status, creds = self.reader_credentials()
        self.assertEqual(status, 200)
        bo = self.clients["cognito"].identities[next(
            p for p, _ in self.clients["cognito"].identities.items()
            if p not in ("brave_calm_otter", "quiet_bold_heron", "shy_tall_lynx"))]
        mine = f"{OWNER}/contrib/abc/{bo}/"
        self.assertEqual(creds["contribPrefix"], mine)
        statements = json.loads(self.clients["sts"].calls[-1]["Policy"])["Statement"]
        # The owner's files: read only. Their own folder: read and write.
        self.assertEqual(statements[0]["Action"], ["s3:GetObject"])
        self.assertEqual(statements[1]["Resource"], f"arn:aws:s3:::nu01-user-events-1/{mine}*")
        self.assertIn("s3:PutObject", statements[1]["Action"])
        listed = statements[2]["Condition"]["StringLike"]["s3:prefix"]
        self.assertEqual(listed, [f"{OWNER}/events/abc/", f"{OWNER}/events/abc/*", mine, f"{mine}*"])
        # No other reader's folder, nor the contributions' root.
        self.assertFalse(any(f"{OWNER}/contrib/abc/*" == r or r.endswith("/contrib/*")
                             for st in statements for r in [st["Resource"]]))
        # The owner learns whose folder it is.
        _, body = self.call("GET /shares/{captureId}", "julio@example.com", path={"captureId": "abc"})
        self.assertEqual(body["grants"][0]["identity"], bo)
        # A role change keeps it.
        _, body = self.grant("bo@example.com", "read")
        self.assertEqual(body["grants"][0]["identity"], bo)

    def test_a_grant_made_to_edit_before_is_read_only(self):
        self.clients["table"].put_item(Item={
            "capture": f"{OWNER}#abc", "email": "ana@example.com", "owner": OWNER,
            "captureId": "abc", "ownerEmail": "julio@example.com", "role": "edit",
            "grantedAt": 1})
        _, shared = self.call("GET /shared", "ana@example.com", token="ana")
        self.assertEqual(shared["shared"][0]["role"], "read")
        _, grants = self.call("GET /shares/{captureId}", "julio@example.com",
                              path={"captureId": "abc"})
        self.assertEqual(grants["grants"][0]["role"], "read")
        _, creds = self.reader_credentials("ana@example.com", "ana")
        self.assertEqual(creds["role"], "read")
        statements = json.loads(self.clients["sts"].calls[-1]["Policy"])["Statement"]
        self.assertEqual(statements[0]["Action"], ["s3:GetObject"])
        self.assertFalse(any("s3:PutObject" in st["Action"] for st in statements
                             if f"/events/abc/" in str(st["Resource"])))

    def join(self, email="kim@example.com", token="kim", key=None, capture="abc"):
        return self.call("POST /links/{captureId}/join", email, token=token,
                         path={"captureId": capture}, body={"key": key or self.KEY})

    def test_signed_in_people_join_by_the_link_as_readers(self):
        self.publish()
        status, body = self.join()
        self.assertEqual(status, 200)
        self.assertEqual(body, {"owner": OWNER, "captureId": "abc",
                                "ownerEmail": "julio@example.com", "role": "read"})
        self.assertEqual(self.join()[1]["role"], "read")  # again: the same
        _, shared = self.call("GET /shared", "kim@example.com", token="kim")
        self.assertEqual(shared["shared"], [{"owner": OWNER, "captureId": "abc",
                                             "ownerEmail": "julio@example.com", "role": "read"}])
        _, creds = self.reader_credentials("kim@example.com", "kim")
        self.assertIn("/contrib/abc/", creds["contribPrefix"])
        _, grants = self.call("GET /shares/{captureId}", "julio@example.com", path={"captureId": "abc"})
        self.assertEqual(grants["grants"][0]["via"], "link")

    def test_joining_keeps_what_the_owner_and_editors_have(self):
        self.publish()
        self.assertEqual(self.join("julio@example.com", "owner-token")[1]["own"], True)
        self.grant("ana@example.com")
        self.assertEqual(self.join("ana@example.com", "ana")[1]["role"], "read")
        self.assertEqual(len(self.clients["table"].items), 1)

    def test_a_wrong_link_joins_nothing(self):
        self.publish()
        self.assertEqual(self.join(key="riffkey-wrong-0123456789abcdefghijklmn")[0], 404)
        self.assertEqual(self.join(capture="xyz")[0], 404)
        self.assertEqual(self.join(key="short")[0], 400)
        self.assertEqual(self.clients["table"].items, {})

    def test_people_who_joined_dont_count_toward_the_email_limit(self):
        self.publish()
        old_grants, old_joins = index.MAX_GRANTS, index.MAX_JOINS
        index.MAX_GRANTS, index.MAX_JOINS = 1, 2
        try:
            self.join("kim@example.com", "kim")
            self.join("lee@example.com", "lee")
            self.assertEqual(self.join("max@example.com", "max")[0], 409)
            self.assertEqual(self.grant("ana@example.com")[0], 200)
            self.assertEqual(self.grant("bo@example.com")[0], 400)
        finally:
            index.MAX_GRANTS, index.MAX_JOINS = old_grants, old_joins

    def test_deleting_the_account_deletes_its_contributions_alone(self):
        self.publish()
        self.join()
        _, creds = self.reader_credentials("kim@example.com", "kim")
        mine = creds["contribPrefix"]
        theirs = f"{OWNER}/contrib/abc/us-east-1:99999999-0000-0000-0000-000000000000/"
        self.clients["s3"].keys = [f"{mine}contrib.json", f"{mine}a.mp4", f"{mine}b.jpg",
                                   f"{theirs}contrib.json", f"{OWNER}/events/abc/event.json"]
        status, body = self.call("DELETE /account", "kim@example.com", token="kim")
        self.assertEqual(status, 200)
        self.assertEqual(body["contributions"], 3)
        self.assertEqual(self.clients["s3"].keys,
                         [f"{theirs}contrib.json", f"{OWNER}/events/abc/event.json"])

    def test_deleting_the_account_deletes_its_links(self):
        self.publish()
        self.call("PUT /links/{captureId}", "olga@example.com", token="other-token",
                  path={"captureId": "xyz"}, body={"key": "olgakey-0123456789abcdefghijklmnopqrstu"})
        status, body = self.call("DELETE /account", "julio@example.com")
        self.assertEqual(body["links"], 1)
        self.assertEqual(self.open_link()[0], 404)
        status, _ = self.open_link(capture="xyz", key="olgakey-0123456789abcdefghijklmnopqrstu")
        self.assertEqual(status, 200)

    # --- visibility: a link is private, unlisted or public --------------------

    def visible(self, visibility, capture="abc", key=None, token="owner-token",
                email="julio@example.com", **fields):
        """PUT /links/{captureId} with a visibility (and a title, an artist)."""
        body = {"key": key or self.KEY, "visibility": visibility, **fields}
        return self.call("PUT /links/{captureId}", email, token=token,
                         path={"captureId": capture}, body=body)

    def kept(self, capture="abc", owner=OWNER):
        """The capture's item in the captures table, or None."""
        return self.clients["captures"].items.get(f"{owner}#{capture}")

    def find(self, q):
        """GET /public?q=, without a token: the captures found."""
        event = {"routeKey": index.SEARCH_ROUTE,
                 "queryStringParameters": None if q is None else {"q": q}}
        response = index.handler(event, None, self.clients)
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(response["headers"]["cache-control"], "public, max-age=60")
        return json.loads(response["body"])["captures"]

    def site_map(self, site=None):
        """GET /sitemap.xml as the site's CloudFront asks: its URLs."""
        import xml.etree.ElementTree as ET
        event = {"routeKey": index.SITEMAP_ROUTE,
                 "headers": {"x-tabcam-site": site} if site else {}}
        response = index.handler(event, None, self.clients)
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(response["headers"]["content-type"], "application/xml")
        self.assertEqual(response["headers"]["cache-control"], "public, max-age=3600")
        ns = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9"}
        root = ET.fromstring(response["body"])
        return [(u.find("s:loc", ns).text, u.find("s:lastmod", ns).text)
                for u in root.findall("s:url", ns)]

    def published(self, capture, title, artist="", when=0, visibility="public",
                  token="owner-token", email="julio@example.com", owner=OWNER):
        """A capture made [visibility] with its title and artist, changed
        [when] seconds after 1_800_000_000; its key."""
        key = f"{capture}key-0123456789ab"
        status, _ = self.visible(visibility, capture=capture, key=key, title=title,
                                 artist=artist, token=token, email=email)
        self.assertEqual(status, 200)
        self.kept(capture, owner)["updatedAt"] = Decimal(1_800_000_000 + when)
        return key

    def test_an_older_apps_link_is_unlisted(self):
        status, body = self.publish()  # the key alone
        self.assertEqual((status, body), (200, {"published": True, "visibility": "unlisted"}))
        self.assertEqual(self.kept()["visibility"], "unlisted")
        self.assertEqual(set(self.kept()), {"capture", "owner", "captureId", "visibility", "updatedAt"})
        # A link from before visibilities (nothing in the table): unlisted.
        self.clients["captures"].items.clear()
        self.assertEqual(self.open_link()[0], 200)
        self.assertEqual(self.join()[0], 200)

    def test_a_links_visibility_is_kept_and_changed(self):
        for visibility in ("private", "public", "unlisted", "private"):
            status, body = self.visible(visibility)
            self.assertEqual((status, body), (200, {"published": True, "visibility": visibility}))
            item = self.kept()
            self.assertEqual((item["visibility"], item["owner"], item["captureId"]),
                             (visibility, OWNER, "abc"))
        for bad in ("secret", "PUBLIC", "", 3, ["public"]):
            self.assertEqual(self.visible(bad)[0], 400, bad)
        self.assertEqual(self.visible("public", title=3)[0], 400)
        self.assertEqual(self.kept()["visibility"], "private")
        # Another capture's key: nothing kept for this one.
        self.assertEqual(self.visible("public", capture="xyz")[0], 409)
        self.assertIsNone(self.kept("xyz"))

    def test_a_private_capture_opens_for_its_owner_alone(self):
        self.visible("private")
        status, body = self.open_link()
        self.assertEqual((status, body["message"]), (403, "That capture is private"))
        self.assertEqual(self.clients["sts"].calls, [])
        status, body = self.join()
        self.assertEqual((status, body["message"]), (403, "That capture is private"))
        self.assertEqual(self.clients["table"].items, {})
        self.assertEqual(self.join("julio@example.com", "owner-token")[1]["own"], True)
        # Its preview is tabs.cam's own, and never indexed.
        page, used = self.preview(capture_json=self.RIFF, site="tabs.cam")
        self.assertIn('<meta property="og:title" content="tabs.cam">', page)
        self.assertIn('<meta property="og:url" content="https://tabs.cam/app/">', page)
        self.assertNotIn("Morning", page)
        self.assertEqual(used, [])
        self.assertEqual(self.response["headers"]["x-robots-tag"], "noindex")
        # The short link still goes to the app, which says it's private.
        self.assertEqual(self.short(self.KEY)[1]["location"], f"/app/?c=abc&k={self.KEY}")
        # Unlisted again: the same key opens it.
        self.visible("unlisted")
        self.assertEqual(self.open_link()[0], 200)
        self.assertEqual(self.join()[0], 200)

    def test_a_private_capture_suspends_every_grant_until_it_isnt(self):
        self.call("GET /profile", "julio@example.com")
        self.store_capture()
        self.publish()
        self.grant("olga@example.com")  # by email, before
        self.join()  # Kim, by the link
        readers = (("olga@example.com", "other-token"), ("kim@example.com", "kim"))
        self.assertEqual(self.visible("private")[0], 200)
        for email, token in readers:
            self.assertEqual(self.call("GET /shared", email, token=token)[1]["shared"], [])
            self.assertEqual(self.reader_credentials(email, token)[0], 404)
        self.assertEqual(self.key_of("other-token", "olga@example.com")[0], 404)
        self.assertEqual(self.key_of()[0], 200)  # its owner's, still
        _, grants = self.call("GET /shares/{captureId}", "julio@example.com", path={"captureId": "abc"})
        self.assertEqual([g.get("suspended") for g in grants["grants"]], [True, True])
        # Not private any more: the same grants work again.
        self.assertEqual(self.visible("unlisted")[0], 200)
        for email, token in readers:
            shared = self.call("GET /shared", email, token=token)[1]["shared"]
            self.assertEqual([(s["owner"], s["captureId"]) for s in shared], [(OWNER, "abc")])
            self.assertEqual(self.reader_credentials(email, token)[0], 200)
        self.assertEqual(self.key_of("other-token", "olga@example.com")[0], 200)
        self.assertFalse(any("suspended" in i for i in self.clients["table"].items.values()))
        # Public lifts it the same way.
        self.visible("private")
        self.visible("public", title="Morning Riff")
        self.assertEqual(self.reader_credentials("kim@example.com", "kim")[0], 200)

    def test_a_grant_to_a_private_capture_waits_until_it_isnt(self):
        self.visible("private")
        self.grant("ana@example.com")
        self.assertEqual(self.call("GET /shared", "ana@example.com", token="ana")[1]["shared"], [])
        self.visible("unlisted")
        self.assertEqual(len(self.call("GET /shared", "ana@example.com", token="ana")[1]["shared"]), 1)

    def test_grants_are_looked_at_only_when_private_comes_or_goes(self):
        self.grant("ana@example.com")
        table = self.clients["table"]
        before = table.queries
        self.publish()
        for visibility in ("unlisted", "public", "public", "unlisted"):
            self.visible(visibility, title="Morning Riff")
        self.assertEqual(table.queries, before)
        self.visible("private")
        self.assertEqual(table.queries, before + 1)
        self.visible("private")
        self.assertEqual(table.queries, before + 1)
        self.visible("public")
        self.assertEqual(table.queries, before + 2)

    def test_a_reader_who_left_meanwhile_isnt_granted_again(self):
        self.publish()
        table = self.clients["table"]
        query = table.query
        gone = {"capture": f"{OWNER}#abc", "email": "gone@example.com", "owner": OWNER,
                "captureId": "abc", "ownerEmail": "julio@example.com", "role": "read",
                "via": "link", "grantedAt": Decimal(1)}
        # Listed by the query, deleted before its update.
        table.query = lambda **kw: {"Items": query(**kw)["Items"] + [gone]}
        self.assertEqual(self.visible("private")[0], 200)
        self.assertEqual(table.items, {})

    def test_a_public_capture_keeps_its_title_and_artist_for_search(self):
        self.visible("public", title="  Riff #1 (Live!) ", artist="Zoë Ünder")
        item = self.kept()
        self.assertEqual((item["title"], item["artist"]), ("Riff #1 (Live!)", "Zoë Ünder"))
        self.assertEqual(item["search"], "riff 1 live zoe under")
        self.assertEqual((item["key"], item["listed"]), (self.KEY, "public"))
        self.visible("public", title="x" * 300)
        self.assertEqual(self.kept()["title"], "x" * 200)
        self.assertEqual(self.kept()["artist"], "")
        # Unlisted or private again: no title, artist or key is kept.
        for visibility in ("unlisted", "private"):
            self.visible(visibility, title="Riff #1", artist="Zoë Ünder")
            self.assertEqual(set(self.kept()),
                             {"capture", "owner", "captureId", "visibility", "updatedAt"})

    def searchable(self):
        """Public captures of two owners, an unlisted one and a private one."""
        self.published("morning", "Morning Riff", "Zoë Ünder", when=1)
        self.published("evening", "Evening Riff", "Kim Lee", when=2)
        self.published("riffing", "Riffing Along", "Olga", when=3, token="other-token",
                       email="olga@example.com", owner=OTHER)
        self.published("waltz", "Quiet Waltz", "Zoë Ünder", when=4)
        self.published("secret", "Secret Riff", "Zoë Ünder", when=5, visibility="unlisted")
        self.published("hidden", "Hidden Riff", "Zoë Ünder", when=6, visibility="private")

    def test_search_finds_public_captures_by_title_and_artist(self):
        self.searchable()
        ids = lambda q: [c["captureId"] for c in self.find(q)]
        # Newest first; a word is the start of one of theirs.
        self.assertEqual(ids("riff"), ["riffing", "evening", "morning"])
        self.assertEqual(ids("RIFFI"), ["riffing"])
        self.assertEqual(ids("iff"), [])
        # By the artist, accents and case aside; every word must match.
        self.assertEqual(ids("zoe"), ["waltz", "morning"])
        self.assertEqual(ids("ZOË"), ["waltz", "morning"])
        self.assertEqual(ids("Ünder, morning!"), ["morning"])
        self.assertEqual(ids("zoe evening"), [])
        # What an answer holds.
        self.assertEqual(self.find("waltz"), [{
            "captureId": "waltz", "key": "waltzkey-0123456789ab", "title": "Quiet Waltz",
            "artist": "Zoë Ünder", "updatedAt": 1_800_000_004}])
        # Never an unlisted or a private one.
        self.assertEqual(ids("secret"), [])
        self.assertEqual(ids("hidden"), [])
        # Under 2 characters: nothing.
        for q in (None, "", "r", " é ", "!!"):
            self.assertEqual(self.find(q), [], q)

    def test_search_answers_20_at_most_and_reads_2000_at_most(self):
        self.clients["captures"].page_size = 3  # pages of 3
        for n in range(25):
            self.published(f"r{n}", f"Riff {n}", when=n)
        found = self.find("riff")
        self.assertEqual(len(found), 20)
        self.assertEqual((found[0]["captureId"], found[-1]["captureId"]), ("r24", "r5"))
        old = index.SEARCH_READ
        index.SEARCH_READ = 5
        try:
            self.clients["captures"].read = 0
            self.assertEqual(self.find("waltz"), [])
            self.assertEqual(self.clients["captures"].read, 5)
        finally:
            index.SEARCH_READ = old

    def test_the_sitemap_lists_public_short_links_on_tabs_cam_alone(self):
        self.searchable()
        self.assertEqual(self.site_map("tabs.cam")[:2], [
            ("https://tabs.cam/s/waltzkey-0123456789ab", "2027-01-15"),
            ("https://tabs.cam/s/riffingkey-0123456789ab", "2027-01-15"),
        ])
        self.kept("morning")["updatedAt"] = Decimal(1_800_000_000 + 3 * 86400)
        urls = self.site_map("tabs.cam")
        self.assertEqual(urls[0], ("https://tabs.cam/s/morningkey-0123456789ab", "2027-01-18"))
        self.assertEqual(len(urls), 4)
        self.assertFalse(any("secret" in u or "hidden" in u for u, _ in urls))
        # The RC's, or a request that doesn't name the site: empty.
        for site in ("rc.tabs.cam", None, "evil.example.com"):
            self.assertEqual(self.site_map(site), [], site)

    def test_a_public_captures_preview_is_indexed_on_tabs_cam_alone(self):
        self.visible("public", title="Morning Riff")
        page, _ = self.preview(capture_json=self.RIFF, site="tabs.cam")
        self.assertIn("<title>Morning &lt;riff&gt; – Me</title>", page)
        self.assertNotIn("x-robots-tag", self.response["headers"])
        # Crawlers that run scripts stay on the page; people go on to the app.
        self.assertIn("if (!/bot|crawl|spider|preview|facebookexternalhit|whatsapp|slack/i"
                      ".test(navigator.userAgent)) location.replace(", page)
        for site in ("rc.tabs.cam", None):
            self.preview(capture_json=self.RIFF, site=site)
            self.assertEqual(self.response["headers"]["x-robots-tag"], "noindex", site)
        # A wrong key, or an unlisted capture: never indexed.
        self.preview(key="x" * 32, capture_json=self.RIFF, site="tabs.cam")
        self.assertEqual(self.response["headers"]["x-robots-tag"], "noindex")
        self.visible("unlisted")
        self.preview(capture_json=self.RIFF, site="tabs.cam")
        self.assertEqual(self.response["headers"]["x-robots-tag"], "noindex")

    def test_deleting_the_account_deletes_its_captures_visibilities(self):
        self.published("abc", "Morning Riff")
        self.published("xyz", "Evening Riff", visibility="private")
        self.published("olga", "Riffing Along", token="other-token", email="olga@example.com",
                       owner=OTHER)
        status, body = self.call("DELETE /account", "julio@example.com")
        self.assertEqual((status, body["captures"]), (200, 2))
        self.assertEqual(list(self.clients["captures"].items), [f"{OTHER}#olga"])
        self.assertEqual([c["captureId"] for c in self.find("riff")], ["olga"])


class AppleCallbackTest(unittest.TestCase):
    """Sign in with Apple on Android: Apple's form_post reply, back to the
    app as an intent:// redirect."""

    def call(self, body, b64=False):
        if b64:
            body = base64.b64encode(body.encode()).decode()
        return index.handler({"routeKey": index.APPLE_CALLBACK_ROUTE, "body": body,
                              "isBase64Encoded": b64}, None, {})

    def test_the_reply_goes_back_to_the_app(self):
        r = self.call("code=c0de&id_token=h.p.s&state=st&user=%7B%22email%22%3A%22a%40b.c%22%7D",
                      b64=True)
        self.assertEqual(r["statusCode"], 303)
        location = r["headers"]["location"]
        self.assertEqual(
            location,
            "intent://callback?code=c0de&id_token=h.p.s&state=st&user=%7B%22email%22%3A%22a%40b.c%22%7D"
            "#Intent;package=com.nu01.tabcam;scheme=signinwithapple;end")

    def test_other_fields_and_intent_tricks_are_dropped(self):
        r = self.call("code=a%23Intent%3Bpackage%3Devil%3Bend&extra=1")
        location = r["headers"]["location"]
        self.assertEqual(location.count("#"), 1)
        self.assertNotIn("extra", location)
        self.assertTrue(location.endswith("#Intent;package=com.nu01.tabcam;scheme=signinwithapple;end"))

    def test_a_canceled_sign_in_still_goes_back(self):
        r = self.call("error=user_cancelled_authorize")
        self.assertEqual(r["statusCode"], 303)
        self.assertIn("error=user_cancelled_authorize", r["headers"]["location"])

    def test_not_apples_reply(self):
        self.assertEqual(self.call("")["statusCode"], 400)
        self.assertEqual(self.call("x=1")["statusCode"], 400)
        self.assertEqual(self.call("code=" + "a" * 20000)["statusCode"], 413)


if __name__ == "__main__":
    unittest.main()
