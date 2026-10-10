"""Who is calling: a Google ID token, checked here, then its Cognito identity.

The app sends the signed-in user's Google ID token (the one it gives
Cognito). It must be signed by Google, for TabScan's web client (every
platform's token is issued for it), unexpired, with a verified e-mail. The
identity pool then says which identity ID that token is, the same folder the
app syncs to, so nobody can ask about another user's folder.
"""
import os

import jwt

GOOGLE_CERTS = "https://www.googleapis.com/oauth2/v3/certs"
ISSUERS = ("accounts.google.com", "https://accounts.google.com")


class Unauthorized(Exception):
    pass


class GoogleVerifier:
    def __init__(self, client_id=None, jwks=None):
        self.client_id = client_id if client_id is not None else os.environ.get("GOOGLE_WEB_CLIENT_ID", "")
        self._jwks = jwks or jwt.PyJWKClient(GOOGLE_CERTS, cache_keys=True, lifespan=3600)

    def email(self, token):
        """The token's verified e-mail address, lower case."""
        if not self.client_id:
            raise Unauthorized("sign-in isn't set up")
        try:
            key = self._jwks.get_signing_key_from_jwt(token).key
            claims = jwt.decode(token, key, algorithms=["RS256"], audience=self.client_id,
                                issuer=ISSUERS, options={"require": ["exp", "iss", "aud", "email"]})
        except jwt.PyJWTError as e:
            raise Unauthorized(f"bad token: {type(e).__name__}") from e
        if claims.get("email_verified") is not True:
            raise Unauthorized("e-mail not verified")
        return claims["email"].strip().lower()


class CognitoIdentities:
    def __init__(self, pool_id=None, client=None):
        self.pool_id = pool_id if pool_id is not None else os.environ.get("COGNITO_IDENTITY_POOL_ID", "")
        self._client = client

    def identity(self, token):
        if not self.pool_id:
            raise Unauthorized("sign-in isn't set up")
        if self._client is None:
            import boto3
            self._client = boto3.client("cognito-identity", region_name=self.pool_id.split(":")[0])
        try:
            return self._client.get_id(IdentityPoolId=self.pool_id, Logins={"accounts.google.com": token})["IdentityId"]
        except self._client.exceptions.NotAuthorizedException as e:
            raise Unauthorized("token refused by the identity pool") from e
