"""Revoking a user's Sign in with Apple tokens when they delete their
account (App Store guideline 5.1.1(v)), with Apple's REST API.

The app asks Apple for a fresh authorization code just before deleting
(Apple's sheet), and sends it with DELETE /apple/account. Here the code is
traded for the user's tokens (POST https://appleid.apple.com/auth/token),
the ID token that comes back must be the caller's (its sub), and the
refresh token is revoked (POST https://appleid.apple.com/auth/revoke),
which ends TabCam's authorization: the app leaves the user's "Sign in with
Apple" list, and the next sign-in asks for the name and email again.

Both calls are signed with a client secret: a short-lived ES256 JWT made
with TabCam's Sign in with Apple key (a .p8 from Certificates, Identifiers
& Profiles > Keys). The key, its ID and the team ID are an SSM SecureString
parameter (APPLE_SIGN_IN_KEY_PARAMETER, /tabcam/apple-sign-in-key by
default), a JSON object:

    {"teamId": "<10-character team ID>",
     "keyId": "<10-character key ID>",
     "privateKey": "-----BEGIN PRIVATE KEY-----\\n...\\n-----END PRIVATE KEY-----\\n"}

Until the parameter exists, nothing is revoked (Key.load returns None).
"""

import base64
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

APPLE = "https://appleid.apple.com"
TOKEN_URL = f"{APPLE}/auth/token"
REVOKE_URL = f"{APPLE}/auth/revoke"
DEFAULT_PARAMETER = "/tabcam/apple-sign-in-key"


class RevokeError(Exception):
    """Apple didn't take the code, or didn't revoke the tokens."""


def _b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


class Key:
    """TabCam's Sign in with Apple key: the team, the key's ID and the
    private key (PEM, PKCS#8, as Apple's .p8 is)."""

    def __init__(self, team_id, key_id, private_key):
        if not (isinstance(team_id, str) and team_id.isalnum()):
            raise ValueError("the Apple key's teamId isn't a team ID")
        if not (isinstance(key_id, str) and key_id.isalnum()):
            raise ValueError("the Apple key's keyId isn't a key ID")
        if not (isinstance(private_key, str) and "PRIVATE KEY" in private_key):
            raise ValueError("the Apple key's privateKey isn't a PEM key")
        self.team_id = team_id
        self.key_id = key_id
        self.private_key = private_key

    @classmethod
    def load(cls, ssm, name=None):
        """The key from its SSM parameter; None while it doesn't exist."""
        name = name or os.environ.get("APPLE_SIGN_IN_KEY_PARAMETER") or DEFAULT_PARAMETER
        try:
            got = ssm.get_parameter(Name=name, WithDecryption=True)
        except Exception as e:  # noqa: BLE001 - boto3's error classes are dynamic
            if type(e).__name__ == "ParameterNotFound":
                return None
            raise
        value = json.loads(got["Parameter"]["Value"])
        return cls(value.get("teamId"), value.get("keyId"), value.get("privateKey"))

    def client_secret(self, client_id, now=None, lifetime=300):
        """The client secret Apple's endpoints take: an ES256 JWT, issued by
        the team, for client_id, valid a few minutes."""
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec, utils

        now = int(time.time() if now is None else now)
        header = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
        claims = {"iss": self.team_id, "iat": now, "exp": now + lifetime,
                  "aud": APPLE, "sub": client_id}
        signing_input = (
            _b64url(json.dumps(header, separators=(",", ":")).encode())
            + "."
            + _b64url(json.dumps(claims, separators=(",", ":")).encode())
        )
        key = serialization.load_pem_private_key(self.private_key.encode(), password=None)
        if not isinstance(key, ec.EllipticCurvePrivateKey) or key.curve.name != "secp256r1":
            raise ValueError("the Apple key isn't a P-256 key")
        der = key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256()))
        r, s = utils.decode_dss_signature(der)
        signature = r.to_bytes(32, "big") + s.to_bytes(32, "big")
        return f"{signing_input}.{_b64url(signature)}"


def _post(opener, url, form):
    request = urllib.request.Request(
        url,
        data=urllib.parse.urlencode(form).encode(),
        headers={"content-type": "application/x-www-form-urlencoded",
                 "user-agent": "tabcam-share-api"},
        method="POST",
    )
    try:
        with opener(request, timeout=5) as response:
            body = response.read()
            return response.status, body
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def _claims(id_token):
    try:
        payload = id_token.split(".")[1]
        return json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
    except (AttributeError, IndexError, ValueError):
        return {}


def revoke(key, client_id, code, subject, opener=None, now=None):
    """Trades the authorization code for the user's tokens and revokes them.
    subject is the caller's Apple user ID (their token's sub): a code of
    another Apple ID is refused, and revokes nothing."""
    opener = opener or urllib.request.urlopen
    secret = key.client_secret(client_id, now=now)
    status, body = _post(opener, TOKEN_URL, {
        "client_id": client_id,
        "client_secret": secret,
        "code": code,
        "grant_type": "authorization_code",
    })
    try:
        tokens = json.loads(body or b"{}")
    except ValueError:
        tokens = {}
    if status != 200:
        raise RevokeError(f"Apple refused the authorization code ({status} {tokens.get('error', '')})".strip())
    if _claims(tokens.get("id_token")).get("sub") != subject:
        raise RevokeError("The authorization is another Apple ID's")
    if tokens.get("refresh_token"):
        token, hint = tokens["refresh_token"], "refresh_token"
    elif tokens.get("access_token"):
        token, hint = tokens["access_token"], "access_token"
    else:
        raise RevokeError("Apple returned no token to revoke")
    status, _ = _post(opener, REVOKE_URL, {
        "client_id": client_id,
        "client_secret": secret,
        "token": token,
        "token_type_hint": hint,
    })
    if status != 200:
        raise RevokeError(f"Apple didn't revoke the tokens ({status})")
