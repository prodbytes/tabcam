"""TabScan's share API: who a capture is shared with, and credentials to it.

A capture (an event) lives in its owner's folder of the user-data bucket,
<owner identity>/events/<capture id>/. Its owner grants it to email
addresses, to edit (the default) or read only. Someone signed in with a
granted address lists what's shared with them, and gets temporary
credentials for just that capture's folder: get and list, plus put and
delete to edit. No email is sent.

Behind an HTTP API with JWT authorizers, so every request carries a
verified ID token: Google's (for the TabScan web client) at the routes
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
  DELETE /account                                 delete my profile (its owner)

Every route acts on the caller's profile alone: as an owner, on its
Cognito identity; as a grantee, on its verified addresses.
"""

import json
import os
import re
import time

import profiles as prof

ROLES = ("edit", "read")
MAX_GRANTS = int(os.environ.get("MAX_GRANTS", "50"))
ID = re.compile(r"^[a-z0-9]{1,32}$")
IDENTITY = re.compile(r"^[a-z]{2}(-[a-z]+)+-\d:[0-9a-f-]{36}$")
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
DEVELOPER = os.environ.get("DEVELOPER_PROVIDER", "login.tabscan.profiles")


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
    return {
        "table": dynamodb.Table(os.environ["TABLE"]),
        # The cloud OCR service's identity -> address table, if it's set up.
        "accounts": dynamodb.Table(accounts) if accounts else None,
        "cognito": boto3.client("cognito-identity", region_name=region),
        "sts": boto3.client("sts", region_name=region),
        "s3": boto3.client("s3", region_name=region),
        "store": prof.Store(
            dynamodb.Table(os.environ["PROFILES_TABLE"]),
            dynamodb.Table(os.environ["SUBJECTS_TABLE"]),
            dynamodb.Table(os.environ["LINK_CODES_TABLE"]),
        ),
        "rbacr": prof.Rbacr(),
    }


_cached = None


def handler(event, context, clients=None):
    global _cached
    if clients is None:
        _cached = _cached or _clients()
        clients = _cached
    try:
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


class Api:
    def __init__(self, event, clients):
        self.event = event
        self.table = clients["table"]
        self.cognito = clients["cognito"]
        self.sts = clients["sts"]
        self.accounts = clients.get("accounts")
        self.s3 = clients.get("s3")
        self.store = clients["store"]
        self.profiles = prof.Profiles(self.store)
        self.rbacr = clients["rbacr"]
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
        }
        if route not in handlers:
            raise ApiError(404, "No such route")
        return handlers[route]()

    def _body(self):
        try:
            body = json.loads(self.event.get("body") or "{}")
        except ValueError:
            raise ApiError(400, "The body isn't JSON")
        if not isinstance(body, dict):
            raise ApiError(400, "The body isn't a JSON object")
        return body

    # --- the caller's profile ----------------------------------------------

    def _profile(self):
        if self._profile_item is None:
            self._profile_item = self.profiles.of(self.subject, self.email, self.provider)
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

    def _view(self, profile):
        roles, global_roles = self.rbacr.union(self.profiles.emails(profile["id"]))
        return {
            "profileId": profile["id"],
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
        """Every item a query matches, page after page."""
        items = []
        while True:
            page = self.table.query(**kwargs)
            items += page["Items"]
            if "LastEvaluatedKey" not in page:
                return items
            kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]

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
        role = item["role"]
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
        result = self.sts.assume_role(
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
        if self.accounts is not None:
            self.accounts.delete_item(Key={"identityId": owner})
        result = self.cognito.delete_identities(IdentityIdsToDelete=[owner])
        if result.get("UnprocessedIdentityIds"):
            raise ApiError(502, "Couldn't delete your identity: try again")
        for s in self.store.linked(profile["id"]):
            self.store.unlink(s["subject"])
        self.store.delete_profile(profile["id"])
        return {"grantsMade": len(made), "grantsToMe": len(to_me)}
