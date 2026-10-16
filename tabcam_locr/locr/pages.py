"""Tab sites' pages, fetched for the web app (POST /page), Premium only.

The browser can't fetch other sites' pages (CORS), so for the web the app
asks the service; Android and iOS fetch them on the device, and never call
this. Only the tab sites below are fetched (the app's list, tabSites in
tabcam_app/lib/import/tab_sites.dart: keep the two the same), over http or
https on the default ports, redirects included, so the route can't be used
to reach anything else. The page comes back as text; the app finds the
tab in it and prints it as a PDF.
"""
import re
import urllib.error
import urllib.parse
import urllib.request

TAB_SITES = (
    "ultimate-guitar.com",
    "songsterr.com",
    "911tabs.com",
    "guitartabs.cc",
    "azchords.com",
    "e-chords.com",
    "guitaretab.com",
    "chordie.com",
    "tabs4acoustic.com",
    "bigbasstabs.com",
    "classtab.org",
    "cifraclub.com.br",
    "cifraclub.com",
    "cifras.com.br",
    "lacuerda.net",
)

MAX_URL = 2000
MAX_BYTES = 2 << 20  # JSON-escaped, within the 6 MB a function URL answers
TIMEOUT = 15
MAX_REDIRECTS = 5
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 "
                  "(KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.8",
}


class NotATabSite(ValueError):
    pass


class FetchFailed(Exception):
    pass


def check(url):
    """url, if it's a tab site's page; NotATabSite otherwise."""
    if not isinstance(url, str) or len(url) > MAX_URL:
        raise NotATabSite("no url")
    parts = urllib.parse.urlsplit(url)
    host = (parts.hostname or "").lower()
    if parts.scheme not in ("http", "https") or parts.username or parts.password \
            or parts.port is not None:
        raise NotATabSite(f"not a plain web address: {parts.scheme}://{host}")
    if not any(host == d or host.endswith("." + d) for d in TAB_SITES):
        raise NotATabSite(f"not a tab site: {host}")
    return url


class _Redirects(urllib.request.HTTPRedirectHandler):
    """Follows redirects to tab sites only."""
    max_redirections = MAX_REDIRECTS

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        check(urllib.parse.urljoin(req.full_url, newurl))
        return super().redirect_request(req, fp, code, msg, headers, newurl)


_opener = urllib.request.build_opener(_Redirects)


def fetch(url, opener=None):
    """The page at url (a tab site's): {"url", "contentType", "html"}."""
    check(url)
    request = urllib.request.Request(url, headers=HEADERS)
    try:
        with (opener or _opener).open(request, timeout=TIMEOUT) as r:
            body = r.read(MAX_BYTES + 1)
            final, content_type = r.geturl(), r.headers.get("Content-Type", "")
    except NotATabSite:
        raise
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise FetchFailed(f"{type(e).__name__}: {e}") from e
    if len(body) > MAX_BYTES:
        raise FetchFailed(f"over {MAX_BYTES} bytes")
    charset = re.search(r"charset=([\w-]+)", content_type, re.I)
    try:
        text = body.decode(charset.group(1) if charset else "utf-8", errors="replace")
    except LookupError:  # a charset Python doesn't know
        text = body.decode("utf-8", errors="replace")
    return {"url": final, "contentType": content_type, "html": text}
