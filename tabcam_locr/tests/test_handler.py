import json

import pytest

from locr import handler
from locr.auth import Unauthorized, Unsupported
from locr.premium import Answer

ID = "us-east-1:0f8b5b1e-1c2d-4e5f-8a9b-0c1d2e3f4a5b"
BUCKET = "user-events"


class FakeS3:
    class exceptions:
        class NoSuchKey(Exception):
            pass

    def __init__(self, objects=()):
        self.objects = dict.fromkeys(objects, b"")
        self.deleted = []
        self.put = {}

    def delete_object(self, Bucket, Key):
        self.deleted.append(Key)

    def get_object(self, Bucket, Key):
        if Key not in self.objects:
            raise self.exceptions.NoSuchKey(Key)
        body = self.objects[Key]

        class Body:
            def read(self):
                return body
        return {"Body": Body(), "ContentLength": len(body)}

    def put_object(self, Bucket, Key, Body, **_):
        self.put[Key] = Body

    def list_objects_v2(self, Bucket, Prefix, **_):
        return {"Contents": [{"Key": k} for k in sorted(self.objects) if k.startswith(Prefix)]}


class FakeLambda:
    def __init__(self):
        self.invoked = []

    def invoke(self, FunctionName, InvocationType, Payload):
        assert InvocationType == "Event"
        self.invoked.append(json.loads(Payload)["key"])


class FakeAccounts:
    def __init__(self, known=None):
        self.known = dict(known or {})

    def put(self, identity, emails):
        self.known[identity] = [emails] if isinstance(emails, str) else list(emails)

    def emails(self, identity):
        found = self.known.get(identity)
        return [found] if isinstance(found, str) else list(found or [])

    def email(self, identity):
        found = self.emails(identity)
        return found[0] if found else None


class FakeProfiles:
    """subject -> (identity, addresses); no profile by default."""

    def __init__(self, known=None):
        self.known = dict(known or {})

    def of(self, subject):
        return self.known.get(subject)


class FakeRbacr:
    def __init__(self, premium=()):
        self.premium = set(premium)

    def check(self, email):
        return Answer(email in self.premium, "2026-11-01T00:00:00Z" if email in self.premium else None)


APPLE_ID = "us-east-1:22222222-2222-2222-2222-222222222222"


class FakeTokens:
    """Google's good-token, Apple's apple-token (a private relay address),
    and Apple's unset-token when the service has no Apple client."""

    def verify(self, token):
        if token == "good-token":
            return "ana@example.com", "accounts.google.com"
        if token == "apple-token":
            return "x7k2@privaterelay.appleid.com", "appleid.apple.com"
        if token == "unset-token":
            raise Unsupported("apple sign-in isn't set up")
        raise Unauthorized("bad token")

    def verify_subject(self, token):
        email, login = self.verify(token)
        issuer = "https://appleid.apple.com" if login == "appleid.apple.com" else "https://accounts.google.com"
        return email, login, f"{issuer}#{token}"


class FakeCognito:
    def __init__(self):
        self.logins = []

    def identity(self, token, login="accounts.google.com"):
        self.logins.append(login)
        return APPLE_ID if login == "appleid.apple.com" else ID


@pytest.fixture
def svc(monkeypatch):
    monkeypatch.setenv("USER_DATA_BUCKET", BUCKET)
    monkeypatch.setenv("OCR_FUNCTION", "tabcam-ocr")
    monkeypatch.setenv("UPGRADE_URL", "https://example.com/subscribe")
    monkeypatch.setenv("VOUCHER_URL", "https://example.com/voucher")
    s = handler.Services()
    s._made.update(s3=FakeS3(), **{"lambda": FakeLambda()}, accounts=FakeAccounts(),
                   rbacr=FakeRbacr(), tokens=FakeTokens(), cognito=FakeCognito(),
                   profiles=FakeProfiles())
    monkeypatch.setattr(handler, "services", s)
    return s


def s3_event(key, kind="Object Created", bucket=BUCKET, size=1000, etag=None):
    obj = {"key": key, "size": size}
    if etag:
        obj["etag"] = etag
    return {"source": "aws.s3", "detail-type": kind,
            "detail": {"bucket": {"name": bucket}, "object": obj}}


def http(path, token="good-token", body=None):
    return {"rawPath": path, "requestContext": {"http": {"method": "POST"}},
            "headers": {"authorization": f"Bearer {token}"} if token else {},
            "body": json.dumps(body) if body is not None else None}


PAGE = f"{ID}/events/ev1/p1.img"


def test_a_premium_users_page_is_queued(svc):
    svc._made["accounts"] = FakeAccounts({ID: "ana@example.com"})
    svc._made["rbacr"] = FakeRbacr({"ana@example.com"})
    assert handler.api(s3_event(PAGE)) == "queued"
    assert svc.lam.invoked == [PAGE]


ETAG = "0123456789abcdef0123456789abcdef"


def test_a_copy_of_a_page_read_before_is_not_read_again(svc):
    svc._made["accounts"] = FakeAccounts({ID: "ana@example.com"})
    svc._made["rbacr"] = FakeRbacr({"ana@example.com"})
    cache = f"{ID}/ocrcache/{ETAG}-{handler.VERSION}.json"
    svc._made["s3"] = FakeS3()
    svc.s3.objects[cache] = json.dumps({"page": "p0", "status": "ok", "text": "e|--3--|"}).encode()
    assert handler.api(s3_event(PAGE, etag=ETAG)) == "cached"
    assert svc.lam.invoked == []
    written = json.loads(svc.s3.put[f"{ID}/ocr/ev1/p1.json"])
    assert written["page"] == "p1" and written["text"] == "e|--3--|" and written["cached"]


def test_a_page_not_read_before_is_queued(svc):
    svc._made["accounts"] = FakeAccounts({ID: "ana@example.com"})
    svc._made["rbacr"] = FakeRbacr({"ana@example.com"})
    assert handler.api(s3_event(PAGE, etag=ETAG)) == "queued"
    assert svc.lam.invoked == [PAGE]
    assert svc.s3.put == {}


def test_a_free_users_page_is_not(svc):
    svc._made["accounts"] = FakeAccounts({ID: "ana@example.com"})
    assert handler.api(s3_event(PAGE)) == "not premium"
    assert svc.lam.invoked == []


def test_an_unknown_identity_is_not_premium(svc):
    svc._made["rbacr"] = FakeRbacr({"ana@example.com"})
    assert handler.api(s3_event(PAGE)) == "not premium"


def test_other_objects_and_buckets_are_ignored(svc):
    assert handler.api(s3_event(f"{ID}/events/ev1/event.json")) == "not a page"
    assert handler.api(s3_event(PAGE, bucket="other")) == "other bucket"
    assert handler.api(s3_event(PAGE, size=10**9)) == "too large"


def test_a_deleted_page_loses_its_transcription(svc):
    assert handler.api(s3_event(PAGE, kind="Object Deleted")) == "deleted"
    assert svc.s3.deleted == [f"{ID}/ocr/ev1/p1.json"]


def test_account_records_the_identity_and_says_who_is_premium(svc):
    r = handler.api(http("/account"))
    body = json.loads(r["body"])
    assert r["statusCode"] == 200
    assert body["premium"] is False and body["upgradeUrl"] == "https://example.com/subscribe"
    assert svc.accounts.known == {ID: ["ana@example.com"]}
    svc._made["rbacr"] = FakeRbacr({"ana@example.com"})
    body = json.loads(handler.api(http("/account"))["body"])
    assert body["premium"] is True and body["expiresAt"] == "2026-11-01T00:00:00Z"


def test_requests_need_a_good_token(svc):
    assert handler.api(http("/account", token=None))["statusCode"] == 401
    assert handler.api(http("/account", token="forged"))["statusCode"] == 401
    assert svc.accounts.known == {}
    assert handler.api(http("/elsewhere"))["statusCode"] == 404


def test_transcribe_queues_the_pages_without_a_transcription(svc):
    svc._made["rbacr"] = FakeRbacr({"ana@example.com"})
    svc._made["s3"] = FakeS3([
        f"{ID}/events/ev1/event.json", f"{ID}/events/ev1/p1.img", f"{ID}/events/ev1/p2.jpg",
        f"{ID}/events/ev1/v1.mp4", f"{ID}/ocr/ev1/p1.json", f"{ID}/events/ev2/p9.img"])
    r = handler.api(http("/transcribe", body={"eventId": "ev1"}))
    assert json.loads(r["body"]) == {"queued": 1}
    assert svc.lam.invoked == [f"{ID}/events/ev1/p2.jpg"]


def test_transcribe_is_premium_only_and_checks_the_event_id(svc):
    assert handler.api(http("/transcribe", body={"eventId": "ev1"}))["statusCode"] == 402
    svc._made["rbacr"] = FakeRbacr({"ana@example.com"})
    assert handler.api(http("/transcribe", body={"eventId": "../x"}))["statusCode"] == 400
    assert svc.lam.invoked == []


def test_apple_users_are_their_own_identity_and_premium_by_their_address(svc):
    body = json.loads(handler.api(http("/account", token="apple-token"))["body"])
    assert svc.cognito.logins == ["appleid.apple.com"]
    assert svc.accounts.known == {APPLE_ID: ["x7k2@privaterelay.appleid.com"]}
    # A relay address matches no Premium unless that address has it.
    assert body["premium"] is False
    svc._made["rbacr"] = FakeRbacr({"x7k2@privaterelay.appleid.com"})
    body = json.loads(handler.api(http("/account", token="apple-token"))["body"])
    assert body["premium"] is True


def test_apple_tokens_without_an_apple_client_need_google(svc):
    r = handler.api(http("/account", token="unset-token"))
    assert r["statusCode"] == 403
    assert json.loads(r["body"])["error"] == "google sign-in needed"
    assert svc.accounts.known == {}


PROFILE_ID = "us-east-1:33333333-3333-3333-3333-333333333333"


def test_a_profile_is_premium_if_any_linked_address_is(svc):
    svc._made["profiles"] = FakeProfiles({
        "https://accounts.google.com#good-token": (PROFILE_ID, ["ana@example.com", "x7k2@privaterelay.appleid.com"])})
    svc._made["rbacr"] = FakeRbacr({"x7k2@privaterelay.appleid.com"})
    r = handler.api(http("/account"))
    assert r["statusCode"] == 200 and json.loads(r["body"])["premium"] is True
    # The profile's folder, not the sign-in's own identity; both addresses.
    assert svc.cognito.logins == []
    assert svc.accounts.emails(PROFILE_ID) == ["ana@example.com", "x7k2@privaterelay.appleid.com"]
    page = f"{PROFILE_ID}/events/ev1/p1.img"
    assert handler.api(s3_event(page)) == "queued"


def test_a_profile_without_a_folder_yet_queues_nothing(svc):
    svc._made["profiles"] = FakeProfiles({"https://accounts.google.com#good-token": (None, ["ana@example.com"])})
    svc._made["rbacr"] = FakeRbacr({"ana@example.com"})
    r = handler.api(http("/transcribe", body={"eventId": "ev1"}))
    assert r["statusCode"] == 200 and json.loads(r["body"]) == {"queued": 0}


def test_transcribe_again_reads_every_page(svc):
    svc._made["accounts"] = FakeAccounts({ID: "ana@example.com"})
    svc._made["rbacr"] = FakeRbacr({"ana@example.com"})
    svc._made["s3"] = FakeS3([f"{ID}/events/ev1/p1.pdf", f"{ID}/ocr/ev1/p1.json"])
    r = handler.api(http("/transcribe", body={"eventId": "ev1"}))
    assert json.loads(r["body"]) == {"queued": 0}
    r = handler.api(http("/transcribe", body={"eventId": "ev1", "again": True}))
    assert json.loads(r["body"]) == {"queued": 1}
    assert svc.lam.invoked == [f"{ID}/events/ev1/p1.pdf"]


def test_the_account_record_is_not_rewritten_on_every_request():
    class Table:
        def __init__(self):
            self.puts = []

        def put_item(self, Item):
            self.puts.append(Item)
    table = Table()
    accounts = handler.Accounts(table=table)
    accounts.put(ID, ["ana@example.com"])
    accounts.put(ID, ["ana@example.com"])
    assert len(table.puts) == 1
    accounts.put(ID, ["ana@example.com", "ana@work.example.com"])  # changed: written
    assert len(table.puts) == 2
