#!/usr/bin/env python3
"""The index page (tabcam_index/site) with its Google client ID filled in.

The page is a static file with an empty
`<meta name="google-signin-client_id" content="">`; empty, it offers no
Google sign-in. This fills it in, the same way for the deploy and for the
local server:

    python3 scripts/index_page.py fill CLIENT_ID < index.html > out.html
    python3 scripts/index_page.py serve [--port 2013] [--bind 127.0.0.1]

`serve` serves tabcam_index/site as `python3 -m http.server` does, with
`/` and `/index.html` filled in with the local web client
(TABCAM_GOOGLE_LOCAL_WEB_CLIENT_ID, else TABCAM_GOOGLE_WEB_CLIENT_ID: the
one the local web app signs in with; environment, else the repo's .env).
A client ID names the app to Google: public, not a secret.
"""

import argparse
import functools
import http.server
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "tabcam_index" / "site"
PLACEHOLDER = '<meta name="google-signin-client_id" content="">'
CLIENT_ID = re.compile(r"[0-9]+-[0-9a-z]+\.apps\.googleusercontent\.com")


def fill(html: str, client_id: str) -> str:
    """[html] with [client_id] in its meta tag; empty leaves it as it is."""
    if not client_id:
        return html
    if not CLIENT_ID.fullmatch(client_id):
        raise ValueError(f"not a Google web client ID: {client_id!r}")
    if html.count(PLACEHOLDER) != 1:
        raise ValueError(f"the page has no single {PLACEHOLDER}")
    return html.replace(
        PLACEHOLDER,
        f'<meta name="google-signin-client_id" content="{client_id}">',
    )


def setting(name: str) -> str:
    """[name] from the environment, else the repo's .env, else empty."""
    value = os.environ.get(name, "")
    if value:
        return value
    try:
        lines = (ROOT / ".env").read_text(encoding="utf-8").splitlines()
    except OSError:
        return ""
    found = [line[len(name) + 1 :] for line in lines if line.startswith(f"{name}=")]
    return found[-1].strip() if found else ""


class Handler(http.server.SimpleHTTPRequestHandler):
    client_id = ""

    def do_GET(self):
        if self.path.split("?", 1)[0] not in ("/", "/index.html"):
            return super().do_GET()
        body = fill((SITE / "index.html").read_text(encoding="utf-8"), self.client_id)
        data = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(data)


def serve(port: int, bind: str) -> None:
    client_id = setting("TABCAM_GOOGLE_LOCAL_WEB_CLIENT_ID") or setting(
        "TABCAM_GOOGLE_WEB_CLIENT_ID"
    )
    if client_id and not CLIENT_ID.fullmatch(client_id):
        print("warning: the Google client ID isn't one; no Google sign-in", file=sys.stderr)
        client_id = ""
    Handler.client_id = client_id
    handler = functools.partial(Handler, directory=str(SITE))
    with http.server.ThreadingHTTPServer((bind, port), handler) as server:
        print(
            f"index on http://{bind}:{port}/, Google sign-in "
            + ("on" if client_id else "off (no client ID)"),
            flush=True,
        )
        server.serve_forever()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    f = sub.add_parser("fill", help="stdin's page, the client ID filled in, to stdout")
    f.add_argument("client_id")
    s = sub.add_parser("serve", help="serve tabcam_index/site, filled in")
    s.add_argument("--port", type=int, default=2013)
    s.add_argument("--bind", default="127.0.0.1")
    args = parser.parse_args()
    if args.command == "fill":
        try:
            sys.stdout.write(fill(sys.stdin.read(), args.client_id))
        except ValueError as e:
            sys.exit(f"error: {e}")
    else:
        serve(args.port, args.bind)


if __name__ == "__main__":
    main()
