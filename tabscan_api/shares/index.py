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

Routes (each also under /apple, for Apple's tokens):
  GET    /shares/{captureId}                      the capture's grants (owner)
  PUT    /shares/{captureId}                      grant {email, role} (owner)
  DELETE /shares/{captureId}?email=               revoke (owner)
  GET    /shared                                  what's shared with me
  DELETE /shared/{owner}/{captureId}              leave a share
  POST   /shared/{owner}/{captureId}/credentials  credentials for it
"""

import json
import os
import re
import time

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


class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status
        self.message = message


def _clients():
    import boto3

    region = os.environ.get("AWS_REGION", "us-east-1")
    return {
        "table": boto3.resource("dynamodb", region_name=region).Table(
            os.environ["TABLE"]
        ),
        "cognito": boto3.client("cognito-identity", region_name=region),
        "sts": boto3.client("sts", region_name=region),
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
            "GET /shares/{captureId}": self.grants,
            "PUT /shares/{captureId}": self.grant,
            "DELETE /shares/{captureId}": self.revoke,
            "GET /shared": self.shared,
            "DELETE /shared/{owner}/{captureId}": self.leave,
            "POST /shared/{owner}/{captureId}/credentials": self.credentials,
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

    def _me(self):
        """The caller's Cognito identity: their own folder."""
        header = (self.event.get("headers") or {}).get("authorization", "")
        token = header[7:] if header.lower().startswith("bearer ") else ""
        result = self.cognito.get_id(
            IdentityPoolId=os.environ["IDENTITY_POOL_ID"],
            Logins={self.login: token},
        )
        return result["IdentityId"]

    def _grants_of(self, owner, capture_id):
        items = self.table.query(
            KeyConditionExpression="#c = :c",
            ExpressionAttributeNames={"#c": "capture"},
            ExpressionAttributeValues={":c": _key(owner, capture_id)},
        )["Items"]
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
        if email == self.email:
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

    def shared(self):
        items = self.table.query(
            IndexName="byEmail",
            KeyConditionExpression="#e = :e",
            ExpressionAttributeNames={"#e": "email"},
            ExpressionAttributeValues={":e": self.email},
        )["Items"]
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
        owner = _identity(self.params.get("owner"))
        capture_id = _id(self.params.get("captureId"))
        item = self.table.get_item(
            Key={"capture": _key(owner, capture_id), "email": self.email}
        ).get("Item")
        return owner, capture_id, item

    def leave(self):
        owner, capture_id, _ = self._my_grant()
        self.table.delete_item(
            Key={"capture": _key(owner, capture_id), "email": self.email}
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
