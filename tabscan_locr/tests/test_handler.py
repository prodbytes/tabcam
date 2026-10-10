import json

import pytest

from locr import handler
from locr.auth import Unauthorized
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

    def delete_object(self, Bucket, Key):
        self.deleted.append(Key)

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

    def put(self, identity, email):
        self.known[identity] = email

    def email(self, identity):
        return self.known.get(identity)


class FakeRbacr:
    def __init__(self, premium=()):
        self.premium = set(premium)

    def check(self, email):
        return Answer(email in self.premium, "2026-11-01T00:00:00Z" if email in self.premium else None)


class FakeGoogle:
    def email(self, token):
        if token != "good-token":
            raise Unauthorized("bad token")
        return "ana@example.com"


class FakeCognito:
    def identity(self, token):
        return ID


@pytest.fixture
def svc(monkeypatch):
    monkeypatch.setenv("USER_DATA_BUCKET", BUCKET)
    monkeypatch.setenv("OCR_FUNCTION", "tabscan-ocr")
    monkeypatch.setenv("UPGRADE_URL", "https://example.com/subscribe")
    monkeypatch.setenv("VOUCHER_URL", "https://example.com/voucher")
    s = handler.Services()
    s._made.update(s3=FakeS3(), **{"lambda": FakeLambda()}, accounts=FakeAccounts(),
                   rbacr=FakeRbacr(), google=FakeGoogle(), cognito=FakeCognito())
    monkeypatch.setattr(handler, "services", s)
    return s


def s3_event(key, kind="Object Created", bucket=BUCKET, size=1000):
    return {"source": "aws.s3", "detail-type": kind,
            "detail": {"bucket": {"name": bucket}, "object": {"key": key, "size": size}}}


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
    assert svc.accounts.known == {ID: "ana@example.com"}
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
