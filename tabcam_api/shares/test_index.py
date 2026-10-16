"""Tests for the share API, with in-memory stand-ins for DynamoDB, Cognito
and STS. Run: python3 -m unittest discover -s tabcam_api/shares"""

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
        found = [k for k in self.keys if k.startswith(Prefix)][:MaxKeys]
        return {"Contents": [{"Key": k} for k in found]} if found else {}


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
                        "kms": Kms()}
        self.clients["keys"] = self.clients["store"].keys
        self.objects = Objects()
        self.clients["s3_as"] = self.objects.as_
        keys.forget("brave_calm_otter")
        seed(self.clients, GOOGLE, "owner-token", "julio@example.com", "brave_calm_otter", OWNER)
        seed(self.clients, GOOGLE, "other-token", "olga@example.com", "quiet_bold_heron", OTHER)
        seed(self.clients, APPLE, "apple-owner-token", "riff@example.com", "shy_tall_lynx", APPLE_OWNER)

    def call(self, route, email, token="owner-token", path=None, query=None,
             body=None, verified="true", iss=None):
        # The issuer the route's authorizer takes, unless the test says.
        if iss is None:
            apple = route.split(" ", 1)[1].startswith("/apple/")
            iss = "https://appleid.apple.com" if apple else "https://accounts.google.com"
        claims = {"iss": iss, "email_verified": verified, "sub": token}
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
        self.assertEqual(body, {"grantsMade": 2, "grantsToMe": 1, "links": 0,
                                "appleTokensRevoked": False})
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
        self.assertIn('content="Me · 2 pages, 1 PDF, 1 link, a text tab. Shared with TabCam."', page)
        link = f"https://rc.tabcam.nu01.com/app/?c=abc&amp;k={self.KEY}"
        self.assertIn(f'<meta property="og:url" content="{link}">', page)
        # Read with the link's own read-only credentials, its folder alone.
        self.assertEqual(used, ["ASIA", f"{OWNER}/events/abc/event.json"])
        policy = json.loads(self.clients["sts"].calls[-1]["Policy"])
        self.assertEqual(policy["Statement"][0]["Action"], ["s3:GetObject"])

    def test_a_wrong_key_previews_as_tabcam_and_reads_nothing(self):
        self.publish()
        page, used = self.preview(key="x" * 32, capture_json=self.RIFF)
        self.assertIn('<meta property="og:title" content="TabCam">', page)
        self.assertNotIn("riff", page)
        self.assertEqual(used, [])
        # Another site than ours: production's is named.
        page, _ = self.preview(key="x" * 32, site="evil.example.com")
        self.assertIn("https://tabcam.nu01.com/app/", page)
        self.assertNotIn("evil", page)

    def test_a_deleted_capture_previews_as_tabcam(self):
        self.publish()
        page, _ = self.preview(capture_json={"id": "abc", "deleted": 1})
        self.assertIn('<meta property="og:title" content="TabCam">', page)

    def test_a_malformed_link_previews_as_tabcam(self):
        page, used = self.preview(capture="<script>", key="k")
        self.assertIn('<meta property="og:title" content="TabCam">', page)
        self.assertNotIn("<script>", page.split("<script>location")[0])
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

    def test_deleting_the_account_deletes_its_links(self):
        self.publish()
        self.call("PUT /links/{captureId}", "olga@example.com", token="other-token",
                  path={"captureId": "xyz"}, body={"key": "olgakey-0123456789abcdefghijklmnopqrstu"})
        status, body = self.call("DELETE /account", "julio@example.com")
        self.assertEqual(body["links"], 1)
        self.assertEqual(self.open_link()[0], 404)
        status, _ = self.open_link(capture="xyz", key="olgakey-0123456789abcdefghijklmnopqrstu")
        self.assertEqual(status, 200)


if __name__ == "__main__":
    unittest.main()
