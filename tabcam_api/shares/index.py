"""TabCam's share API: who a capture is shared with, and credentials to it.

A capture (an event) lives in its owner's folder of the user-data bucket,
<owner identity>/events/<capture id>/. Its owner grants it to email
addresses, to edit (the default) or read only. Someone signed in with a
granted address lists what's shared with them, and gets temporary
credentials for just that capture's folder: get and list, plus put and
delete to edit. No email is sent.

Behind an HTTP API with JWT authorizers, so every request carries a
verified ID token: Google's (for the TabCam web client) at the routes
below, or Apple's (Sign in with Apple, for the app's bundle ID) at the same
routes under /apple. Each path has the authorizer of its issuer, and the
function checks the token's issuer matches the path. The caller's Cognito
identity (their folder) comes from that token too (GetId, with the token
under its issuer's Logins key: Google and Apple sign-ins are different
identities).

Every sign-in belongs to a profile (profiles.py), created the first time
it's seen: the profile's Cognito identity (a developer identity) is the
folder, shared by every sign-in linked to it, and its addresses are all
those sign-ins' verified ones.

Routes (each also under /apple, for Apple's tokens):
  GET    /profile                                 my profile: ID, accounts, roles
  POST   /profile/link-code                       a code to link another sign-in
  POST   /profile/link                            {code}: join that profile
  POST   /profile/unlink                          {id}: unlink an account
  POST   /profile/credentials                     a Cognito token for its folder
  GET    /shares/{captureId}                      the capture's grants (owner)
  PUT    /shares/{captureId}                      grant {email, role} (owner)
  DELETE /shares/{captureId}?email=               revoke (owner)
  GET    /shared                                  what's shared with me
  DELETE /shared/{owner}/{captureId}              leave a share
  POST   /shared/{owner}/{captureId}/credentials  credentials for it
  DELETE /account                                 delete my profile (its owner);
                                                  under /apple, {appleAuthorizationCode}
                                                  revokes my Apple tokens too
  PUT    /links/{captureId}                       {key}: anyone with the link
                                                  (…/app/?c=<id>&k=<key>) may
                                                  read the capture (owner)
  POST   /keys/{owner}/{captureId}                the capture's content key
                                                  (its owner, or someone it's
                                                  shared with; keys.py)

And two routes without a token (no authorizer), for anyone holding a link:
  POST   /public/{captureId}/credentials          {key}: read-only credentials
                                                  for that capture's folder,
                                                  and its content key when
                                                  it's encrypted
  GET    /preview/{captureId}/{key}               the link's preview page:
                                                  the capture's title and
                                                  what it holds, for chat
                                                  apps' link previews (the
                                                  site sends their crawlers
                                                  here)

Every route acts on the caller's profile alone: as an owner, on its
Cognito identity; as a grantee, on its verified addresses.
"""

import base64
import hashlib
import html
import json
import os
import re
import time

import apple_revoke
import keys as pkeys
import profiles as prof
import sealed

ROLES = ("edit", "read")
MAX_GRANTS = int(os.environ.get("MAX_GRANTS", "50"))
ID = re.compile(r"^[a-z0-9]{1,32}$")
IDENTITY = re.compile(r"^[a-z]{2}(-[a-z]+)+-\d:[0-9a-f-]{36}$")
# A link's key: random, made by the app (only its SHA-256 is kept).
LINK_KEY = re.compile(r"^[A-Za-z0-9_-]{32,64}$")
PUBLIC_ROUTE = "POST /public/{captureId}/credentials"
PREVIEW_ROUTE = "GET /preview/{captureId}/{key}"
# The sites a preview may name (the site's CloudFront sends its own in
# x-tabcam-site); production's by default.
SITES = ("tabcam.nu01.com", "rc.tabcam.nu01.com")
EMAIL = re.compile(r"^[^@\s]{1,64}@[A-Za-z0-9.-]{1,189}\.[A-Za-z]{2,}$")

# The issuers whose tokens the API takes: the path prefix of their routes,
# and the token's key in Cognito's Logins.
GOOGLE = "https://accounts.google.com"
APPLE = "https://appleid.apple.com"
PREFIXES = {GOOGLE: "", APPLE: "/apple"}
LOGINS = {GOOGLE: "accounts.google.com", APPLE: "appleid.apple.com"}
PROVIDERS = {GOOGLE: "google", APPLE: "apple"}
# The identity pool's developer provider: a profile's Cognito identity is
# the developer identity of its ID.
DEVELOPER = os.environ.get("DEVELOPER_PROVIDER", "login.tabcam.profiles")


class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status
        self.message = message


def _clients():
    import boto3

    region = os.environ.get("AWS_REGION", "us-east-1")
    dynamodb = boto3.resource("dynamodb", region_name=region)
    accounts = os.environ.get("ACCOUNTS_TABLE")
    keys_table = os.environ.get("PROFILE_KEYS_TABLE")
    keys = dynamodb.Table(keys_table) if keys_table else None
    return {
        "table": dynamodb.Table(os.environ["TABLE"]),
        # Profile keys (keys.py): off without the table and the KMS key.
        "keys": keys if os.environ.get("PROFILE_KEY_ID") else None,
        "kms": boto3.client("kms", region_name=region),
        "links": dynamodb.Table(os.environ["LINKS_TABLE"]),
        # The cloud OCR service's identity -> address table, if it's set up.
        "accounts": dynamodb.Table(accounts) if accounts else None,
        "cognito": boto3.client("cognito-identity", region_name=region),
        "sts": boto3.client("sts", region_name=region),
        "s3": boto3.client("s3", region_name=region),
        # S3 as some temporary credentials (a link's, read only).
        "s3_as": lambda c: boto3.client(
            "s3",
            region_name=region,
            aws_access_key_id=c["accessKeyId"],
            aws_secret_access_key=c["secretAccessKey"],
            aws_session_token=c["sessionToken"],
        ),
        "store": prof.Store(
            dynamodb.Table(os.environ["PROFILES_TABLE"]),
            dynamodb.Table(os.environ["SUBJECTS_TABLE"]),
            dynamodb.Table(os.environ["LINK_CODES_TABLE"]),
            keys=keys,
        ),
        "rbacr": prof.Rbacr(),
        # Sign in with Apple's key, read when an Apple account is deleted.
        "apple_key": lambda: apple_revoke.Key.load(boto3.client("ssm", region_name=region)),
        "apple_open": None,
    }


_cached = None


def handler(event, context, clients=None):
    global _cached
    if clients is None:
        _cached = _cached or _clients()
        clients = _cached
    try:
        if event.get("routeKey") == PUBLIC_ROUTE:
            return _json(200, public_credentials(event, clients))
        if event.get("routeKey") == PREVIEW_ROUTE:
            return preview(event, clients)
        return _json(200, Api(event, clients).route())
    except ApiError as e:
        return _json(e.status, {"message": e.message})


def _json(status, body):
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def _email(value):
    if not isinstance(value, str) or not EMAIL.match(value.strip()):
        raise ApiError(400, "Not an email address")
    return value.strip().lower()


def _id(value):
    if not isinstance(value, str) or not ID.match(value):
        raise ApiError(400, "Not a capture ID")
    return value


def _identity(value):
    if not isinstance(value, str) or not IDENTITY.match(value):
        raise ApiError(400, "Not an owner ID")
    return value


def _key(owner, capture_id):
    return f"{owner}#{capture_id}"


def _link_key(value):
    if not isinstance(value, str) or not LINK_KEY.match(value):
        raise ApiError(400, "Not a link key")
    return hashlib.sha256(value.encode()).hexdigest()


def _body_of(event):
    try:
        body = json.loads(event.get("body") or "{}")
    except ValueError:
        raise ApiError(400, "The body isn't JSON")
    if not isinstance(body, dict):
        raise ApiError(400, "The body isn't a JSON object")
    return body


def query_all(table, **kwargs):
    """Every item a query matches, page after page."""
    items = []
    while True:
        page = table.query(**kwargs)
        items += page["Items"]
        if "LastEvaluatedKey" not in page:
            return items
        kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]


def folder_credentials(sts, owner, capture_id, role):
    """Credentials for the capture's folder alone: get and list, plus put
    and delete to edit."""
    bucket = os.environ["BUCKET"]
    prefix = f"{owner}/events/{capture_id}/"
    actions = ["s3:GetObject"]
    if role == "edit":
        actions += ["s3:PutObject", "s3:DeleteObject"]
    policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": actions,
                "Resource": f"arn:aws:s3:::{bucket}/{prefix}*",
            },
            {
                "Effect": "Allow",
                "Action": "s3:ListBucket",
                "Resource": f"arn:aws:s3:::{bucket}",
                "Condition": {"StringLike": {"s3:prefix": [prefix, f"{prefix}*"]}},
            },
        ],
    }
    result = sts.assume_role(
        RoleArn=os.environ["ACCESS_ROLE_ARN"],
        RoleSessionName=f"share-{capture_id}"[:64],
        Policy=json.dumps(policy),
        DurationSeconds=3600,
    )
    c = result["Credentials"]
    return {
        "accessKeyId": c["AccessKeyId"],
        "secretAccessKey": c["SecretAccessKey"],
        "sessionToken": c["SessionToken"],
        "expiration": int(c["Expiration"].timestamp()),
        "prefix": prefix,
        "role": role,
    }


def public_credentials(event, clients):
    """Anyone with a capture's link (its ID and key, no sign-in): read-only
    credentials for its folder, and whose folder it is. A wrong key and an
    unknown one are the same 404."""
    capture_id = _id((event.get("pathParameters") or {}).get("captureId"))
    digest = _link_key(_body_of(event).get("key"))
    item = clients["links"].get_item(Key={"keyHash": digest}).get("Item")
    if item is None or item.get("captureId") != capture_id:
        raise ApiError(404, "No such link")
    owner = item["owner"]
    creds = folder_credentials(clients["sts"], owner, capture_id, "read")
    body = {"owner": owner, **creds}
    content_key = _content_key(clients, owner, capture_id, creds)
    if content_key is not None:
        body["contentKey"] = content_key
    return body


def _read_event(clients, owner, capture_id, creds):
    """The capture's event.json, read with [creds] (its folder's, read
    only); None when it isn't there."""
    s3 = clients["s3_as"](creds)
    try:
        body = s3.get_object(
            Bucket=os.environ["BUCKET"], Key=f"{owner}/events/{capture_id}/event.json"
        )["Body"].read()
    except Exception as e:
        if "NoSuchKey" in str(e) or type(e).__name__ == "NoSuchKey":
            return None
        raise
    return json.loads(body)


def _content_key_bytes(clients, owner, capture_id, event):
    """An encrypted capture's content key (its event as read), unwrapped
    with the owner profile's private key; None when it isn't encrypted."""
    wrapped = sealed.wrapped_key(event)
    if wrapped is None:
        return None
    if clients.get("keys") is None:
        raise ApiError(503, "Keys aren't set up")
    profile = clients["store"].profile_by_identity(owner)
    if profile is None:
        raise ApiError(404, "No such capture")
    try:
        return pkeys.unwrap(clients["keys"], clients["kms"], profile["id"], capture_id, wrapped)
    except pkeys.KeyError_ as e:
        print(f"key of {owner}/{capture_id}: {e}")
        raise ApiError(409, "That capture's key doesn't open") from e


def _content_key(clients, owner, capture_id, creds):
    """The capture's content key, base64, or None (not encrypted, or not
    there yet)."""
    event = _read_event(clients, owner, capture_id, creds)
    key = None if event is None else _content_key_bytes(clients, owner, capture_id, event)
    return None if key is None else base64.b64encode(key).decode()


def preview(event, clients):
    """The page a capture's link shows chat apps (WhatsApp, iMessage,
    Slack...), whose crawlers don't run the app: the capture's title and
    what it holds, as Open Graph tags, for a key that opens it; else
    TabCam's own. People who land here go on to the app."""
    params = event.get("pathParameters") or {}
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    site = headers.get("x-tabcam-site")
    site = site if site in SITES else SITES[0]
    capture_id = params.get("captureId") or ""
    key = params.get("key") or ""
    valid = bool(ID.match(capture_id) and LINK_KEY.match(key))
    link = (f"https://{site}/app/?c={capture_id}&k={key}" if valid
            else f"https://{site}/app/")
    title, description = "TabCam", "Scan and share guitar tabs."
    if valid:
        try:
            capture = _linked_capture(clients, capture_id, key)
        except Exception as e:  # a wrong key, a deleted capture, S3
            print(f"preview of {capture_id}: {e}")
            capture = None
        if capture is not None:
            title, description = _preview_text(capture)
    page = PREVIEW_PAGE.format(
        title=html.escape(title),
        description=html.escape(description),
        link=html.escape(link),
        image=html.escape(f"https://{site}/app/icons/Icon-512.png"),
        link_js=json.dumps(link),
    )
    return {
        "statusCode": 200,
        "headers": {
            "content-type": "text/html; charset=utf-8",
            # A rename shows in new previews within minutes.
            "cache-control": "public, max-age=300",
            "x-robots-tag": "noindex",
        },
        "body": page,
    }


def _linked_capture(clients, capture_id, key):
    """The capture's event.json, read with the link's own read-only
    credentials; None for a key that doesn't open it, or a deleted one."""
    item = clients["links"].get_item(Key={"keyHash": _link_key(key)}).get("Item")
    if item is None or item.get("captureId") != capture_id:
        return None
    owner = item["owner"]
    creds = folder_credentials(clients["sts"], owner, capture_id, "read")
    capture = _read_event(clients, owner, capture_id, creds)
    if capture is None or capture.get("deleted"):
        return None
    if sealed.is_sealed_event(capture):
        key = _content_key_bytes(clients, owner, capture_id, capture)
        capture = sealed.open_event(capture, key)
    return capture


def _preview_text(capture):
    """A capture's preview: its title (with the artist), and what it holds:
    "Black Sabbath · 3 pages, 1 PDF, a text tab"."""
    title = (capture.get("title") or "").strip() or "TabCam"
    artist = (capture.get("artist") or "").strip()
    counts = {}
    for page in capture.get("pages") or []:
        kind = page.get("kind") or "image"
        counts[kind] = counts.get(kind, 0) + 1
    names = (("image", "page"), ("pdf", "PDF"), ("video", "video"),
             ("audio", "recording"), ("link", "link"))
    held = [f"{counts[k]} {name}{'' if counts[k] == 1 else 's'}"
            for k, name in names if counts.get(k)]
    if capture.get("hideImages"):
        held = [h for h in held if not h.endswith(("page", "pages"))]
    if (capture.get("tabText") or "").strip():
        held.append("a text tab")
    parts = [p for p in (artist, ", ".join(held)) if p]
    description = " · ".join(parts) or "A guitar tab"
    return (f"{title} – {artist}" if artist else title), f"{description}. Shared with TabCam."


PREVIEW_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{description}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="TabCam">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{description}">
<meta property="og:url" content="{link}">
<meta property="og:image" content="{image}">
<meta name="twitter:card" content="summary">
<meta name="twitter:title" content="{title}">
<meta name="twitter:description" content="{description}">
<link rel="canonical" href="{link}">
</head>
<body>
<p><a href="{link}">{title}</a></p>
<script>location.replace({link_js});</script>
</body>
</html>
"""


class Api:
    def __init__(self, event, clients):
        self.event = event
        self.table = clients["table"]
        self.links = clients.get("links")
        self.cognito = clients["cognito"]
        self.sts = clients["sts"]
        self.accounts = clients.get("accounts")
        self.s3 = clients.get("s3")
        self.store = clients["store"]
        self.profiles = prof.Profiles(self.store)
        self.rbacr = clients["rbacr"]
        self.clients = clients
        self.keys = clients.get("keys")
        self.kms = clients.get("kms")
        self._profile_item = None
        claims = (
            event.get("requestContext", {})
            .get("authorizer", {})
            .get("jwt", {})
            .get("claims", {})
        )
        # The route's own key, without the issuer's prefix. API Gateway has
        # checked the token with that path's authorizer; this makes sure the
        # issuer is the path's too, so a token is never taken as another
        # provider's.
        method, _, path = (event.get("routeKey") or "").partition(" ")
        issuer = APPLE if path.startswith("/apple/") else GOOGLE
        if claims.get("iss") != issuer:
            raise ApiError(401, "Sign in again")
        self.login = LOGINS[issuer]
        self.provider = PROVIDERS[issuer]
        if not claims.get("sub"):
            raise ApiError(401, "Sign in again")
        # The sign-in, never the email: an address can change hands.
        self.subject = f"{issuer}#{claims['sub']}"
        self.route_key = f"{method} {path[len(PREFIXES[issuer]):]}"
        # Only a verified address can be granted, or use a grant. Apple sends
        # email_verified as a string ("true"), Google as a boolean. Apple's
        # private relay addresses are verified too: each is the user's, for
        # this app.
        if str(claims.get("email_verified")).lower() != "true":
            raise ApiError(403, "Sign in with a verified email address")
        if not claims.get("email"):
            raise ApiError(403, "Sign in with an email address")
        self.email = _email(claims.get("email"))
        self.params = event.get("pathParameters") or {}
        self.query = event.get("queryStringParameters") or {}

    def route(self):
        route = self.route_key
        handlers = {
            "GET /profile": self.profile,
            "POST /keys/{owner}/{captureId}": self.content_key,
            "POST /profile/link-code": self.link_code,
            "POST /profile/link": self.link,
            "POST /profile/unlink": self.unlink,
            "POST /profile/credentials": self.profile_credentials,
            "GET /shares/{captureId}": self.grants,
            "PUT /shares/{captureId}": self.grant,
            "DELETE /shares/{captureId}": self.revoke,
            "GET /shared": self.shared,
            "DELETE /shared/{owner}/{captureId}": self.leave,
            "POST /shared/{owner}/{captureId}/credentials": self.credentials,
            "DELETE /account": self.delete_account,
            "PUT /links/{captureId}": self.publish_link,
        }
        if route not in handlers:
            raise ApiError(404, "No such route")
        return handlers[route]()

    def _body(self):
        return _body_of(self.event)

    # --- the caller's profile ----------------------------------------------

    def _profile(self):
        if self._profile_item is None:
            self._profile_item = self.profiles.of(self.subject, self.email, self.provider)
            # Every profile has its keys from its first request on.
            if self.keys is not None:
                try:
                    pkeys.keys_of(self.keys, self.kms, self._profile_item["id"])
                except Exception as e:  # made again at the next request
                    print(f"keys of {self._profile_item['id']}: {e}")
        return self._profile_item

    def _developer_token(self, profile):
        """A Cognito OpenID token for the profile's identity (made the first
        time), and that identity's ID, which is kept on the profile."""
        kwargs = {
            "IdentityPoolId": os.environ["IDENTITY_POOL_ID"],
            "Logins": {DEVELOPER: profile["id"]},
            "TokenDuration": 3600,
        }
        if profile.get("identityId"):
            kwargs["IdentityId"] = profile["identityId"]
        result = self.cognito.get_open_id_token_for_developer_identity(**kwargs)
        if profile.get("identityId") != result["IdentityId"]:
            profile["identityId"] = result["IdentityId"]
            self.store.save_profile(profile)
        return result

    def _me(self):
        """The profile's Cognito identity: its folder."""
        profile = self._profile()
        return profile.get("identityId") or self._developer_token(profile)["IdentityId"]

    def _emails(self):
        """The profile's verified addresses: every linked sign-in's."""
        return self.profiles.emails(self._profile()["id"]) or [self.email]

    def _public_key(self, profile):
        """The profile's public key (base64 DER, SubjectPublicKeyInfo), for
        its devices to wrap captures' keys with; None without keys."""
        if self.keys is None:
            return None
        return pkeys.keys_of(self.keys, self.kms, profile["id"])["publicKey"]

    def _view(self, profile):
        roles, global_roles = self.rbacr.union(self.profiles.emails(profile["id"]))
        public_key = self._public_key(profile)
        return {
            "profileId": profile["id"],
            **({"publicKey": public_key, "keyAlgorithm": pkeys.ALGORITHM}
               if public_key else {}),
            "accounts": self.profiles.accounts(profile, self.subject),
            "roles": roles,
            "globalRoles": global_roles,
            "premium": "premium" in roles,
        }

    def profile(self):
        return self._view(self._profile())

    def profile_credentials(self):
        profile = self._profile()
        result = self._developer_token(profile)
        return {"profileId": profile["id"], "identityId": result["IdentityId"],
                "token": result["Token"]}

    def link_code(self):
        profile = self._profile()
        self._me()  # the profile's identity, settled before anyone joins
        code, expires = self.store.make_code(profile["id"], self.subject)
        return {"code": code, "expiresAt": expires}

    def _folder_empty(self, identity):
        listing = self.s3.list_objects_v2(Bucket=os.environ["BUCKET"], Prefix=f"{identity}/", MaxKeys=1)
        return not listing.get("Contents")

    def link(self):
        code = self._body().get("code")
        target = self.store.peek_code(code)
        if target is None:
            raise ApiError(404, "That code is wrong, already used or expired")
        mine = self._profile()
        if target == mine["id"]:
            raise ApiError(409, "This account is in that profile already")
        owner = mine.get("ownerSubject") == self.subject
        if owner:
            # An owner brings nothing along: its profile must be alone and
            # empty, as nothing is moved between folders.
            others = [s for s in self.store.linked(mine["id"]) if s["subject"] != self.subject]
            if others:
                raise ApiError(409, "Other accounts are linked to this one: unlink them first")
            if mine.get("identityId") and not self._folder_empty(mine["identityId"]):
                raise ApiError(409, "This account has captures in the cloud of its own")
        if self.store.profile(target) is None or not self.store.take_code(code):
            raise ApiError(404, "That code is wrong, already used or expired")
        self.store.relink(self.subject, target, self.email, self.provider)
        if owner:
            self.store.delete_profile(mine["id"])
            if mine.get("identityId"):
                self.cognito.delete_identities(IdentityIdsToDelete=[mine["identityId"]])
        self._profile_item = self.store.profile(target)
        return self._view(self._profile_item)

    def unlink(self):
        account = self._body().get("id")
        profile = self._profile()
        for s in self.store.linked(profile["id"]):
            if prof.account_id(s["subject"]) == account:
                if s["subject"] == profile.get("ownerSubject"):
                    raise ApiError(409, "The profile's owner can't be unlinked")
                self.store.unlink(s["subject"])
                if s["subject"] == self.subject:
                    return {"unlinked": True}
                return self._view(profile)
        raise ApiError(404, "No such account in this profile")

    def _query(self, **kwargs):
        return query_all(self.table, **kwargs)

    def _grants_of(self, owner, capture_id):
        items = self._query(
            KeyConditionExpression="#c = :c",
            ExpressionAttributeNames={"#c": "capture"},
            ExpressionAttributeValues={":c": _key(owner, capture_id)},
        )
        return [
            {"email": i["email"], "role": i["role"], "grantedAt": int(i["grantedAt"])}
            for i in items
        ]

    def grants(self):
        capture_id = _id(self.params.get("captureId"))
        return {"grants": self._grants_of(self._me(), capture_id)}

    def grant(self):
        capture_id = _id(self.params.get("captureId"))
        body = self._body()
        email = _email(body.get("email"))
        role = body.get("role", "edit")
        if role not in ROLES:
            raise ApiError(400, "The role is edit or read")
        if email in self._emails():
            raise ApiError(400, "That's your own address")
        owner = self._me()
        grants = self._grants_of(owner, capture_id)
        if len(grants) >= MAX_GRANTS and email not in {g["email"] for g in grants}:
            raise ApiError(400, f"A capture can be shared with {MAX_GRANTS} people")
        self.table.put_item(
            Item={
                "capture": _key(owner, capture_id),
                "email": email,
                "owner": owner,
                "captureId": capture_id,
                "ownerEmail": self.email,
                "role": role,
                "grantedAt": int(time.time()),
            }
        )
        return {"grants": self._grants_of(owner, capture_id)}

    def revoke(self):
        capture_id = _id(self.params.get("captureId"))
        email = _email(self.query.get("email"))
        owner = self._me()
        self.table.delete_item(Key={"capture": _key(owner, capture_id), "email": email})
        return {"grants": self._grants_of(owner, capture_id)}

    def _shared_with_me(self):
        """The grants to any of the profile's addresses."""
        items = []
        for email in self._emails():
            items += self._query(
                IndexName="byEmail",
                KeyConditionExpression="#e = :e",
                ExpressionAttributeNames={"#e": "email"},
                ExpressionAttributeValues={":e": email},
            )
        return items

    def shared(self):
        items = self._shared_with_me()
        return {
            "shared": [
                {
                    "owner": i["owner"],
                    "captureId": i["captureId"],
                    "ownerEmail": i["ownerEmail"],
                    "role": i["role"],
                }
                for i in items
            ]
        }

    def _my_grant(self):
        """The grant of a capture to one of the profile's addresses (edit
        over read, if there are both)."""
        owner = _identity(self.params.get("owner"))
        capture_id = _id(self.params.get("captureId"))
        found = None
        for email in self._emails():
            item = self.table.get_item(
                Key={"capture": _key(owner, capture_id), "email": email}
            ).get("Item")
            if item is not None and (found is None or item["role"] == "edit"):
                found = item
        return owner, capture_id, found

    def leave(self):
        owner, capture_id = _identity(self.params.get("owner")), _id(self.params.get("captureId"))
        for email in self._emails():
            self.table.delete_item(
                Key={"capture": _key(owner, capture_id), "email": email}
            )
        return {}

    def credentials(self):
        owner, capture_id, item = self._my_grant()
        if item is None:
            raise ApiError(404, "Not shared with you")
        return folder_credentials(self.sts, owner, capture_id, item["role"])

    def content_key(self):
        """An encrypted capture's content key, for its owner's profile or
        someone it's shared with: unwrapped from what its event.json holds
        (read here, never taken from the caller). 404 for anyone else, and
        for a capture that isn't there or isn't encrypted."""
        owner = _identity(self.params.get("owner"))
        capture_id = _id(self.params.get("captureId"))
        if owner != self._me():
            _, _, grant = self._my_grant()
            if grant is None:
                raise ApiError(404, "Not shared with you")
        creds = folder_credentials(self.sts, owner, capture_id, "read")
        event = _read_event(self.clients, owner, capture_id, creds)
        key = None if event is None else _content_key_bytes(self.clients, owner, capture_id, event)
        if key is None:
            raise ApiError(404, "No key for that capture")
        return {"contentKey": base64.b64encode(key).decode(), "algorithm": "A256GCM"}

    def publish_link(self):
        """Lets anyone with the capture's link read it: the link's key (made
        by the app, in the link) is kept, by its SHA-256, for this capture
        of the caller's folder. Again with the same key does nothing new."""
        capture_id = _id(self.params.get("captureId"))
        digest = _link_key(self._body().get("key"))
        owner = self._me()
        item = self.links.get_item(Key={"keyHash": digest}).get("Item")
        if item is not None and (item["owner"], item["captureId"]) != (owner, capture_id):
            raise ApiError(409, "That key is another capture's")
        if item is None:
            self.links.put_item(Item={"keyHash": digest, "owner": owner,
                                      "captureId": capture_id,
                                      "createdAt": int(time.time())})
        return {"published": True}

    def delete_account(self):
        """Deletes the caller's profile: the grants of its captures, the
        grants to its addresses, its record in the cloud OCR service's
        accounts table, its linked sign-ins, and last its Cognito identity,
        so a retry after a failure still finds the same identity. Only its
        owner may; its folder's objects are the app's to delete (with the
        profile's credentials), before this."""
        profile = self._profile()
        if profile.get("ownerSubject") != self.subject:
            raise ApiError(409, "Only the profile's owner can delete it: unlink this account instead")
        apple_revoked = self._revoke_apple()
        owner = self._me()
        made = self._query(
            IndexName="byOwner",
            KeyConditionExpression="#o = :o",
            ExpressionAttributeNames={"#o": "owner"},
            ExpressionAttributeValues={":o": owner},
        )
        # The keys say whose a grant is: never delete anyone else's.
        made = [i for i in made if i["capture"].startswith(f"{owner}#")]
        emails = set(self._emails())
        to_me = [i for i in self._shared_with_me() if i["email"] in emails]
        for item in made + to_me:
            self.table.delete_item(
                Key={"capture": item["capture"], "email": item["email"]}
            )
        links = query_all(
            self.links,
            IndexName="byOwner",
            KeyConditionExpression="#o = :o",
            ExpressionAttributeNames={"#o": "owner"},
            ExpressionAttributeValues={":o": owner},
        )
        for item in links:
            if item["owner"] == owner:
                self.links.delete_item(Key={"keyHash": item["keyHash"]})
        if self.accounts is not None:
            self.accounts.delete_item(Key={"identityId": owner})
        result = self.cognito.delete_identities(IdentityIdsToDelete=[owner])
        if result.get("UnprocessedIdentityIds"):
            raise ApiError(502, "Couldn't delete your identity: try again")
        for s in self.store.linked(profile["id"]):
            self.store.unlink(s["subject"])
        self.store.delete_profile(profile["id"])
        return {"grantsMade": len(made), "grantsToMe": len(to_me), "links": len(links),
                "appleTokensRevoked": apple_revoked}

    def _revoke_apple(self):
        """Signed in with Apple: revokes the caller's Apple tokens with the
        authorization code the app just got from Apple (App Store guideline
        5.1.1(v)), before anything is deleted, so a refusal can be retried
        with a new code. True once revoked; False with nothing to revoke
        with (Google, no code, or no Sign in with Apple key set up yet)."""
        if self.provider != "apple":
            return False
        code = self._body().get("appleAuthorizationCode")
        if code is None:
            print("delete_account: no Apple authorization code, nothing revoked")
            return False
        if not isinstance(code, str) or not re.fullmatch(r"[A-Za-z0-9._-]{1,512}", code):
            raise ApiError(400, "That isn't an Apple authorization code")
        client_id = os.environ.get("APPLE_CLIENT_ID")
        load = self.clients.get("apple_key")
        key = load() if (client_id and load) else None
        if key is None:
            print("delete_account: no Sign in with Apple key set up, nothing revoked")
            return False
        try:
            apple_revoke.revoke(key, client_id, code, self.subject.split("#", 1)[1],
                                opener=self.clients.get("apple_open"))
        except apple_revoke.RevokeError as e:
            print(f"delete_account: revoking the Apple tokens failed: {e}")
            raise ApiError(502, f"{e}: try again") from e
        except OSError as e:
            print(f"delete_account: Apple didn't answer: {e}")
            raise ApiError(502, "Apple didn't answer: try again") from e
        return True
