"""The user-data bucket's keys, as the app writes them, and where results go.

    <identity>/events/<event id>/<page id>.<extension>   a page (the app)
    <identity>/ocr/<event id>/<page id>.json             its transcription (here)

Keys come from S3 events and requests, so everything is checked: an
identity is a Cognito identity ID, IDs and extensions are the app's own
patterns (lib/library/capture_event.dart).
"""
import re
from dataclasses import dataclass

IDENTITY = re.compile(r"^[a-z]{2}-[a-z]+-\d:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
ID = re.compile(r"^[a-z0-9]{1,32}$")
# Image pages: scans are JPEG files named .img; imported photos keep theirs.
IMAGE_EXTENSIONS = ("img", "jpg", "jpeg", "png", "webp")


@dataclass(frozen=True)
class PageKey:
    identity: str
    event_id: str
    page_id: str
    extension: str

    @property
    def key(self):
        return f"{self.identity}/events/{self.event_id}/{self.page_id}.{self.extension}"

    @property
    def result_key(self):
        return result_key(self.identity, self.event_id, self.page_id)


def parse_page(key):
    """The image page [key] names, or None (event.json, videos, anything else)."""
    parts = key.split("/")
    if len(parts) != 4 or parts[1] != "events":
        return None
    identity, _, event_id, name = parts
    page_id, dot, extension = name.partition(".")
    if not (dot and IDENTITY.match(identity) and ID.match(event_id) and ID.match(page_id)):
        return None
    if extension not in IMAGE_EXTENSIONS:
        return None
    return PageKey(identity, event_id, page_id, extension)


def result_key(identity, event_id, page_id):
    return f"{identity}/ocr/{event_id}/{page_id}.json"


def check_identity(identity):
    if not IDENTITY.match(identity or ""):
        raise ValueError("bad identity")
    return identity


def check_id(value):
    if not isinstance(value, str) or not ID.match(value):
        raise ValueError("bad id")
    return value
