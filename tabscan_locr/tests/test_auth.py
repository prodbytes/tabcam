import time

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from locr.auth import GoogleVerifier, Unauthorized

WEB = "111-web.apps.googleusercontent.com"
LOCAL = "111-local.apps.googleusercontent.com"
KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)


class Keys:
    """Stands in for Google's JWKS: always our test key."""

    def get_signing_key_from_jwt(self, token):
        return type("Key", (), {"key": KEY.public_key()})()


def token(aud):
    return jwt.encode({"iss": "https://accounts.google.com", "aud": aud, "exp": int(time.time()) + 600,
                       "email": "Riff@Example.com", "email_verified": True}, KEY, algorithm="RS256")


def test_tokens_of_every_listed_client_are_taken():
    verifier = GoogleVerifier(client_id=f"{WEB}, {LOCAL}", jwks=Keys())
    assert verifier.email(token(WEB)) == "riff@example.com"
    assert verifier.email(token(LOCAL)) == "riff@example.com"


def test_tokens_of_other_clients_are_refused():
    with pytest.raises(Unauthorized):
        GoogleVerifier(client_id=WEB, jwks=Keys()).email(token(LOCAL))


def test_no_client_refuses_everything():
    with pytest.raises(Unauthorized):
        GoogleVerifier(client_id="", jwks=Keys()).email(token(WEB))
