"""TabCam's own sign-in sessions: what keeps a user signed in for days.

A provider's ID token (Google's, Apple's, the email user pool's) lasts an
hour, and the app can't always renew it quietly (Google on the web needs
the browser's cooperation; Apple can't renew at all). So once signed in,
the app starts a TabCam session with that token (POST /session, behind the
provider's authorizer), and from then on uses TabCam's ID tokens:

- **The refresh token**: 256 random bits, given to the app once and kept
  here only as its SHA-256. It lasts while it's used: each refresh pushes
  its end to IDLE (7 days) later, and never past MAX (90 days) after the
  sign-in. Signing out ends it (POST /session/end), and so do deleting the
  account and another sign-in of the profile unlinking it (unlinking
  itself, it stays signed in, with a profile of its own); a sign-in no
  longer linked to a profile can't refresh.
- **TabCam's ID tokens**: JWTs signed by a KMS key (RSA 2048, RS256,
  never leaving KMS), for an hour, issued by SESSION_ISSUER (the API's own
  /session, whose discovery document and keys are public routes, so API
  Gateway's JWT authorizer and the OCR service can check them). They say
  who the provider vouched for: `sub` and `idp` (the provider's subject
  and issuer, the sign-in the profiles know), `idp_aud` (the provider
  token's audience), and the sign-in's verified `email`.

The table (SESSIONS_TABLE): `id` (the hash), `subject`, `idp`, `idpAud`,
`email`, `createdAt`, `lastUsedAt`, `expiresAt` (DynamoDB's TTL), with a
`bySubject` index.
"""

import base64
import hashlib
import json
import os
import re
import secrets
import time

IDLE = 7 * 24 * 3600
MAX = 90 * 24 * 3600
TOKEN_TTL = 3600
AUDIENCE = "tabcam-app"
PREFIX = "tcs1."
TOKEN = re.compile(r"^tcs1\.[A-Za-z0-9_-]{43}$")
ALGORITHM = "RSASSA_PKCS1_V1_5_SHA_256"


class Conflict(Exception):
    """The session ended meanwhile (a conditional write lost)."""


def _b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _hash(token):
    return hashlib.sha256(token.encode()).hexdigest()


def valid_token(token):
    return isinstance(token, str) and bool(TOKEN.match(token))


class Signer:
    """Signs TabCam's ID tokens with the KMS key (SESSION_KEY_ID); its
    public half, as a JWKS, for whoever checks them. The public key is read
    once per container."""

    def __init__(self, kms, key_id=None):
        self.kms = kms
        self.key_id = key_id or os.environ.get("SESSION_KEY_ID", "")
        self._public = None

    def _public_key(self):
        if self._public is None:
            der = self.kms.get_public_key(KeyId=self.key_id)["PublicKey"]
            self._public = (der, _b64url(hashlib.sha256(der).digest())[:16])
        return self._public

    @property
    def kid(self):
        return self._public_key()[1]

    def sign(self, claims):
        header = {"alg": "RS256", "typ": "JWT", "kid": self.kid}
        signing_input = ".".join(
            _b64url(json.dumps(part, separators=(",", ":")).encode())
            for part in (header, claims))
        signature = self.kms.sign(
            KeyId=self.key_id, Message=signing_input.encode(), MessageType="RAW",
            SigningAlgorithm=ALGORITHM)["Signature"]
        return f"{signing_input}.{_b64url(signature)}"

    def jwks(self):
        from cryptography.hazmat.primitives import serialization
        der, kid = self._public_key()
        numbers = serialization.load_der_public_key(der).public_numbers()

        def b64int(n):
            return _b64url(n.to_bytes((n.bit_length() + 7) // 8, "big"))

        return {"keys": [{"kty": "RSA", "use": "sig", "alg": "RS256", "kid": kid,
                          "n": b64int(numbers.n), "e": b64int(numbers.e)}]}


def discovery(issuer):
    """The OpenID discovery document API Gateway's authorizer reads: where
    the keys are."""
    return {
        "issuer": issuer,
        "jwks_uri": f"{issuer}/.well-known/jwks.json",
        "id_token_signing_alg_values_supported": ["RS256"],
        "subject_types_supported": ["public"],
        "response_types_supported": ["id_token"],
    }


class Sessions:
    def __init__(self, table, now=time.time):
        self.table = table
        self.now = now

    def _expiry(self, item, now):
        return min(now + IDLE, int(item["createdAt"]) + MAX)

    def start(self, subject, idp, idp_aud, email):
        """A new session for the sign-in: (its refresh token, its item)."""
        token = PREFIX + secrets.token_urlsafe(32)
        now = int(self.now())
        item = {"id": _hash(token), "subject": subject, "idp": idp,
                "idpAud": idp_aud or "", "email": email,
                "createdAt": now, "lastUsedAt": now}
        item["expiresAt"] = self._expiry(item, now)
        self.table.put_item(Item=item, ConditionExpression="attribute_not_exists(id)")
        return token, item

    def find(self, token):
        """The session of [token], if it's still on; None otherwise (and an
        expired one, which DynamoDB's TTL may not have removed yet, goes)."""
        if not valid_token(token):
            return None
        key = {"id": _hash(token)}
        item = self.table.get_item(Key=key, ConsistentRead=True).get("Item")
        if item is None:
            return None
        if int(item.get("expiresAt", 0)) <= self.now():
            self.table.delete_item(Key=key)
            return None
        return item

    def touch(self, item, email=None):
        """Used now: its end moves IDLE later (never past MAX). Conflict if
        it ended meanwhile (signed out at the same moment)."""
        now = int(self.now())
        item = dict(item, lastUsedAt=now)
        if email:
            item["email"] = email
        item["expiresAt"] = self._expiry(item, now)
        try:
            self.table.put_item(Item=item, ConditionExpression="attribute_exists(id)")
        except Exception as e:
            if type(e).__name__ == "ConditionalCheckFailedException" or "ConditionalCheckFailed" in str(e):
                raise Conflict() from e
            raise
        return item

    def end(self, token):
        if valid_token(token):
            self.table.delete_item(Key={"id": _hash(token)})

    def end_all(self, subject):
        """Ends every session of the sign-in (its account deleted, or it
        was unlinked); how many."""
        kwargs = dict(IndexName="bySubject", KeyConditionExpression="#s = :s",
                      ExpressionAttributeNames={"#s": "subject"},
                      ExpressionAttributeValues={":s": subject})
        ended = 0
        while True:
            page = self.table.query(**kwargs)
            for item in page["Items"]:
                self.table.delete_item(Key={"id": item["id"]})
                ended += 1
            if "LastEvaluatedKey" not in page:
                return ended
            kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]


def id_token(signer, issuer, item, now=None):
    """A TabCam ID token for the session's sign-in, for TOKEN_TTL."""
    now = int(now if now is not None else time.time())
    _, _, sub = item["subject"].partition("#")
    claims = {"iss": issuer, "aud": AUDIENCE, "sub": sub, "idp": item["idp"],
              "email": item["email"], "email_verified": True,
              "iat": now, "exp": now + TOKEN_TTL}
    if item.get("idpAud"):
        claims["idp_aud"] = item["idpAud"]
    return claims, signer.sign(claims)
