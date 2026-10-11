"""Who is calling: an ID token, checked here, then its Cognito identity.

The app sends the signed-in user's ID token (the one it gives Cognito):

- Google's, signed by Google, for TabScan's web client (every platform's
  token is issued for it) or the local web client (local web builds);
- or, with APPLE_CLIENT_ID set, Apple's (Sign in with Apple on iOS), signed
  by Apple, for the app's bundle ID.

It must be unexpired, with a verified e-mail (Apple sends email_verified as
"true", a string; its private relay addresses are verified too, and simply
match no Premium). The identity pool then says which identity ID that token
is (under its issuer's Logins key), the same folder the app syncs to, so
nobody can ask about another user's folder.
"""
import os

import jwt


class Unauthorized(Exception):
    pass


class Unsupported(Unauthorized):
    """A token of a provider this service isn't set up for (Apple's, without
    APPLE_CLIENT_ID): the app says Premium needs Google sign-in."""


class Provider:
    """One issuer: where its keys are, what its tokens say, the audiences
    taken, and the token's key in Cognito's Logins."""

    def __init__(self, name, certs, issuers, login, client_ids, jwks=None):
        self.name = name
        self.certs = certs
        self.issuers = issuers
        self.login = login
        self.client_ids = client_ids
        self._jwks = jwks

    @property
    def jwks(self):
        if self._jwks is None:
            self._jwks = jwt.PyJWKClient(self.certs, cache_keys=True, lifespan=3600)
        return self._jwks


def _ids(raw):
    """One client ID, or several separated by commas."""
    return [c.strip() for c in (raw or "").split(",") if c.strip()]


GOOGLE_ISSUERS = ("accounts.google.com", "https://accounts.google.com")
APPLE_ISSUERS = ("https://appleid.apple.com",)


class TokenVerifier:
    def __init__(self, client_id=None, jwks=None, apple_client_id=None, apple_jwks=None):
        google = client_id if client_id is not None else os.environ.get("GOOGLE_WEB_CLIENT_ID", "")
        apple = apple_client_id if apple_client_id is not None else os.environ.get("APPLE_CLIENT_ID", "")
        self.providers = [
            Provider("google", "https://www.googleapis.com/oauth2/v3/certs", GOOGLE_ISSUERS,
                     "accounts.google.com", _ids(google), jwks),
            Provider("apple", "https://appleid.apple.com/auth/keys", APPLE_ISSUERS,
                     "appleid.apple.com", _ids(apple), apple_jwks),
        ]

    def _provider(self, token):
        """The provider the token says issued it (unverified: only to pick
        whose keys and audiences to check it against)."""
        try:
            issuer = jwt.decode(token, options={"verify_signature": False}).get("iss")
        except jwt.PyJWTError as e:
            raise Unauthorized(f"bad token: {type(e).__name__}") from e
        for p in self.providers:
            if issuer in p.issuers:
                return p
        raise Unauthorized("unknown issuer")

    def verify(self, token):
        """(verified e-mail address in lower case, the token's Logins key)."""
        p = self._provider(token)
        if not p.client_ids:
            if p.name == "google":
                raise Unauthorized("sign-in isn't set up")
            raise Unsupported(f"{p.name} sign-in isn't set up")
        try:
            key = p.jwks.get_signing_key_from_jwt(token).key
            claims = jwt.decode(token, key, algorithms=["RS256"], audience=p.client_ids,
                                issuer=p.issuers,
                                options={"require": ["exp", "iss", "aud", "email"]})
        except jwt.PyJWTError as e:
            raise Unauthorized(f"bad token: {type(e).__name__}") from e
        verified = claims.get("email_verified")
        if not (verified is True or (isinstance(verified, str) and verified.lower() == "true")):
            raise Unauthorized("e-mail not verified")
        email = claims["email"]
        if not isinstance(email, str) or not email.strip():
            raise Unauthorized("no e-mail")
        return email.strip().lower(), p.login

    def email(self, token):
        """The token's verified e-mail address, lower case."""
        return self.verify(token)[0]


class CognitoIdentities:
    def __init__(self, pool_id=None, client=None):
        self.pool_id = pool_id if pool_id is not None else os.environ.get("COGNITO_IDENTITY_POOL_ID", "")
        self._client = client

    def identity(self, token, login="accounts.google.com"):
        if not self.pool_id:
            raise Unauthorized("sign-in isn't set up")
        if self._client is None:
            import boto3
            self._client = boto3.client("cognito-identity", region_name=self.pool_id.split(":")[0])
        try:
            return self._client.get_id(IdentityPoolId=self.pool_id, Logins={login: token})["IdentityId"]
        except self._client.exceptions.NotAuthorizedException as e:
            raise Unauthorized(f"token refused by the identity pool: {e}") from e
