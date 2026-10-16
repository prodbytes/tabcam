"""Tests for revoking Sign in with Apple tokens, with a made-up key and a
fake Apple. Run: python3 -m unittest discover -s tabcam_api/shares"""

import base64
import json
import unittest
import urllib.parse

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

import apple_revoke


def b64url_json(data):
    raw = json.dumps(data).encode()
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def unb64(part):
    return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))


def made_up_key():
    private = ec.generate_private_key(ec.SECP256R1())
    pem = private.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode()
    return private, apple_revoke.Key("TEAM123456", "KEY1234567", pem)


class Response:
    def __init__(self, status, body):
        self.status = status
        self._body = body

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class FakeApple:
    """Apple's /auth/token and /auth/revoke: a code made for sub."""

    def __init__(self, sub="001234.abcd", token_status=200, revoke_status=200, refresh=True):
        self.sub = sub
        self.token_status = token_status
        self.revoke_status = revoke_status
        self.refresh = refresh
        self.calls = []

    def __call__(self, request, timeout=None):
        form = dict(urllib.parse.parse_qsl(request.data.decode()))
        self.calls.append((request.full_url, form))
        if request.full_url == apple_revoke.TOKEN_URL:
            if self.token_status != 200:
                return Response(self.token_status, b'{"error": "invalid_grant"}')
            tokens = {"access_token": "at", "id_token": f"h.{b64url_json({'sub': self.sub})}.s"}
            if self.refresh:
                tokens["refresh_token"] = "rt"
            return Response(200, json.dumps(tokens).encode())
        return Response(self.revoke_status, b"")


class Ssm:
    def __init__(self, value=None):
        self.value = value

    def get_parameter(self, Name, WithDecryption):
        if self.value is None:
            raise type("ParameterNotFound", (Exception,), {})()
        return {"Parameter": {"Value": self.value}}


class AppleRevokeTest(unittest.TestCase):
    def test_the_client_secret_is_an_es256_jwt_apple_can_check(self):
        private, key = made_up_key()
        secret = key.client_secret("com.nu01.tabcam", now=1000)
        header, claims, signature = secret.split(".")
        self.assertEqual(json.loads(unb64(header)),
                         {"alg": "ES256", "kid": "KEY1234567", "typ": "JWT"})
        self.assertEqual(json.loads(unb64(claims)), {
            "iss": "TEAM123456", "iat": 1000, "exp": 1300,
            "aud": "https://appleid.apple.com", "sub": "com.nu01.tabcam"})
        raw = unb64(signature)
        self.assertEqual(len(raw), 64)
        der = utils.encode_dss_signature(int.from_bytes(raw[:32], "big"),
                                         int.from_bytes(raw[32:], "big"))
        private.public_key().verify(der, f"{header}.{claims}".encode(),
                                    ec.ECDSA(hashes.SHA256()))

    def test_revoke_trades_the_code_and_revokes_the_refresh_token(self):
        _, key = made_up_key()
        apple = FakeApple()
        apple_revoke.revoke(key, "com.nu01.tabcam", "c0de", "001234.abcd", opener=apple)
        (token_url, token_form), (revoke_url, revoke_form) = apple.calls
        self.assertEqual(token_url, "https://appleid.apple.com/auth/token")
        self.assertEqual(token_form["grant_type"], "authorization_code")
        self.assertEqual(token_form["code"], "c0de")
        self.assertEqual(token_form["client_id"], "com.nu01.tabcam")
        self.assertEqual(revoke_url, "https://appleid.apple.com/auth/revoke")
        self.assertEqual(revoke_form["token"], "rt")
        self.assertEqual(revoke_form["token_type_hint"], "refresh_token")

    def test_without_a_refresh_token_the_access_token_is_revoked(self):
        _, key = made_up_key()
        apple = FakeApple(refresh=False)
        apple_revoke.revoke(key, "com.nu01.tabcam", "c0de", "001234.abcd", opener=apple)
        self.assertEqual(apple.calls[1][1]["token_type_hint"], "access_token")

    def test_another_apple_ids_code_revokes_nothing(self):
        _, key = made_up_key()
        apple = FakeApple(sub="someone.else")
        with self.assertRaises(apple_revoke.RevokeError):
            apple_revoke.revoke(key, "com.nu01.tabcam", "c0de", "001234.abcd", opener=apple)
        self.assertEqual(len(apple.calls), 1)

    def test_apple_refusing_is_an_error(self):
        _, key = made_up_key()
        with self.assertRaises(apple_revoke.RevokeError):
            apple_revoke.revoke(key, "x.y", "c0de", "001234.abcd",
                                opener=FakeApple(token_status=400))
        with self.assertRaises(apple_revoke.RevokeError):
            apple_revoke.revoke(key, "x.y", "c0de", "001234.abcd",
                                opener=FakeApple(revoke_status=400))

    def test_the_key_comes_from_ssm_or_is_none(self):
        self.assertIsNone(apple_revoke.Key.load(Ssm()))
        _, key = made_up_key()
        value = json.dumps({"teamId": "TEAM123456", "keyId": "KEY1234567",
                            "privateKey": key.private_key})
        loaded = apple_revoke.Key.load(Ssm(value))
        self.assertEqual((loaded.team_id, loaded.key_id), ("TEAM123456", "KEY1234567"))
        with self.assertRaises(ValueError):
            apple_revoke.Key.load(Ssm(json.dumps({"teamId": "T", "keyId": "K"})))


if __name__ == "__main__":
    unittest.main()
