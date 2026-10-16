"""Profiles: what a TabCam user's data belongs to.

A profile has an ID like `huge_wavy_darter` (two different adjectives and
an animal, from the word lists beside this file) and the sign-ins linked to
it: subjects, `<issuer>#<sub>` of a Google or Apple ID token, never the
email. Its captures are in one folder, the Cognito identity of the profile
(a developer identity, so every linked sign-in reaches the same folder),
and its roles are the union of the rbacr roles of every linked sign-in's
verified address.

A sign-in without a profile gets one the first time it's seen: the profile
of another sign-in with the same verified address, if there is one, or a
new one. Another sign-in joins a profile with a link code its owner makes
(8 characters, 10 minutes, single use, stored only as its SHA-256).
"""

import hashlib
import json
import os
import secrets
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ATTEMPTS = 10
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 8
CODE_TTL = 600
ROLES_CACHE = 60


class Conflict(Exception):
    """A conditional write lost: the item exists (or doesn't) already."""


def _words(name):
    with open(os.path.join(HERE, name)) as f:
        return [w for w in f.read().split() if w]


_lists = {}


def words():
    if not _lists:
        _lists["adjectives"] = _words("adjectives.txt")
        _lists["animals"] = _words("animals.txt")
    return _lists["adjectives"], _lists["animals"]


def generate(rng=secrets.SystemRandom()):
    """A new profile ID: two different adjectives and an animal, e.g.
    `huge_wavy_darter`. About 1.1 billion of them: a name, not a secret."""
    adjectives, animals = words()
    first = rng.randrange(len(adjectives))
    second = rng.randrange(len(adjectives) - 1)
    if second >= first:
        second += 1
    return f"{adjectives[first]}_{adjectives[second]}_{animals[rng.randrange(len(animals))]}"


def valid(profile_id):
    if not isinstance(profile_id, str) or len(profile_id) > 100:
        return False
    parts = profile_id.split("_")
    if len(parts) != 3 or parts[0] == parts[1]:
        return False
    adjectives, animals = words()
    return parts[0] in adjectives and parts[1] in adjectives and parts[2] in animals


def account_id(subject):
    """What the app calls a linked sign-in: a hash of its subject, so the
    provider's user ID isn't shown."""
    return hashlib.sha256(subject.encode()).hexdigest()[:16]


def _hash(code):
    return hashlib.sha256(code.encode()).hexdigest()


def normalize_code(code):
    return "".join(c for c in str(code or "").upper() if c.isalnum())


class Store:
    """The tables (DynamoDB resources, or fakes in tests): profiles, their
    sign-ins, link codes, and the profiles' keys (keys.py), if set up."""

    def __init__(self, profiles, subjects, codes, now=time.time, keys=None):
        self.profiles = profiles
        self.subjects = subjects
        self.codes = codes
        self.keys = keys
        self.now = now

    # Items are written whole (put_item), conditionally where races matter.
    def _put_new(self, table, item, key):
        try:
            table.put_item(Item=item, ConditionExpression=f"attribute_not_exists({key})")
        except Exception as e:
            if type(e).__name__ == "ConditionalCheckFailedException" or "ConditionalCheckFailed" in str(e):
                raise Conflict(key) from e
            raise

    def profile(self, profile_id):
        return self.profiles.get_item(Key={"id": profile_id}).get("Item")

    def profile_by_identity(self, identity):
        """The profile whose folder is [identity], if any."""
        items = self.profiles.query(
            IndexName="byIdentity",
            KeyConditionExpression="#i = :i",
            ExpressionAttributeNames={"#i": "identityId"},
            ExpressionAttributeValues={":i": identity},
        )["Items"]
        return items[0] if items else None

    def link_of(self, subject):
        return self.subjects.get_item(Key={"subject": subject}, ConsistentRead=True).get("Item")

    def linked(self, profile_id):
        items, kwargs = [], dict(
            IndexName="byProfile",
            KeyConditionExpression="#p = :p",
            ExpressionAttributeNames={"#p": "profileId"},
            ExpressionAttributeValues={":p": profile_id},
        )
        while True:
            page = self.subjects.query(**kwargs)
            items += page["Items"]
            if "LastEvaluatedKey" not in page:
                return sorted(items, key=lambda i: int(i.get("linkedAt", 0)))
            kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]

    def by_email(self, email):
        return self.subjects.query(
            IndexName="byEmail",
            KeyConditionExpression="#e = :e",
            ExpressionAttributeNames={"#e": "email"},
            ExpressionAttributeValues={":e": email},
        )["Items"]

    def save_profile(self, profile):
        self.profiles.put_item(Item=profile)

    def _link_item(self, subject, profile_id, email, provider):
        return {"subject": subject, "profileId": profile_id, "email": email,
                "provider": provider, "linkedAt": int(self.now())}

    def link(self, subject, profile_id, email, provider):
        """Links a subject that isn't linked yet; Conflict if it is."""
        self._put_new(self.subjects, self._link_item(subject, profile_id, email, provider), "subject")

    def relink(self, subject, profile_id, email, provider):
        self.subjects.put_item(Item=self._link_item(subject, profile_id, email, provider))

    def unlink(self, subject):
        self.subjects.delete_item(Key={"subject": subject})

    def delete_profile(self, profile_id):
        self.profiles.delete_item(Key={"id": profile_id})
        # Its keys go too: whatever it left behind can't be read again.
        if self.keys is not None:
            self.keys.delete_item(Key={"profileId": profile_id})

    # --- link codes -------------------------------------------------------

    def make_code(self, profile_id, created_by):
        code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
        expires = int(self.now()) + CODE_TTL
        self.codes.put_item(Item={"code": _hash(code), "profileId": profile_id,
                                  "createdBy": created_by, "expiresAt": expires})
        return f"{code[:4]}-{code[4:]}", expires

    def peek_code(self, code):
        """The profile a code links to, if it's good: not used, not expired."""
        code = normalize_code(code)
        if len(code) != CODE_LENGTH:
            return None
        item = self.codes.get_item(Key={"code": _hash(code)}, ConsistentRead=True).get("Item")
        if item is None or int(item["expiresAt"]) <= self.now():
            return None
        return item["profileId"]

    def take_code(self, code):
        """Uses a code up; whether it was there to use."""
        key = {"code": _hash(normalize_code(code))}
        try:
            self.codes.delete_item(Key=key, ConditionExpression="attribute_exists(code)")
            return True
        except Exception as e:
            if type(e).__name__ == "ConditionalCheckFailedException" or "ConditionalCheckFailed" in str(e):
                return False
            raise


class Profiles:
    def __init__(self, store, rng=secrets.SystemRandom()):
        self.store = store
        self.rng = rng

    def _new_profile(self, subject, email):
        for _ in range(ATTEMPTS):
            profile = {"id": generate(self.rng), "createdAt": int(self.store.now()),
                       "lastSignInAt": int(self.store.now()),
                       "ownerSubject": subject, "ownerEmail": email}
            try:
                self.store._put_new(self.store.profiles, profile, "id")
                return profile
            except Conflict:
                continue
        raise RuntimeError("no free profile ID")

    def of(self, subject, email, provider):
        """The subject's profile: found by its link, else another sign-in's
        with the same verified address, else a new one."""
        link = self.store.link_of(subject)
        if link is not None:
            profile = self.store.profile(link["profileId"])
            if profile is None:  # the row went missing: make it again
                profile = {"id": link["profileId"], "createdAt": int(self.store.now()),
                           "ownerSubject": subject, "ownerEmail": email}
            profile["lastSignInAt"] = int(self.store.now())
            if profile.get("ownerSubject") == subject and email:
                profile["ownerEmail"] = email
            self.store.save_profile(profile)
            if email and link.get("email") != email:
                self.store.relink(subject, profile["id"], email, provider)
            return profile
        profile = None
        for other in self.store.by_email(email) if email else []:
            profile = self.store.profile(other["profileId"])
            if profile is not None:
                break
        if profile is None:
            profile = self._new_profile(subject, email)
        try:
            self.store.link(subject, profile["id"], email, provider)
        except Conflict:
            # Another first sign-in of the same subject won the race.
            return self.store.profile(self.store.link_of(subject)["profileId"])
        return profile

    def accounts(self, profile, me=None):
        return [
            {
                "id": account_id(s["subject"]),
                "email": s.get("email", ""),
                "provider": s.get("provider", ""),
                "owner": s["subject"] == profile.get("ownerSubject"),
                "you": s["subject"] == me,
                "linkedAt": int(s.get("linkedAt", 0)),
            }
            for s in self.store.linked(profile["id"])
        ]

    def emails(self, profile_id):
        return sorted({s["email"] for s in self.store.linked(profile_id) if s.get("email")})


class Rbacr:
    """Every role an address has, from rbacr (POST /api/roles, with a root's
    token from an SSM SecureString parameter, RBACR_TOKEN_PARAMETER). Cached
    a minute; on any error, none (fails closed)."""

    def __init__(self, url=None, token=None, opener=None, clock=time.monotonic, ssm=None):
        self.url = (url or os.environ.get("RBACR_URL") or "https://rbacr.nu01.com").rstrip("/")
        self.system = os.environ.get("RBACR_SYSTEM", "tabcam")
        self._token = token
        self._ssm = ssm
        self._open = opener or urllib.request.urlopen
        self._clock = clock
        self._cache = {}

    def token(self):
        """Read once per container (the instance lives as long as it does)."""
        if self._token is None:
            if self._ssm is None:
                import boto3
                self._ssm = boto3.client("ssm")
            name = os.environ["RBACR_TOKEN_PARAMETER"]
            got = self._ssm.get_parameter(Name=name, WithDecryption=True)
            self._token = got["Parameter"]["Value"].strip()
        return self._token

    def roles(self, email):
        """(this system's roles, global roles) of [email]."""
        hit = self._cache.get(email)
        if hit and hit[0] > self._clock():
            return hit[1]
        try:
            req = urllib.request.Request(
                f"{self.url}/api/roles", data=json.dumps({"email": email}).encode(), method="POST",
                headers={"Authorization": f"Bearer {self.token()}", "Content-Type": "application/json"})
            with self._open(req, timeout=3) as r:
                data = json.loads(r.read())
            answer = (frozenset((data.get("roles") or {}).get(self.system) or []),
                      frozenset(data.get("globalRoles") or []))
        except Exception as e:
            print(json.dumps({"msg": "rbacr failed", "error": f"{type(e).__name__}: {e}"}))
            return frozenset(), frozenset()
        self._cache[email] = (self._clock() + ROLES_CACHE, answer)
        return answer

    def union(self, emails):
        """The roles of all [emails] together."""
        roles, global_roles = set(), set()
        for email in emails:
            r, g = self.roles(email)
            roles |= r
            global_roles |= g
        return sorted(roles), sorted(global_roles)
