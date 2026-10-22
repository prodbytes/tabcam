#!/usr/bin/env python3
"""Google Play uploads through the Android Publisher API (v3 edits), for
scripts/store-upload-android.sh: the store listing, or an App Bundle to a
testing track. Never the production track.

    play_publish.py listing <listing dir>            [--review]
    play_publish.py bundle <aab> <track> <status>    [--notes <file>] [--review]

Authenticates with an OAuth access token in PLAY_ACCESS_TOKEN (the script
gets one for the service account from gcloud: no key file). Changes are
committed without being sent for review unless --review is given (Play
Console's Publishing overview sends them otherwise); an app without
managed publishing takes no such commit, and its changes go to review.
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

PACKAGE = "com.nu01.tabcam"
API = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}"
UPLOAD = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACKAGE}"
LANGUAGE = "en-US"


class PlayError(Exception):
    pass


def call(method, url, body=None, data=None, content_type=None, fail=True):
    headers = {"Authorization": f"Bearer {os.environ['PLAY_ACCESS_TOKEN']}"}
    if body is not None:
        data = json.dumps(body).encode()
        content_type = "application/json"
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            raw = r.read()
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        try:
            detail = json.loads(detail)["error"]["message"]
        except (ValueError, KeyError, TypeError):
            pass
        message = f"{method} {url.split(PACKAGE)[-1]}: HTTP {e.code}: {detail}"
        if not fail:
            raise PlayError(message) from None
        sys.exit(f"error: {message}")
    return json.loads(raw) if raw else {}


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read().strip()


def listing(edit, folder):
    """Title, descriptions, icon, feature graphic and phone screenshots
    (in file name order) from [folder] (tabcam_store/android/en-US)."""
    call("PUT", f"{API}/edits/{edit}/listings/{LANGUAGE}", {
        "language": LANGUAGE,
        "title": read(os.path.join(folder, "title.txt")),
        "shortDescription": read(os.path.join(folder, "short_description.txt")),
        "fullDescription": read(os.path.join(folder, "full_description.txt")),
    })
    print("listing: title and descriptions")
    images = os.path.join(folder, "images")
    for kind, files in (
        ("icon", [os.path.join(images, "icon.png")]),
        ("featureGraphic", [os.path.join(images, "featureGraphic.png")]),
        ("phoneScreenshots", [os.path.join(images, "phoneScreenshots", n)
                              for n in sorted(os.listdir(os.path.join(images, "phoneScreenshots")),
                                              key=lambda n: (len(n), n))
                              if n.endswith(".png")]),
    ):
        call("DELETE", f"{API}/edits/{edit}/listings/{LANGUAGE}/{kind}")
        for path in files:
            with open(path, "rb") as f:
                call("POST", f"{UPLOAD}/edits/{edit}/listings/{LANGUAGE}/{kind}?uploadType=media",
                     data=f.read(), content_type="image/png")
        print(f"listing: {kind}: {', '.join(os.path.basename(p) for p in files)}")


def bundle(edit, aab, track, status, notes):
    with open(aab, "rb") as f:
        version = call("POST", f"{UPLOAD}/edits/{edit}/bundles?uploadType=media",
                       data=f.read(), content_type="application/octet-stream")["versionCode"]
    print(f"bundle: version code {version}")
    release = {"versionCodes": [str(version)], "status": status}
    if notes:
        release["releaseNotes"] = [{"language": LANGUAGE, "text": read(notes)}]
    call("PUT", f"{API}/edits/{edit}/tracks/{urllib.parse.quote(track)}",
         {"track": track, "releases": [release]})
    print(f"track {track}: version {version}, {status}")


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="what", required=True)
    s = sub.add_parser("listing")
    s.add_argument("folder")
    s.add_argument("--review", action="store_true")
    b = sub.add_parser("bundle")
    b.add_argument("aab")
    b.add_argument("track")
    b.add_argument("status", choices=["draft", "completed"])
    b.add_argument("--notes")
    b.add_argument("--review", action="store_true")
    args = p.parse_args()
    if args.what == "bundle" and args.track == "production":
        sys.exit("error: no production uploads from here")
    if not os.environ.get("PLAY_ACCESS_TOKEN"):
        sys.exit("error: PLAY_ACCESS_TOKEN isn't set")

    edit = call("POST", f"{API}/edits", {})["id"]
    if args.what == "listing":
        listing(edit, args.folder)
    else:
        bundle(edit, args.aab, args.track, args.status, args.notes)
    if args.review:
        call("POST", f"{API}/edits/{edit}:commit")
        print("committed, sent for review")
        return
    try:
        call("POST", f"{API}/edits/{edit}:commit?changesNotSentForReview=true", fail=False)
        print("committed: send it for review in Play Console's Publishing overview")
    except PlayError as e:
        # Apps without managed publishing take no unreviewed commits: Play
        # sends every change for review.
        if "changesNotSentForReview must not be set" not in str(e):
            sys.exit(f"error: {e}")
        call("POST", f"{API}/edits/{edit}:commit")
        print("committed, sent for review (Play sends this app's changes automatically)")


if __name__ == "__main__":
    main()
