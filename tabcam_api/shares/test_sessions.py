"""Tests for TabCam's sessions (sessions.py and their routes in index.py):
signed with a real RSA key behind a stand-in for KMS, and checked against
the JWKS the API publishes, as API Gateway's authorizer and the OCR service
check them."""

import base64
import json
import os
import unittest

os.environ.setdefault("SESSION_ISSUER", "https://api.example.com/session")

# test_index first: it sets the environment index reads when imported.
import test_index as t  # noqa: E402, I001

import index  # noqa: E402
import sessions as sess  # noqa: E402

ISSUER = os.environ["SESSION_ISSUER"]
DAY = 24 * 3600


class SigningKms:
    """KMS's asymmetric key: signs RS256, gives its public half."""

    _key = None

    def __init__(self):
        from cryptography.hazmat.primitives.asymmetric import rsa
        if SigningKms._key is None:
            SigningKms._key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        self.key = SigningKms._key
        self.signs = 0

    def get_public_key(self, KeyId):
        from cryptography.hazmat.primitives import serialization
        return {"PublicKey": self.key.public_key().public_bytes(
            serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)}

    def sign(self, KeyId, Message, MessageType, SigningAlgorithm):
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.asymmetric import padding
        assert MessageType == "RAW" and SigningAlgorithm == "RSASSA_PKCS1_V1_5_SHA_256"
        self.signs += 1
        return {"Signature": self.key.sign(Message, padding.PKCS1v15(), hashes.SHA256())}


class Clock:
    def __init__(self, now=1_800_000_000):
        self.now = now

    def __call__(self):
        return self.now


class SessionsTest(unittest.TestCase):
    def setUp(self):
        self.api = t.ShareApiTest()
        self.api.setUp()
        self.clients = self.api.clients
        self.clock = Clock()
        self.table = t.KeyTable("id", {"bySubject": "subject"})
        self.clients["sessions"] = sess.Sessions(self.table, now=self.clock)
        self.kms = SigningKms()
        self.clients["signer"] = sess.Signer(self.kms, key_id="arn:aws:kms:us-east-1:1:key/sessions")

    # --- helpers ---------------------------------------------------------

    def public(self, route, body=None):
        response = index.handler({"routeKey": route, "body": json.dumps(body) if body else None},
                                 None, self.clients)
        return response["statusCode"], json.loads(response["body"]), response

    def start(self, route="POST /session", token="owner-token", email="julio@example.com", aud=None):
        return self.api.call(route, email, token=token, aud=aud)

    def verify(self, id_token):
        """What API Gateway's JWT authorizer does: the published keys, the
        issuer, the audience, the expiry (at the test's clock)."""
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.asymmetric import padding, rsa

        def unb64(part):
            return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))

        _, jwks, _ = self.public(index.SESSION_KEYS_ROUTE)
        (jwk,) = jwks["keys"]
        key = rsa.RSAPublicNumbers(int.from_bytes(unb64(jwk["e"]), "big"),
                                   int.from_bytes(unb64(jwk["n"]), "big")).public_key()
        header, payload, signature = id_token.split(".")
        head = json.loads(unb64(header))
        self.assertEqual((head["alg"], head["kid"]), ("RS256", jwk["kid"]))
        # Raises if the signature isn't the key's.
        key.verify(unb64(signature), f"{header}.{payload}".encode(), padding.PKCS1v15(),
                   hashes.SHA256())
        claims = json.loads(unb64(payload))
        self.assertEqual((claims["iss"], claims["aud"]), (ISSUER, sess.AUDIENCE))
        return claims

    def as_session(self, route, id_token, body=None):
        """A /tabcam route, with the claims the authorizer verified."""
        claims = self.verify(id_token)
        event = {"routeKey": route, "headers": {"authorization": f"Bearer {id_token}"},
                 "requestContext": {"authorizer": {"jwt": {"claims": claims}}},
                 "pathParameters": None, "queryStringParameters": None,
                 "body": json.dumps(body) if body is not None else None}
        response = index.handler(event, None, self.clients)
        return response["statusCode"], json.loads(response["body"])

    def refresh(self, token):
        status, body, _ = self.public(index.SESSION_REFRESH_ROUTE, {"refreshToken": token})
        return status, body

    # --- tests -----------------------------------------------------------

    def test_a_provider_token_starts_a_session_for_its_sign_in(self):
        status, body = self.start()
        self.assertEqual(status, 200)
        self.assertTrue(sess.valid_token(body["refreshToken"]))
        claims = self.verify(body["idToken"])
        self.assertEqual(claims["sub"], "owner-token")
        self.assertEqual(claims["idp"], t.GOOGLE)
        self.assertEqual(claims["email"], "julio@example.com")
        self.assertTrue(claims["email_verified"])
        self.assertEqual(claims["exp"] - claims["iat"], 3600)
        self.assertEqual(body["sessionExpiresAt"], self.clock.now + 7 * DAY)
        # Only the hash is kept.
        (item,) = self.table.items.values()
        self.assertNotIn(body["refreshToken"], json.dumps(item, default=str))

    def test_its_token_reaches_the_same_profile(self):
        _, mine = self.api.call("GET /profile", "julio@example.com")
        _, body = self.start()
        status, profile = self.as_session("GET /tabcam/profile", body["idToken"])
        self.assertEqual(status, 200)
        self.assertEqual(profile["profileId"], mine["profileId"])
        self.assertEqual(profile["accounts"], mine["accounts"])

    def test_refreshing_keeps_it_going_a_week_past_each_use(self):
        _, body = self.start()
        token = body["refreshToken"]
        for _ in range(5):
            self.clock.now += 6 * DAY
            status, renewed = self.refresh(token)
            self.assertEqual(status, 200)
            self.assertEqual(renewed["sessionExpiresAt"], self.clock.now + 7 * DAY)
            self.assertEqual(self.verify(renewed["idToken"])["sub"], "owner-token")

    def test_a_week_unused_ends_it(self):
        _, body = self.start()
        self.clock.now += 7 * DAY
        status, _ = self.refresh(body["refreshToken"])
        self.assertEqual(status, 401)
        self.assertEqual(self.table.items, {})

    def test_it_never_lasts_past_ninety_days(self):
        _, body = self.start()
        start = self.clock.now
        while True:
            self.clock.now += 6 * DAY
            status, renewed = self.refresh(body["refreshToken"])
            if status != 200:
                break
            self.assertLessEqual(renewed["sessionExpiresAt"], start + 90 * DAY)
        self.assertEqual(status, 401)
        self.assertGreaterEqual(self.clock.now, start + 90 * DAY)

    def test_signing_out_ends_it(self):
        _, body = self.start()
        status, ended, _ = self.public(index.SESSION_END_ROUTE, {"refreshToken": body["refreshToken"]})
        self.assertEqual((status, ended), (200, {"ended": True}))
        self.assertEqual(self.refresh(body["refreshToken"])[0], 401)

    def test_a_wrong_token_is_refused_without_looking(self):
        for token in (None, "", 42, "tcs1.short", "x" * 48, "tcs1." + "A" * 43):
            self.assertEqual(self.refresh(token)[0], 401, token)

    def test_a_session_token_cant_start_another(self):
        _, body = self.start()
        status, _ = self.as_session("POST /tabcam/session", body["idToken"])
        self.assertEqual(status, 400)

    def test_a_token_for_another_audience_or_provider_is_refused(self):
        _, body = self.start()
        claims = self.verify(body["idToken"])
        for bad in ({"aud": "someone-else"}, {"idp": ISSUER}, {"idp": "https://evil.example"},
                    {"iss": t.GOOGLE}):
            event = {"routeKey": "GET /tabcam/profile",
                     "requestContext": {"authorizer": {"jwt": {"claims": {**claims, **bad}}}}}
            response = index.handler(event, None, self.clients)
            self.assertEqual(response["statusCode"], 401, bad)

    def test_unlinking_a_sign_in_ends_its_sessions(self):
        # Olga's sign-in joins Julio's profile, starts a session, and is
        # unlinked by the owner.
        _, code = self.api.call("POST /profile/link-code", "julio@example.com")
        self.clients["cognito"].identities.pop("quiet_bold_heron")
        self.clients["store"].delete_profile("quiet_bold_heron")
        self.clients["store"].unlink(f"{t.GOOGLE}#other-token")
        status, _ = self.api.call("POST /profile/link", "olga@example.com", token="other-token",
                                  body={"code": code["code"]})
        self.assertEqual(status, 200)
        _, olga = self.start(token="other-token", email="olga@example.com")
        account = index.prof.account_id(f"{t.GOOGLE}#other-token")
        status, _ = self.api.call("POST /profile/unlink", "julio@example.com", body={"id": account})
        self.assertEqual(status, 200)
        self.assertEqual(self.refresh(olga["refreshToken"])[0], 401)

    def test_unlinking_yourself_keeps_you_signed_in(self):
        _, code = self.api.call("POST /profile/link-code", "julio@example.com")
        self.clients["cognito"].identities.pop("quiet_bold_heron")
        self.clients["store"].delete_profile("quiet_bold_heron")
        self.clients["store"].unlink(f"{t.GOOGLE}#other-token")
        self.api.call("POST /profile/link", "olga@example.com", token="other-token",
                      body={"code": code["code"]})
        _, olga = self.start(token="other-token", email="olga@example.com")
        account = index.prof.account_id(f"{t.GOOGLE}#other-token")
        status, body = self.as_session("POST /tabcam/profile/unlink", olga["idToken"],
                                       body={"id": account})
        self.assertEqual((status, body), (200, {"unlinked": True}))
        # Its next request makes it a profile of its own; it goes on.
        status, profile = self.as_session("GET /tabcam/profile", olga["idToken"])
        self.assertEqual(status, 200)
        self.assertNotEqual(profile["profileId"], "brave_calm_otter")
        self.assertEqual(self.refresh(olga["refreshToken"])[0], 200)

    def test_deleting_the_account_ends_its_sessions(self):
        _, body = self.start()
        status, _ = self.as_session("DELETE /tabcam/account", body["idToken"])
        self.assertEqual(status, 200)
        self.assertEqual(self.table.items, {})
        self.assertEqual(self.refresh(body["refreshToken"])[0], 401)

    def test_an_apple_session_keeps_the_apple_audience_for_revoking(self):
        _, body = self.start(route="POST /apple/session", token="apple-owner-token",
                             email="riff@example.com", aud="com.nu01.tabcam")
        claims = self.verify(body["idToken"])
        self.assertEqual((claims["idp"], claims["idp_aud"]), (t.APPLE, "com.nu01.tabcam"))
        status, profile = self.as_session("GET /tabcam/profile", body["idToken"])
        self.assertEqual(status, 200)
        self.assertEqual(profile["profileId"], "shy_tall_lynx")

    def test_the_keys_and_discovery_document_are_public(self):
        status, doc, response = self.public(index.SESSION_DISCOVERY_ROUTE)
        self.assertEqual(status, 200)
        self.assertEqual(doc["issuer"], ISSUER)
        self.assertEqual(doc["jwks_uri"], f"{ISSUER}/.well-known/jwks.json")
        self.assertIn("max-age", response["headers"]["cache-control"])
        status, jwks, _ = self.public(index.SESSION_KEYS_ROUTE)
        self.assertEqual(jwks["keys"][0]["kid"], self.clients["signer"].kid)

    def test_a_tampered_token_fails_the_check(self):
        _, body = self.start()
        header, payload, signature = body["idToken"].split(".")
        claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
        claims["sub"] = "other-token"
        forged = base64.urlsafe_b64encode(json.dumps(claims).encode()).rstrip(b"=").decode()
        with self.assertRaises(Exception):
            self.verify(f"{header}.{forged}.{signature}")

    def test_without_sessions_set_up_the_routes_say_so(self):
        self.clients["sessions"] = None
        self.assertEqual(self.refresh("tcs1." + "A" * 43)[0], 404)
        self.assertEqual(self.start()[0], 404)


if __name__ == "__main__":
    unittest.main()
