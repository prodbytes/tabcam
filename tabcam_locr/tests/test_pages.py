"""POST /page: tab sites' pages for the web app. The page is made up."""
import io
import json
import urllib.error

import pytest

from locr import handler, pages

from test_handler import FakeAccounts, FakeRbacr, http, svc  # noqa: F401

URL = "https://tabs.ultimate-guitar.com/tab/nobody/made-up-riff-tabs-1"
HTML = "<html><pre>e|-0-----3-|\nB|-1-----0-|</pre></html>"


class FakeResponse(io.BytesIO):
    def __init__(self, body, url=URL, content_type="text/html; charset=utf-8"):
        super().__init__(body)
        self._url = url
        self.headers = {"Content-Type": content_type}

    def geturl(self):
        return self._url

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False


class FakeOpener:
    def __init__(self, answer):
        self.answer, self.opened = answer, []

    def open(self, request, timeout):
        self.opened.append(request.full_url)
        if isinstance(self.answer, Exception):
            raise self.answer
        return self.answer


@pytest.mark.parametrize("url", [
    URL,
    "http://classtab.org/made_up.txt",
    "https://www.cifraclub.com.br/nobody/riff/",
])
def test_tab_sites_are_taken(url):
    assert pages.check(url) == url


@pytest.mark.parametrize("url", [
    None, 42, "", "https://example.com/tab",
    "https://notultimate-guitar.com/tab",
    "https://ultimate-guitar.com.example.com/tab",
    "https://ultimate-guitar.com:8443/tab",
    "https://user:pw@ultimate-guitar.com/tab",
    "file:///etc/passwd", "http://169.254.169.254/latest/meta-data",
    "https://ultimate-guitar.com/" + "x" * 3000,
])
def test_anything_else_is_refused(url):
    with pytest.raises(pages.NotATabSite):
        pages.check(url)


def test_redirects_off_the_tab_sites_are_refused():
    redirects = pages._Redirects()

    class Req:
        full_url = URL
    with pytest.raises(pages.NotATabSite):
        redirects.redirect_request(Req(), None, 302, "Found", {}, "http://169.254.169.254/")


def test_fetch_decodes_by_charset():
    opener = FakeOpener(FakeResponse("canción".encode("latin-1"),
                                     content_type="text/html; charset=ISO-8859-1"))
    page = pages.fetch(URL, opener=opener)
    assert page["html"] == "canción" and opener.opened == [URL]


def test_fetch_caps_the_size():
    with pytest.raises(pages.FetchFailed):
        pages.fetch(URL, opener=FakeOpener(FakeResponse(b"x" * (pages.MAX_BYTES + 1))))


def test_fetch_errors_are_fetch_failed():
    error = urllib.error.HTTPError(URL, 403, "Forbidden", {}, None)
    with pytest.raises(pages.FetchFailed):
        pages.fetch(URL, opener=FakeOpener(error))


def test_page_route_is_premium_only(svc, monkeypatch):  # noqa: F811
    monkeypatch.setattr(pages, "_opener", FakeOpener(FakeResponse(HTML.encode())))
    assert handler.api(http("/page", body={"url": URL}))["statusCode"] == 402
    svc._made["rbacr"] = FakeRbacr({"ana@example.com"})
    reply = handler.api(http("/page", body={"url": URL}))
    assert reply["statusCode"] == 200
    assert json.loads(reply["body"]) == {
        "url": URL, "contentType": "text/html; charset=utf-8", "html": HTML}


def test_page_route_checks_the_url(svc, monkeypatch):  # noqa: F811
    opener = FakeOpener(FakeResponse(HTML.encode()))
    monkeypatch.setattr(pages, "_opener", opener)
    svc._made["rbacr"] = FakeRbacr({"ana@example.com"})
    for body in ({"url": "https://example.com/"}, {}, ["x"]):
        assert handler.api(http("/page", body=body))["statusCode"] == 400
    assert opener.opened == []


def test_page_route_fetch_failure_is_a_502(svc, monkeypatch):  # noqa: F811
    monkeypatch.setattr(pages, "_opener", FakeOpener(urllib.error.URLError("timed out")))
    svc._made["rbacr"] = FakeRbacr({"ana@example.com"})
    assert handler.api(http("/page", body={"url": URL}))["statusCode"] == 502


def test_page_route_logs_the_size_not_the_page(svc, monkeypatch, capsys):  # noqa: F811
    monkeypatch.setattr(pages, "_opener", FakeOpener(FakeResponse(HTML.encode())))
    svc._made["rbacr"] = FakeRbacr({"ana@example.com"})
    handler.api(http("/page", body={"url": URL}))
    out = capsys.readouterr().out
    assert "e|-0" not in out and f'"html": {len(HTML)}' in out


@pytest.fixture(autouse=True)
def _accounts(svc):  # noqa: F811
    svc._made["accounts"] = FakeAccounts()
