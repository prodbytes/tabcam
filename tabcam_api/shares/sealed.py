"""TabCam's encrypted formats, as the app writes them (lib/cloud/sealed.dart
is the same), for the services that read captures: link previews here, the
cloud OCR service (a copy).

An encrypted capture's event.json keeps in the clear only what sync and the
API need, and its content key wrapped (keys.py):

    {"v": 1, "id": "<capture id>", "updated": ..., "owner": ...,
     "key": {"alg": "RSA-OAEP-256", "wrapped": "<base64>"},
     "sealed": "<base64: 12-byte nonce, then AES-256-GCM of the whole
                event's JSON, its tag last; the capture's ID as AAD>"}

A tombstone ("deleted") holds no content and isn't sealed.

A file (a page) is "TSE1", then its chunk size (4 bytes, big endian), then
a 7-byte nonce prefix, then its chunks: each up to the chunk size of
plaintext, encrypted with AES-256-GCM (16-byte tag after each), nonce = the
prefix, the chunk's number (4 bytes, big endian) and 1 for the last chunk
(else 0); AAD "tabcam:<capture id>/<file name>". So a file is read a chunk
at a time, and chunks can't be dropped, reordered or swapped between files.
"""

import base64
import json
import struct

MAGIC = b"TSE1"
HEADER = len(MAGIC) + 4 + 7
TAG = 16


class SealError(Exception):
    """Not sealed, or not with this key."""


def is_sealed_event(event):
    return isinstance(event, dict) and "sealed" in event and "key" in event


def wrapped_key(event):
    """The event's wrapped content key (base64), or None."""
    key = event.get("key") if isinstance(event, dict) else None
    return key.get("wrapped") if isinstance(key, dict) else None


def open_event(event, content_key):
    """The whole event, from its sealed event.json."""
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    try:
        blob = base64.b64decode(event["sealed"], validate=True)
        plain = AESGCM(content_key).decrypt(blob[:12], blob[12:], event["id"].encode())
        return json.loads(plain)
    except Exception as e:
        raise SealError(f"can't open the event: {e}") from e


def file_aad(capture_id, file_name):
    return f"tabcam:{capture_id}/{file_name}".encode()


def open_file(data, content_key, capture_id, file_name):
    """A sealed file's content (all of it: for files that fit in memory)."""
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    if len(data) < HEADER or data[:4] != MAGIC:
        raise SealError("not a sealed file")
    (chunk,) = struct.unpack(">I", data[4:8])
    prefix = data[8:15]
    if not 1 <= chunk <= 1 << 24:
        raise SealError("bad chunk size")
    aes = AESGCM(content_key)
    aad = file_aad(capture_id, file_name)
    out, at, n = [], HEADER, 0
    while True:
        end = min(at + chunk + TAG, len(data))
        last = end == len(data)
        nonce = prefix + struct.pack(">IB", n, 1 if last else 0)
        try:
            out.append(aes.decrypt(nonce, data[at:end], aad))
        except Exception as e:
            raise SealError(f"chunk {n} doesn't open") from e
        if last:
            return b"".join(out)
        at, n = end, n + 1
