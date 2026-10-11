"""Tests for the share API, with in-memory stand-ins for DynamoDB, Cognito
and STS. Run: python3 -m unittest discover -s tabscan_api/shares"""

import datetime
import json
import os
import unittest
from decimal import Decimal

os.environ.update(
    TABLE="shares",
    BUCKET="nu01-user-events-1",
    IDENTITY_POOL_ID="us-east-1:pool",
    ACCESS_ROLE_ARN="arn:aws:iam::1:role/tabscan-share-access",
)

import index  # noqa: E402

OWNER = "us-east-1:11111111-1111-1111-1111-111111111111"
OTHER = "us-east-1:22222222-2222-2222-2222-222222222222"


class Table:
    def __init__(self, page_size=None):
        self.items = {}
        # Queries answer this many items a page, as DynamoDB pages by size.
        self.page_size = page_size

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

    def query(self, KeyConditionExpression, ExpressionAttributeNames,
              ExpressionAttributeValues, IndexName=None, ExclusiveStartKey=None):
        name = list(ExpressionAttributeNames.values())[0]
        value = list(ExpressionAttributeValues.values())[0]
        items = [i for i in self.items.values() if i[name] == value]
        start = ExclusiveStartKey or 0
        if self.page_size is None or start + self.page_size >= len(items):
            return {"Items": items[start:]}
        end = start + self.page_size
        return {"Items": items[start:end], "LastEvaluatedKey": end}


class Accounts:
    """The cloud OCR service's identity -> address table."""

    def __init__(self, items):
        self.items = dict(items)

    def delete_item(self, Key):
        self.items.pop(Key["identityId"], None)


class Cognito:
    def __init__(self):
        self.identities = {"owner-token": OWNER, "other-token": OTHER}
        self.deleted = []
        self.unprocessed = False

    def get_id(self, IdentityPoolId, Logins):
        return {"IdentityId": self.identities[Logins["accounts.google.com"]]}

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


class ShareApiTest(unittest.TestCase):
    def setUp(self):
        self.clients = {"table": Table(), "cognito": Cognito(), "sts": Sts(),
                        "accounts": Accounts({OWNER: "julio@example.com",
                                              OTHER: "olga@example.com"})}

    def call(self, route, email, token="owner-token", path=None, query=None,
             body=None, verified="true"):
        event = {
            "routeKey": route,
            "headers": {"authorization": f"Bearer {token}"},
            "requestContext": {"authorizer": {"jwt": {"claims": {
                "email": email, "email_verified": verified}}}},
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

    def test_a_grant_defaults_to_edit_and_is_listed(self):
        status, body = self.grant(" Ana@Example.com ")
        self.assertEqual(status, 200)
        self.assertEqual(body["grants"][0]["email"], "ana@example.com")
        self.assertEqual(body["grants"][0]["role"], "edit")
        status, body = self.call("GET /shares/{captureId}", "julio@example.com",
                                 path={"captureId": "abc"})
        self.assertEqual([g["email"] for g in body["grants"]], ["ana@example.com"])

    def test_read_only_grants_and_bad_input(self):
        self.assertEqual(self.grant("bo@example.com", "read")[1]["grants"][0]["role"], "read")
        self.assertEqual(self.grant("bo@example.com", "admin")[0], 400)
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
            "ownerEmail": "julio@example.com", "role": "edit"}])

        path = {"owner": OWNER, "captureId": "abc"}
        status, creds = self.call("POST /shared/{owner}/{captureId}/credentials",
                                  "ana@example.com", token="ana", path=path)
        self.assertEqual(status, 200)
        self.assertEqual(creds["prefix"], f"{OWNER}/events/abc/")
        policy = json.loads(self.clients["sts"].calls[0]["Policy"])
        objects = policy["Statement"][0]
        self.assertEqual(objects["Resource"],
                         f"arn:aws:s3:::nu01-user-events-1/{OWNER}/events/abc/*")
        self.assertIn("s3:PutObject", objects["Action"])

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
        self.assertEqual(body, {"grantsMade": 2, "grantsToMe": 1})
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


if __name__ == "__main__":
    unittest.main()
