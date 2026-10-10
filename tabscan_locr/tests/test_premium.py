import io
import json
import urllib.error

from locr.premium import Rbacr


class Opener:
    def __init__(self, *answers):
        self.answers = list(answers)
        self.requests = []

    def __call__(self, req, timeout):
        self.requests.append(req)
        a = self.answers.pop(0)
        if isinstance(a, Exception):
            raise a
        return io.BytesIO(json.dumps(a).encode())


class Clock:
    t = 0.0

    def __call__(self):
        return self.t


def rbacr(opener, clock=None):
    return Rbacr(url="https://rbacr.example", token="rbacr_test", opener=opener, clock=clock or Clock())


def test_asks_about_the_premium_role_in_tabscan():
    opener = Opener({"allowed": True, "expiresAt": "2026-11-01T00:00:00Z", "ttl": 100})
    a = rbacr(opener).check("Ana@Example.com")
    assert a.premium and a.expires_at == "2026-11-01T00:00:00Z"
    req = opener.requests[0]
    assert req.full_url == "https://rbacr.example/api/check"
    assert req.get_header("Authorization") == "Bearer rbacr_test"
    assert json.loads(req.data) == {"email": "ana@example.com", "systemId": "tabscan", "role": "premium"}


def test_a_yes_is_cached_until_its_ttl():
    clock = Clock()
    opener = Opener({"allowed": True, "ttl": 100}, {"allowed": False})
    r = rbacr(opener, clock)
    assert r.check("ana@example.com").premium
    clock.t = 99
    assert r.check("ana@example.com").premium
    clock.t = 101
    assert not r.check("ana@example.com").premium


def test_fails_closed_and_does_not_cache_errors():
    opener = Opener(urllib.error.URLError("down"), {"error": "?"}, {"allowed": True, "ttl": None})
    r = rbacr(opener)
    a = r.check("ana@example.com")
    assert not a.premium and not a.checked
    assert not r.check("ana@example.com").premium  # an odd answer is a no too
    assert r.check("ana@example.com").premium


def test_no_address_is_no():
    assert not rbacr(Opener()).check("").premium
