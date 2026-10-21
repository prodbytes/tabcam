import time

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from locr.auth import TokenVerifier, Unauthorized, Unsupported

WEB = "111-web.apps.googleusercontent.com"
LOCAL = "111-local.apps.googleusercontent.com"
BUNDLE = "com.nu01.tabcam"
KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
OTHER_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)


class Keys:
    """Stands in for a provider's JWKS: always [key]."""

    def __init__(self, key=KEY):
        self.key = key

    def get_signing_key_from_jwt(self, token):
        return type("Key", (), {"key": self.key.public_key()})()


def token(aud):
    return jwt.encode({"iss": "https://accounts.google.com", "aud": aud, "exp": int(time.time()) + 600,
                       "email": "Riff@Example.com", "email_verified": True}, KEY, algorithm="RS256")


def apple_token(aud=BUNDLE, verified="true", email="x7k2@privaterelay.appleid.com", key=KEY):
    claims = {"iss": "https://appleid.apple.com", "aud": aud, "exp": int(time.time()) + 600,
              "sub": "000123.abc", "email_verified": verified, "is_private_email": "true"}
    if email is not None:
        claims["email"] = email
    return jwt.encode(claims, key, algorithm="RS256")


def verifier(google=WEB, apple=BUNDLE, apple_keys=None):
    return TokenVerifier(client_id=google, jwks=Keys(), apple_client_id=apple,
                         apple_jwks=apple_keys or Keys())


def test_tokens_of_every_listed_client_are_taken():
    v = TokenVerifier(client_id=f"{WEB}, {LOCAL}", jwks=Keys(), apple_client_id="")
    assert v.email(token(WEB)) == "riff@example.com"
    assert v.email(token(LOCAL)) == "riff@example.com"
    assert v.verify(token(WEB)) == ("riff@example.com", "accounts.google.com")


def test_tokens_of_other_clients_are_refused():
    with pytest.raises(Unauthorized):
        TokenVerifier(client_id=WEB, jwks=Keys(), apple_client_id="").email(token(LOCAL))


def test_no_client_refuses_everything():
    with pytest.raises(Unauthorized):
        TokenVerifier(client_id="", jwks=Keys(), apple_client_id="").email(token(WEB))


def test_apple_tokens_for_the_bundle_are_taken_with_a_string_email_verified():
    assert verifier().verify(apple_token()) == ("x7k2@privaterelay.appleid.com", "appleid.apple.com")
    assert verifier().verify(apple_token(verified=True))[1] == "appleid.apple.com"


def test_apple_tokens_must_be_verified_signed_by_apple_and_for_the_bundle():
    for bad in (apple_token(verified="false"), apple_token(verified=None), apple_token(email=None),
                apple_token(aud="com.example.other")):
        with pytest.raises(Unauthorized):
            verifier().verify(bad)
    # Signed by another key than Apple's.
    with pytest.raises(Unauthorized):
        verifier(apple_keys=Keys(OTHER_KEY)).verify(apple_token(key=KEY))


def test_apple_tokens_for_the_services_id_are_taken_beside_the_bundles():
    both = verifier(apple=f"{BUNDLE},com.nu01.tabcam.signin")
    assert both.verify(apple_token(aud="com.nu01.tabcam.signin"))[1] == "appleid.apple.com"
    assert both.verify(apple_token())[1] == "appleid.apple.com"
    with pytest.raises(Unauthorized):
        verifier().verify(apple_token(aud="com.nu01.tabcam.signin"))


def test_apple_tokens_without_an_apple_client_are_unsupported():
    with pytest.raises(Unsupported):
        verifier(apple="").verify(apple_token())


def test_other_issuers_and_garbage_are_refused():
    forged = jwt.encode({"iss": "https://evil.example", "aud": WEB, "exp": int(time.time()) + 600,
                         "email": "riff@example.com", "email_verified": True}, KEY, algorithm="RS256")
    for bad in (forged, "not-a-token"):
        with pytest.raises(Unauthorized) as e:
            verifier().verify(bad)
        assert not isinstance(e.value, Unsupported)


def test_the_subject_is_the_sign_in_as_profiles_know_it():
    email, login, subject = verifier().verify_subject(apple_token())
    assert (login, subject) == ("appleid.apple.com", "https://appleid.apple.com#000123.abc")


POOL = "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_Email"


def email_token(aud="emailclient", iss=POOL):
    return jwt.encode({"iss": iss, "aud": aud, "exp": int(time.time()) + 600, "sub": "mia-sub",
                       "token_use": "id", "email": "Mia@Example.com", "email_verified": True},
                      KEY, algorithm="RS256")


def email_verifier():
    return TokenVerifier(client_id=WEB, jwks=Keys(), apple_client_id=BUNDLE, apple_jwks=Keys(),
                         email_issuer=POOL, email_client_id="emailclient", email_jwks=Keys())


def test_email_sign_in_tokens_are_taken_for_the_pools_client():
    email, login, subject = email_verifier().verify_subject(email_token())
    assert email == "mia@example.com"
    assert login == "cognito-idp.us-east-1.amazonaws.com/us-east-1_Email"
    assert subject == f"{POOL}#mia-sub"
    with pytest.raises(Unauthorized):
        email_verifier().verify(email_token(aud="another-client"))


def test_without_the_pool_set_up_email_tokens_are_refused():
    with pytest.raises(Unauthorized):
        verifier().verify(email_token())
