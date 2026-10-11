"""The two Lambda functions (one image, two handlers).

api (tabscan-ocr-api), light: it never loads the OCR engines.
  - S3 "Object Created" events for page images (EventBridge): if the page's
    owner is premium, invoke ocr for it (asynchronously). Free users' pages
    stop here.
  - S3 "Object Deleted" events: delete the page's transcription.
  - Its function URL, for the app, with the user's ID token (Google's, or
    Apple's when APPLE_CLIENT_ID is set; otherwise 403 "google sign-in
    needed"):
      POST /account     records which identity ID is which verified e-mail
                        (S3 events only carry the identity ID), and answers
                        whether the user is premium, with the upgrade links
      POST /transcribe  {"eventId"}: transcribes the event's pages that have
                        no transcription yet (pages from before upgrading)
      POST /autocorrect {"eventId", "song", "text"}: checks a text tab
                        against the song's tab found online (autocorrect.py)
                        and answers with per-note corrections

ocr (tabscan-ocr), heavy: reads one page and writes its transcription,
<identity>/ocr/<event id>/<page id>.json, which the app reads.
"""
import base64
import json
import os
import time
import traceback
from datetime import datetime, timezone

from . import keys

MAX_BYTES = 25 * 1024 * 1024
MAX_PAGES = 50
VERSION = os.environ.get("LOCR_VERSION", "dev")


def _now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def log(msg, **fields):
    """One JSON line in CloudWatch: what happened, and why. Never tokens."""
    print(json.dumps({"msg": msg, **fields}, default=str))


class Services:
    """AWS clients and helpers, made on first use; tests replace them."""

    def __init__(self):
        self._made = {}

    def _get(self, name, make):
        if name not in self._made:
            self._made[name] = make()
        return self._made[name]

    @property
    def s3(self):
        import boto3
        return self._get("s3", lambda: boto3.client("s3"))

    @property
    def lam(self):
        import boto3
        return self._get("lambda", lambda: boto3.client("lambda"))

    @property
    def accounts(self):
        return self._get("accounts", Accounts)

    @property
    def rbacr(self):
        from .premium import Rbacr
        return self._get("rbacr", Rbacr)

    @property
    def tokens(self):
        from .auth import TokenVerifier
        return self._get("tokens", TokenVerifier)

    @property
    def corrector(self):
        from .autocorrect import Corrector
        return self._get("corrector", Corrector)

    @property
    def cognito(self):
        from .auth import CognitoIdentities
        return self._get("cognito", CognitoIdentities)

    bucket = property(lambda self: os.environ["USER_DATA_BUCKET"])
    ocr_function = property(lambda self: os.environ["OCR_FUNCTION"])


class Accounts:
    """Identity ID -> verified e-mail, in DynamoDB. Only /account and
    /transcribe write it, from a checked ID token."""

    def __init__(self, table=None):
        import boto3
        self.table = table or boto3.resource("dynamodb").Table(os.environ["ACCOUNTS_TABLE"])

    def put(self, identity, email):
        self.table.put_item(Item={"identityId": identity, "email": email, "updatedAt": _now()})

    def email(self, identity):
        item = self.table.get_item(Key={"identityId": identity}).get("Item")
        return item and item.get("email")


services = Services()


# --- api ------------------------------------------------------------------

def api(event, context=None):
    if event.get("source") == "aws.s3":
        return on_s3(event)
    if "requestContext" in event and "http" in event["requestContext"]:
        return on_http(event)
    log("ignored event", keys=sorted(event))
    return None


def on_s3(event):
    outcome = _on_s3(event)
    detail = event.get("detail", {})
    log("s3 event", type=event.get("detail-type"), key=detail.get("object", {}).get("key"),
        outcome=outcome)
    return outcome


def _on_s3(event):
    detail = event.get("detail", {})
    if detail.get("bucket", {}).get("name") != services.bucket:
        return "other bucket"
    page = keys.parse_page(detail.get("object", {}).get("key", ""))
    if page is None:
        return "not a page"
    if event.get("detail-type") == "Object Deleted":
        services.s3.delete_object(Bucket=services.bucket, Key=page.result_key)
        return "deleted"
    if detail.get("object", {}).get("size", 0) > MAX_BYTES:
        return "too large"
    email = services.accounts.email(page.identity)
    if not email:
        log("unknown identity: the app hasn't called /account", identity=page.identity)
        return "not premium"
    if not services.rbacr.check(email).premium:
        return "not premium"
    _queue(page)
    return "queued"


def _queue(page):
    services.lam.invoke(FunctionName=services.ocr_function, InvocationType="Event",
                        Payload=json.dumps({"key": page.key}).encode())


def _reply(status, body):
    return {"statusCode": status, "headers": {"Content-Type": "application/json",
                                              "Cache-Control": "no-store"},
            "body": json.dumps(body)}


def on_http(event):
    start = time.monotonic()
    method = event["requestContext"]["http"]["method"]
    path = event.get("rawPath", "")
    request = {"method": method, "path": path}
    try:
        reply = _on_http(event, method, path, request)
    except Exception as e:
        log("http failed", **request, error=f"{type(e).__name__}: {e}",
            trace=traceback.format_exc())
        raise
    body = json.loads(reply["body"])
    body.pop("email", None)
    log("http", **request, status=reply["statusCode"],
        ms=round((time.monotonic() - start) * 1000), reply=body)
    return reply


def _on_http(event, method, path, request):
    from .auth import Unauthorized, Unsupported
    if method != "POST" or path not in ("/account", "/transcribe", "/autocorrect"):
        return _reply(404, {"error": "not found"})
    auth = {k.lower(): v for k, v in (event.get("headers") or {}).items()}.get("authorization", "")
    if not auth.lower().startswith("bearer "):
        return _reply(401, {"error": "sign in"})
    token = auth[7:].strip()
    try:
        email, login = services.tokens.verify(token)
        identity = services.cognito.identity(token, login)
    except Unsupported as e:
        request["unauthorized"] = str(e)
        return _reply(403, {"error": "google sign-in needed"})
    except Unauthorized as e:
        request["unauthorized"] = str(e)
        return _reply(401, {"error": "sign in again"})
    services.accounts.put(identity, email)
    answer = services.rbacr.check(email)
    request.update(identity=identity, premium=answer.premium, checked=answer.checked)
    if path == "/account":
        return _reply(200, {
            "email": email,
            "premium": answer.premium,
            "expiresAt": answer.expires_at,
            "checked": answer.checked,
            "upgradeUrl": os.environ.get("UPGRADE_URL", ""),
            "voucherUrl": os.environ.get("VOUCHER_URL", ""),
        })
    if not answer.premium:
        return _reply(402, {"error": "premium only", "upgradeUrl": os.environ.get("UPGRADE_URL", "")})
    try:
        body = event.get("body") or "{}"
        if event.get("isBase64Encoded"):
            body = base64.b64decode(body)
        body = json.loads(body)
        event_id = keys.check_id(body.get("eventId"))
    except (ValueError, AttributeError) as e:
        request["bad_body"] = f"{type(e).__name__}: {e}"
        return _reply(400, {"error": "eventId needed"})
    request["event"] = event_id
    if path == "/autocorrect":
        return _autocorrect(body, request)
    return _reply(200, {"queued": _transcribe_missing(identity, event_id)})


def _autocorrect(body, request):
    from .autocorrect import MAX_SONG, MAX_TEXT, NotSetUp
    text, song = body.get("text"), body.get("song") or ""
    if not isinstance(text, str) or not text.strip() or len(text) > MAX_TEXT \
            or not isinstance(song, str) or len(song) > MAX_SONG:
        request["bad_body"] = "text or song"
        return _reply(400, {"error": f"text (up to {MAX_TEXT} characters) needed"})
    try:
        result = services.corrector.correct(text, song)
    except NotSetUp as e:
        request["not_set_up"] = str(e)
        return _reply(503, {"error": "auto-correct isn't set up"})
    except Exception as e:  # the API or the web: logged, the user told to try later
        log("autocorrect failed", error=f"{type(e).__name__}: {e}", trace=traceback.format_exc())
        return _reply(502, {"error": "couldn't check online right now"})
    usage = result.pop("usage", None)
    log("autocorrect", event=request["event"], found=result["found"], notes=result["notes"],
        proposed=result["proposed"], kept=len(result["corrections"]), usage=usage)
    return _reply(200, result)


def _list(prefix):
    names, token = [], None
    while True:
        args = {"Bucket": services.bucket, "Prefix": prefix}
        if token:
            args["ContinuationToken"] = token
        r = services.s3.list_objects_v2(**args)
        names += [o["Key"] for o in r.get("Contents", [])]
        if not r.get("IsTruncated"):
            return names
        token = r["NextContinuationToken"]


def _transcribe_missing(identity, event_id):
    done = {k.rsplit("/", 1)[-1].removesuffix(".json") for k in _list(f"{identity}/ocr/{event_id}/")}
    files = _list(f"{identity}/events/{event_id}/")
    queued, skipped = 0, []
    for key in files:
        page = keys.parse_page(key)
        if page is None:
            skipped.append(key.rsplit("/", 1)[-1])  # not a page image (event.json, a video)
        elif page.page_id in done:
            continue
        elif queued < MAX_PAGES:
            _queue(page)
            queued += 1
    log("transcribe", identity=identity, event=event_id, files=len(files), done=len(done),
        queued=queued, not_pages=skipped)
    return queued


# --- ocr ------------------------------------------------------------------

_engines = None


def ocr(event, context=None):
    global _engines
    page = keys.parse_page(event.get("key", ""))
    if page is None:
        log("ocr bad key", key=event.get("key"))
        return None
    log("ocr start", key=page.key, engines_loaded=_engines is not None)
    from . import engines, pipeline
    if _engines is None:
        _engines = engines.default()
    result = {"page": page.page_id, "version": VERSION, "created": None}
    start = time.monotonic()
    try:
        obj = services.s3.get_object(Bucket=services.bucket, Key=page.key)
        if obj["ContentLength"] > MAX_BYTES:
            raise pipeline.TooLarge("image too large")
        r = pipeline.transcribe(obj["Body"].read(), _engines, read_page=engines.read_page)
        result.update(status="ok" if r.text else "no-tab", text=r.text,
                      staves=r.staves, lines=r.lines, timings=r.timings)
    except services.s3.exceptions.NoSuchKey:
        log("ocr page gone", key=page.key)
        return "gone"  # deleted meanwhile
    except (ValueError, pipeline.TooLarge) as e:
        result.update(status="error", text="", error=str(e))
    except Exception as e:  # logged, then retried by Lambda
        log("ocr failed", key=page.key, error=f"{type(e).__name__}: {e}",
            seconds=round(time.monotonic() - start, 2), trace=traceback.format_exc())
        raise
    result.update(seconds=round(time.monotonic() - start, 2), created=_now(),
                  engines=list(_engines))
    services.s3.put_object(Bucket=services.bucket, Key=page.result_key,
                           Body=json.dumps(result).encode(), ContentType="application/json")
    log("ocr done", key=page.key, status=result["status"], error=result.get("error"),
        staves=result.get("staves"), lines=result.get("lines"), timings=result.get("timings"),
        seconds=result["seconds"])
    return result["status"]
