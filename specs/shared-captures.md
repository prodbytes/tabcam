# Shared captures

A signed-in user can share any capture (event) of their own with other
people by **email address**, to **edit** (the default, "Can edit": they
change it as the owner does, and the owner sees their changes) or **read
only** (they see it, and get its updates, but can't change it). No email
is sent: someone sees what's shared with them when they sign in to TabCam
with that address (with Google, or with Apple on iOS). To share a capture with other people than the
original's, [clone](library.md#events) it and share the copy.

A build has sharing only with [sign-in and cloud sync](cloud-sync.md) and
`TABCAM_SHARE_API_URL` set.

## Sharing

**Share with people**, a button of its own in the capture's app bar for
the user's own events (signed in first, in a build with sharing), opens a
sheet:

- what it does ("People you add find this capture when they sign in to
  TabCam with that email address. No email is sent.");
- **Email** and the role (**Can edit**, the default, or **Read only**),
  and **Add**, which checks the address looks like one ("Enter an email
  address"), grants it and syncs the capture, so it's in the cloud;
- the people it's shared with ("Not shared yet." when nobody), each with
  their role, to change, and **Remove** (×).

Addresses are compared in lower case. One's own address, and more than
50 people per capture, are refused, with the API's message.

The owner's app records the people and roles on the event (`shares`:
`[{email, role}]`, `role` `edit` or `read`) each time it lists, adds,
changes or removes them, so they sync with the capture
([event.json](cloud-sync.md#whats-synced-and-where)). The grants in the
share API are what count: `shares` only says who they were when last
recorded (and an editor could change it in their copy).

## Shared with me

A capture shared with the user comes down at the next
[sync pass](cloud-sync.md#when-and-how) (within seconds while the app is in front) and shows in
the [library](library.md)'s **Shared with me** section, below the user's
own (**My captures**), with "shared by <their email>" on its card. Its
event screen says **"Shared by <email> · Can edit"** or **"· Read only"**
under the app bar.

- **Can edit**: everything works as for the user's own, except Share with
  people (only the owner shares). Changes go up to the owner's folder,
  and the owner's changes come down; the later one wins, as between one's
  own devices.
- **Read only**: Rename, Add, Rotate, Delete (a page) and editing the
  text tab are off (the view changes only what shows), and nothing
  reads it here; Share (export) and Clone work. A clone
  is the user's own.
- **Remove** (a card's menu, instead of Delete, after a confirmation that
  the owner keeps it) takes it off the user's devices and leaves the
  share.
- A share the owner removed, or a capture the owner deleted, goes from
  the user's devices at the next pass. A role change applies at the next
  pass too.

If the owner [hid its images](hidden-images.md), it shows that way for
the user too, who can't show them.

Who shared it and the role are kept on the device only (`sharedBy`,
`readOnly`), never in the capture's cloud copy.

## How it works

The capture stays in its owner's folder,
`<owner identity>/events/<capture id>/`, its owner's
[profile](profiles.md)'s: the owner is the profile, and a grant to any of
the profile's addresses reaches every account linked to it. The same API
keeps the profiles (`/profile` routes, [profiles](profiles.md#api)). The **share API**
([tabcam_api/shares/index.py](../tabcam_api/shares/index.py), Python
3.13 on Lambda) behind an HTTP API keeps the grants and hands out
credentials:

| Route | Who | Does |
|---|---|---|
| `GET /shares/{captureId}` | the owner | the capture's grants |
| `PUT /shares/{captureId}` | the owner | grants `{email, role}` (role `edit` by default, or `read`) |
| `DELETE /shares/{captureId}?email=` | the owner | removes a grant |
| `GET /shared` | anyone | the captures shared with them: owner, capture, owner's email, role |
| `DELETE /shared/{owner}/{captureId}` | the grantee | leaves a share |
| `POST /shared/{owner}/{captureId}/credentials` | the grantee | temporary credentials for that capture's folder |
| `PUT /links/{captureId}` | the owner | records the capture's link key (`{key}`): anyone with the link may read it ([sharing](sharing.md)) |
| `POST /public/{captureId}/credentials` | anyone, no token | `{key}`: read-only credentials for the capture's folder, and its owner; a wrong or unknown key is a 404 |
| `DELETE /account` | anyone | [deletes their account](cloud-sync.md#deleting-the-account): the grants of their captures, the grants to their address, their record in the cloud OCR service's accounts table, then their Cognito identity |

Each route is also under `/apple` (`GET /apple/shared`, …,
`DELETE /apple/account`), for Sign in with Apple's tokens, except
`POST /public/…`, which has no authorizer: the function answers it before
reading any token, with nothing but the key to go on.

- Every request carries the user's ID token, checked by the HTTP API's
  JWT authorizers. An HTTP API route has one authorizer, and a JWT
  authorizer one issuer, so each provider has its own paths:
  - **Google's** at the routes above: the `google` authorizer, issuer
    `https://accounts.google.com`, audience the web client, and the local
    web client where it's set (though the main pool then refuses local
    tokens: no sharing in local web builds);
  - **Apple's** under `/apple`, only when the stack has `AppleClientId`:
    the `apple` authorizer, issuer `https://appleid.apple.com`, audience
    the bundle ID `com.nu01.tabcam`. The app sends an Apple token there
    (it reads the token's issuer).

  The function checks the token's issuer (`iss`) is its path's, or answers
  401, so a token is never taken as another provider's, then routes both
  paths alike. Only verified addresses are used: `email_verified` must be
  true (Apple sends it as the string `"true"`, Google as a boolean), and a
  token without an email is refused (403). Apple's private relay
  addresses count as verified: each is the user's, for TabCam, and is
  what others share with. The owner's folder is their Cognito identity,
  found from the same token (`GetId`, with the token under its issuer's
  `Logins` key: `accounts.google.com` or `appleid.apple.com`), so a user
  can only grant their own captures. A Google and an Apple sign-in are two
  identities: captures shared from one are owned by that one's folder,
  but a grant to an address reaches whoever signs in with it, either way.
  Every route acts on the caller alone: as an owner, on that identity; as
  a grantee, on their verified address. `DELETE /account` deletes only
  grants whose key starts with the caller's identity, or whose email is
  theirs, and the identity last, so a retry after a failure finds the
  same one (Cognito keeping it is a 502, to retry).
- Grants are in a DynamoDB table: key `<owner>#<capture id>` and the
  email, with the role, the owner's identity and email, and when; an index
  by email lists what's shared with someone, and one by owner (keys only)
  the grants someone made, for deleting their account. Queries follow
  every page.
- **Credentials**: the function assumes the `tabcam-share-access` role
  for an hour with a session policy that allows only
  `<bucket>/<owner>/events/<capture id>/*` (get; put and delete too to
  edit) and listing that prefix. The role itself allows at most the
  `events/` folders, and only the function may assume it.
- **Links**: the links table keeps each key's SHA-256 (never the key),
  with the owner's identity and the capture ID; one key is one capture's
  (another's is a 409). A link's credentials are those of a read-only
  grant (get and list that capture's folder), for an hour. The public
  route is throttled harder (5 requests a second, bursts of 10); keys are
  192 random bits, so guessing one is hopeless anyway. `DELETE /account`
  deletes the caller's links too (an index by owner).
- Inputs are checked: capture IDs `[a-z0-9]{1,32}`, owners
  `<region>:<uuid>`, emails, roles, link keys (`[A-Za-z0-9_-]{32,64}`). The API is throttled (10 requests a
  second, bursts of 20).

In the app ([lib/cloud/share_api.dart](../tabcam_app/lib/cloud/share_api.dart)),
each sync pass, after the user's own folder: lists `GET /shared`, removes
the local copies of captures no longer listed, then syncs each listed
capture as a folder of one, with its credentials (reused until five
minutes before they expire, or the role changes): the same comparison as
for the user's own ([cloud sync](cloud-sync.md)), but read-only ones
never upload. A failing share is logged and skipped; the others go on.

## Infrastructure

[tabcam_infra/share-api.yaml](../tabcam_infra/share-api.yaml), stack
`tabcam-share-api`: the table, the function (its code uploaded by
`scripts/deploy-share-api.sh`), its role, the access role, the HTTP API
(CORS for the web app's origins) and its log group (30 days). An
administrator deploys it, after `tabcam-user-data` and
`tabcam-identity`: see [tabcam_infra/README.md](../tabcam_infra/README.md).
The function may get, put, delete and query grants, call `GetId` and
`DeleteIdentities` on the identity pool, and, when the `tabcam-ocr`
stack is deployed (the script finds its `AccountsTable`, the
`AccountsTableName` parameter), delete items of the accounts table.
The script prints `TABCAM_SHARE_API_URL`.

## Verified

- The function's tests (`python3 -m unittest discover -s
  tabcam_api/shares`, with in-memory DynamoDB, Cognito and STS): a grant
  defaults to edit and is listed; read-only grants; bad emails, roles,
  IDs and one's own address are refused; unverified addresses are
  refused; the grantee lists, gets credentials narrowed to the capture's
  folder (read only: get only), and leaves; no grant, no credentials; the
  owner revokes. `DELETE /account` deletes the caller's grants both ways,
  their accounts record, their links and their identity, and nothing of anyone else's
  (another owner's grant to a third person stays), across query pages;
  without the OCR table too; Cognito keeping the identity is a 502 and a
  retry finishes; an unverified address deletes nothing; an Apple user
  deletes theirs under `/apple`. With made-up Apple claims: the `/apple`
  routes take Apple's tokens and use their own identity
  (`appleid.apple.com`); an Apple user gets what's shared with their
  (relay) address; Apple's `email_verified` may be a boolean or a string,
  and false is refused; a token on another issuer's path is refused before
  anything is read; an Apple token without an email is refused; unknown
  `/apple` routes are 404. Links: a published key opens read-only
  credentials (get only, that capture's folder) without a token, and only
  its hash is kept; publishing again is the same; a wrong key, another
  capture's ID, a bad key or body open nothing; a key is one capture's.
- The app's tests, two devices and a fake share API over the in-memory
  bucket: a capture shared to edit comes down and edits go back (without
  the sharing fields); read only uploads nothing; the grantee's own
  events stay in their folder; revoked, it goes, and shared again it
  comes back; the grantee removes it and leaves; the owner deletes it and
  it goes; a role change reaches the copy; a clone of a shared capture is
  the user's own. The API client's requests. A capture's link with its
  key opens it read only, signed out (instead of the welcome) and signed
  in when it isn't shared with the user, in a library apart; a wrong key
  says it can't be opened; Share makes the key once, on the tap, and a
  link the API couldn't record is recorded at the next pass.
- The template passes `validate-template` and cfn-lint (the `/apple`
  routes and authorizer only with `AppleClientId`).
- Not yet verified: the deployed API, which needs the Google OAuth
  clients and the stacks (and, for Apple, the stack with `AppleClientId`).

## Known limitations

- Credentials are asked for each shared capture, one request per capture
  per pass (reused for an hour).
- An owner deleting a capture doesn't remove its grants at once: each
  grantee's next pass finds the tombstone and leaves.
- Two capture IDs can only clash between users if made in the same
  microsecond; a shared capture whose ID is one of the user's own is
  skipped.
- People only find what's shared with them in the app; there's no email
  or notification.
- A capture's link can't be revoked or changed yet: whoever has a link
  with its key can see the capture, read only, until the capture is
  deleted (or its owner deletes their account). A clone has no key, so
  cloning gives a capture with a new link.
