"""Who is premium: rbacr (https://github.com/prodbytes/rbacr) decides.

rbacr knows people by verified e-mail address. This asks it, with a
root-owned API token kept in Secrets Manager (rbacr SPEC C1, C2), whether an
address holds the premium role in the tabscan system (C3). Paying
subscribers get that role from rbacr's Stripe sync (Q2), others from a
voucher or a root's grant.

It fails closed (C6): an error, a timeout or a strange answer is "no", and
isn't cached. A "yes" is cached until its ttl, at most CACHE_YES; a "no"
for CACHE_NO, so an upgrade shows within a minute.
"""
import json
import os
import time
import urllib.error
import urllib.request
from dataclasses import dataclass

CACHE_YES = 300
CACHE_NO = 60
TIMEOUT = 5


@dataclass(frozen=True)
class Answer:
    premium: bool
    expires_at: str | None = None  # when the grants giving the role end
    checked: bool = True  # False: rbacr couldn't answer (so: not premium)


class Rbacr:
    def __init__(self, url=None, system=None, role=None, token=None, opener=None, clock=time.monotonic):
        self.url = (url or os.environ.get("RBACR_URL") or "https://rbacr.nu01.com").rstrip("/")
        if not (self.url.startswith("https://") or self.url.startswith("http://localhost")):
            raise ValueError("rbacr must be reached over https")
        self.system = system or os.environ.get("RBACR_SYSTEM", "tabscan")
        self.role = role or os.environ.get("RBACR_ROLE", "premium")
        self._token = token
        self._open = opener or urllib.request.urlopen
        self._clock = clock
        self._cache = {}

    def token(self):
        if self._token is None:
            import boto3
            arn = os.environ["RBACR_TOKEN_SECRET"]
            self._token = boto3.client("secretsmanager").get_secret_value(SecretId=arn)["SecretString"].strip()
        return self._token

    def check(self, email):
        email = (email or "").strip().lower()
        if not email:
            return Answer(False)
        hit = self._cache.get(email)
        if hit and hit[0] > self._clock():
            return hit[1]
        try:
            answer, ttl = self._ask(email)
        except Exception as e:  # fail closed, never cached
            print(f"rbacr check failed: {type(e).__name__}")
            return Answer(False, checked=False)
        self._cache[email] = (self._clock() + ttl, answer)
        return answer

    def _ask(self, email):
        body = json.dumps({"email": email, "systemId": self.system, "role": self.role}).encode()
        req = urllib.request.Request(
            f"{self.url}/api/check", data=body, method="POST",
            headers={"Authorization": f"Bearer {self.token()}", "Content-Type": "application/json"})
        with self._open(req, timeout=TIMEOUT) as r:
            data = json.loads(r.read())
        if data.get("allowed") is True:
            ttl = data.get("ttl")
            ttl = CACHE_YES if ttl is None else max(0, min(int(ttl), CACHE_YES))
            return Answer(True, data.get("expiresAt")), ttl
        if data.get("allowed") is False:
            return Answer(False), CACHE_NO
        raise ValueError("unexpected answer")
