"""The two Lambda functions (one image, two handlers).

api (tabcam-ocr-api), light: it never loads the OCR engines.
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
      POST /transcribe  {"eventId", "again"?}: transcribes the event's pages
                        that have no transcription yet (pages from before
                        upgrading); with "again", every page (Read again);
                        never a page being read already
      POST /warm        loads the engines in an ocr function ahead of a
                        page (the app, as the camera opens), at most once
                        every few minutes per user
      POST /autocorrect {"eventId", "song", "text"}: checks a text tab
                        against the song's tab found online (autocorrect.py)
                        and answers with per-note corrections
      POST /page        {"url"}: a tab site's page, for the web app, which
                        can't fetch other sites' pages (pages.py)

ocr (tabcam-ocr), heavy: reads one page and writes its transcription,
<identity>/ocr/<event id>/<page id>.json, which the app reads; not when
the page was deleted meanwhile. {"warm": true} only loads the engines.
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
# A page being read has a marker beside its transcription (.reading), so
# asking again doesn't start a second reading while the first is under
# way; one older than the ocr function's timeout (15 min) is stale.
READING_FOR = 15 * 60
# A user's warm-up asks: at most one per this many seconds (per api
# container), about as long as an idle ocr function stays warm.
WARM_EVERY = 5 * 60
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
    def profiles(self):
        return self._get("profiles", ProfileDirectory)

    @property
    def cognito(self):
        from .auth import CognitoIdentities
        return self._get("cognito", CognitoIdentities)

    bucket = property(lambda self: os.environ["USER_DATA_BUCKET"])
    ocr_function = property(lambda self: os.environ["OCR_FUNCTION"])


class ProfileDirectory:
    """The share API's profiles (read only): a sign-in's profile, its
    folder (Cognito identity) and its addresses. Without the tables set up
    (PROFILES_TABLE, SUBJECTS_TABLE), no profiles: each sign-in is its own
    identity, as before profiles."""

    def __init__(self, profiles=None, subjects=None):
        names = os.environ.get("PROFILES_TABLE"), os.environ.get("SUBJECTS_TABLE")
        if profiles is None and all(names):
            import boto3
            db = boto3.resource("dynamodb")
            profiles, subjects = db.Table(names[0]), db.Table(names[1])
        self.profiles, self.subjects = profiles, subjects

    def of(self, subject):
        """(identity ID or None, addresses) of the subject's profile, or
        None when it has none (yet)."""
        if self.subjects is None:
            return None
        link = self.subjects.get_item(Key={"subject": subject}).get("Item")
        if link is None:
            return None
        profile = self.profiles.get_item(Key={"id": link["profileId"]}).get("Item") or {}
        linked = self.subjects.query(
            IndexName="byProfile", KeyConditionExpression="#p = :p",
            ExpressionAttributeNames={"#p": "profileId"},
            ExpressionAttributeValues={":p": link["profileId"]})["Items"]
        emails = sorted({i["email"] for i in linked if i.get("email")})
        return profile.get("identityId"), emails


class Accounts:
    """Identity ID -> verified e-mail addresses (a profile's), in DynamoDB.
    Only /account and /transcribe write it, from a checked ID token."""

    # What this container wrote last, and when: the same again within an
    # hour isn't written again (every request would, otherwise).
    REWRITE_AFTER = 3600

    def __init__(self, table=None):
        import boto3
        self.table = table or boto3.resource("dynamodb").Table(os.environ["ACCOUNTS_TABLE"])
        self._written = {}

    def put(self, identity, emails):
        emails = [emails] if isinstance(emails, str) else list(emails)
        last = self._written.get(identity)
        if last and last[0] == emails and time.monotonic() - last[1] < self.REWRITE_AFTER:
            return
        self.table.put_item(Item={"identityId": identity, "email": emails[0], "emails": emails,
                                  "updatedAt": _now()})
        self._written[identity] = (emails, time.monotonic())

    def emails(self, identity):
        item = self.table.get_item(Key={"identityId": identity}).get("Item") or {}
        return list(item.get("emails") or ([item["email"]] if item.get("email") else []))

    def email(self, identity):
        found = self.emails(identity)
        return found[0] if found else None


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
        services.s3.delete_object(Bucket=services.bucket, Key=page.reading_key)
        return "deleted"
    if detail.get("object", {}).get("size", 0) > MAX_BYTES:
        return "too large"
    emails = services.accounts.emails(page.identity)
    if not emails:
        log("unknown identity: the app hasn't called /account", identity=page.identity)
        return "not premium"
    if not _premium(emails).premium:
        return "not premium"
    if _from_cache(page, detail.get("object", {}).get("etag")):
        return "cached"
    _queue(page)
    return "queued"


def _from_cache(page, etag):
    """Writes [page]'s transcription from an earlier reading of the same
    image (a clone, a published contribution, the same file added again),
    if there's one: no second reading. Read again never comes here."""
    key = keys.cache_key(page.identity, etag, VERSION)
    if key is None:
        return False
    try:
        cached = json.loads(services.s3.get_object(Bucket=services.bucket, Key=key)["Body"].read())
    except services.s3.exceptions.NoSuchKey:
        return False
    except Exception as e:  # a cache that can't be read: read the page
        log("ocr cache unreadable", key=key, error=f"{type(e).__name__}: {e}")
        return False
    cached.update(page=page.page_id, created=_now(), cached=True)
    services.s3.put_object(Bucket=services.bucket, Key=page.result_key,
                           Body=json.dumps(cached).encode(), ContentType="application/json",
                           CacheControl="no-cache")
    log("ocr from cache", key=page.key, cache=key)
    return True


def _queue(page):
    services.s3.put_object(Bucket=services.bucket, Key=page.reading_key,
                           Body=_now().encode(), ContentType="text/plain")
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
    if "html" in body:  # a fetched page: its size only
        body["html"] = len(body["html"])
    log("http", **request, status=reply["statusCode"],
        ms=round((time.monotonic() - start) * 1000), reply=body)
    return reply


def _on_http(event, method, path, request):
    from .auth import Unauthorized, Unsupported
    if method != "POST" or path not in ("/account", "/transcribe", "/autocorrect", "/page",
                                        "/warm"):
        return _reply(404, {"error": "not found"})
    auth = {k.lower(): v for k, v in (event.get("headers") or {}).items()}.get("authorization", "")
    if not auth.lower().startswith("bearer "):
        return _reply(401, {"error": "sign in"})
    token = auth[7:].strip()
    try:
        email, login, subject = services.tokens.verify_subject(token)
        # The sign-in's profile: its folder, and every linked address.
        found = services.profiles.of(subject)
        if found is None:
            identity, emails = services.cognito.identity(token, login), [email]
        else:
            identity, emails = found
            emails = emails or [email]
    except Unsupported as e:
        request["unauthorized"] = str(e)
        return _reply(403, {"error": "google sign-in needed"})
    except Unauthorized as e:
        request["unauthorized"] = str(e)
        return _reply(401, {"error": "sign in again"})
    if identity:
        services.accounts.put(identity, emails)
    answer = _premium(emails)
    request.update(identity=identity, premium=answer.premium, checked=answer.checked,
                   addresses=len(emails))
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
    if path == "/warm":
        return _reply(200, {"warming": _warm(identity or email)})
    try:
        body = event.get("body") or "{}"
        if event.get("isBase64Encoded"):
            body = base64.b64decode(body)
        body = json.loads(body)
        event_id = None if path == "/page" else keys.check_id(body.get("eventId"))
    except (ValueError, AttributeError) as e:
        request["bad_body"] = f"{type(e).__name__}: {e}"
        return _reply(400, {"error": "eventId needed"})
    if path == "/page":
        return _page(body, request)
    request["event"] = event_id
    if path == "/autocorrect":
        return _autocorrect(body, request)
    if not identity:  # a profile whose folder isn't made yet: nothing synced
        return _reply(200, {"queued": 0})
    # "again" (the app's Read again): every page, read results too.
    again = body.get("again") is True
    request["again"] = again
    return _reply(200, {"queued": _transcribe_missing(identity, event_id, again)})


def _page(body, request):
    from .pages import FetchFailed, NotATabSite, check, fetch
    try:
        url = check(body.get("url") if isinstance(body, dict) else None)
    except NotATabSite as e:
        request["bad_body"] = str(e)
        return _reply(400, {"error": "a tab site's page needed"})
    request["url"] = url
    try:
        page = fetch(url)
    except NotATabSite as e:  # redirected off the tab sites
        request["redirected"] = str(e)
        return _reply(502, {"error": "couldn't fetch the page"})
    except FetchFailed as e:
        request["failed"] = str(e)
        return _reply(502, {"error": "couldn't fetch the page"})
    return _reply(200, page)


def _premium(emails):
    """Premium if any of the addresses is; checked only if every "no" was."""
    from .premium import Answer
    answers = [services.rbacr.check(e) for e in emails]
    for a in answers:
        if a.premium:
            return a
    return Answer(False, None, all(a.checked for a in answers))


def _autocorrect(body, request):
    from .autocorrect import MAX_SONG, MAX_TEXT, NotSetUp
    text, song = body.get("text"), body.get("song") or ""
    if not isinstance(text, str) or not text.strip() or len(text) > MAX_TEXT \
            or not isinstance(song, str) or len(song) > MAX_SONG:
        request["bad_body"] = "text or song"
        return _reply(400, {"error": f"text (up to {MAX_TEXT} characters) needed"})
    # Off unless switched on (AUTOCORRECT_ENABLED=1): the app hides Fix, and
    # the Claude key being there (for other uses) mustn't turn it on.
    if os.environ.get("AUTOCORRECT_ENABLED") != "1":
        request["not_set_up"] = "switched off"
        return _reply(503, {"error": "auto-correct isn't set up"})
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


_warmed = {}  # who asked for a warm-up -> when (monotonic)


def _warm(who):
    """An ocr function loading its engines, unless this user asked lately."""
    now = time.monotonic()
    if now - _warmed.get(who, -WARM_EVERY) < WARM_EVERY:
        return False
    _warmed[who] = now
    services.lam.invoke(FunctionName=services.ocr_function, InvocationType="Event",
                        Payload=json.dumps({"warm": True}).encode())
    return True


def _objects(prefix):
    found, token = [], None
    while True:
        args = {"Bucket": services.bucket, "Prefix": prefix}
        if token:
            args["ContinuationToken"] = token
        r = services.s3.list_objects_v2(**args)
        found += r.get("Contents", [])
        if not r.get("IsTruncated"):
            return found
        token = r["NextContinuationToken"]


def _list(prefix):
    return [o["Key"] for o in _objects(prefix)]


def _transcribe_missing(identity, event_id, again=False):
    results = _objects(f"{identity}/ocr/{event_id}/")
    names = {o["Key"].rsplit("/", 1)[-1]: o for o in results}
    done = set() if again else {n.removesuffix(".json") for n in names if n.endswith(".json")}
    now = datetime.now(timezone.utc)
    reading = {n.removesuffix(".reading") for n, o in names.items()
               if n.endswith(".reading")
               and (now - o["LastModified"]).total_seconds() < READING_FOR}
    files = _list(f"{identity}/events/{event_id}/")
    queued, skipped, busy = 0, [], 0
    for key in files:
        page = keys.parse_page(key)
        if page is None:
            skipped.append(key.rsplit("/", 1)[-1])  # not a page image (event.json, a video)
        elif page.page_id in done:
            continue
        elif page.page_id in reading:
            busy += 1  # its reading is under way: it'll be written
        elif queued < MAX_PAGES:
            _queue(page)
            queued += 1
    log("transcribe", identity=identity, event=event_id, files=len(files), done=len(done),
        reading=busy, queued=queued, not_pages=skipped)
    return queued


# --- ocr ------------------------------------------------------------------

_engines = None


def _vision(img):
    """Claude's reading of a page the engines find no tab on; "" while the
    Claude API key isn't set up, or when Claude fails (logged)."""
    from . import claude, vision
    try:
        return vision.read_tab(img)
    except claude.NotSetUp:
        return ""
    except Exception as e:
        log("vision failed", error=f"{type(e).__name__}: {e}")
        return ""


def _load_engines():
    """The engines and their models, loaded once per container, and run
    once on a blank image (their first run sets more up)."""
    global _engines
    if _engines is not None:
        return False
    import numpy as np
    from . import engines
    found = engines.default()
    blank = np.full((48, 160, 3), 255, np.uint8)
    engines._paddle().predict(blank)
    engines._rapid()(blank)
    _engines = found
    return True


def _still_there(page):
    """Whether [page] is still in the bucket (not deleted while read)."""
    try:
        services.s3.head_object(Bucket=services.bucket, Key=page.key)
        return True
    except Exception as e:
        code = getattr(e, "response", {}).get("Error", {}).get("Code")
        if code in ("404", "NoSuchKey", "NotFound"):
            return False
        raise


def ocr(event, context=None):
    if event.get("warm") is True:
        start = time.monotonic()
        loaded = _load_engines()
        log("ocr warm", loaded=loaded, seconds=round(time.monotonic() - start, 2))
        return "warm"
    page = keys.parse_page(event.get("key", ""))
    if page is None:
        log("ocr bad key", key=event.get("key"))
        return None
    log("ocr start", key=page.key, engines_loaded=_engines is not None)
    try:
        return _read(page)
    finally:
        # Read (or failed: Lambda's retry is queued already): a new ask may
        # read it again.
        services.s3.delete_object(Bucket=services.bucket, Key=page.reading_key)


def _read(page):
    from . import engines, pipeline
    t = time.monotonic()
    if _load_engines():
        log("ocr engines loaded", seconds=round(time.monotonic() - t, 2))
    result = {"page": page.page_id, "version": VERSION, "created": None}
    start = time.monotonic()
    try:
        obj = services.s3.get_object(Bucket=services.bucket, Key=page.key)
        if obj["ContentLength"] > MAX_BYTES:
            raise pipeline.TooLarge("image too large")
        read = pipeline.transcribe_pdf if page.is_pdf else pipeline.transcribe
        r = read(obj["Body"].read(), _engines, read_page=engines.read_page,
                 read_crop=engines.read_crop,
                 vision=_vision if os.environ.get("VISION_FALLBACK") == "1" else None)
        result.update(status="ok" if r.text else "no-tab", text=r.text,
                      doubts=r.doubts, staves=r.staves, lines=r.lines, timings=r.timings)
        if "claude" in r.timings:
            result["engines"] = ["claude"]
    except services.s3.exceptions.NoSuchKey:
        log("ocr page gone", key=page.key)
        return "gone"  # deleted meanwhile
    except (ValueError, pipeline.TooLarge) as e:
        result.update(status="error", text="", error=str(e))
    except Exception as e:  # logged, then retried by Lambda
        log("ocr failed", key=page.key, error=f"{type(e).__name__}: {e}",
            seconds=round(time.monotonic() - start, 2), trace=traceback.format_exc())
        raise
    result.update(seconds=round(time.monotonic() - start, 2), created=_now())
    result.setdefault("engines", list(_engines))
    if not _still_there(page):
        # Deleted while it was read: its transcription would outlive it.
        log("ocr page gone", key=page.key, seconds=result["seconds"])
        return "gone"
    # Rewritten by a new reading: readers revalidate it (its ETag) each time.
    services.s3.put_object(Bucket=services.bucket, Key=page.result_key,
                           Body=json.dumps(result).encode(), ContentType="application/json",
                           CacheControl="no-cache")
    # Kept by the image's content too, so a copy of it isn't read again
    # (a failed reading isn't: the next one tries again).
    cache = keys.cache_key(page.identity, obj.get("ETag"), VERSION)
    if cache and result["status"] in ("ok", "no-tab"):
        services.s3.put_object(Bucket=services.bucket, Key=cache,
                               Body=json.dumps(result).encode(), ContentType="application/json")
    log("ocr done", key=page.key, status=result["status"], error=result.get("error"),
        staves=result.get("staves"), lines=result.get("lines"), timings=result.get("timings"),
        seconds=result["seconds"])
    return result["status"]
