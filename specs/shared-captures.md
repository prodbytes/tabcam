# Shared captures

A capture (event) is shared with other people by its **link**: the
owner's [Share](sharing.md) copies it, and someone signed in who opens it
**joins** it, **read only**: they see the owner's files and get its
updates, and can't change them. **Only the owner changes a capture.**
What they add (Add, dropped files, Cam's takes) goes to **their own
copy** of it instead: a [clone](library.md#events), made the first time
(their newest copy after that), whose files stay the owner's until they
change (copy on write), and which opens in its place. There's no
sharing by email address in the app any more, nor a list of people: the
Share with people button and its sheet were removed (2026-10-17), so the
owner can't see, change or remove who has joined. Captures shared by
email before stay shared, read only, those shared **to edit** too
(2026-11-15: the app no longer uploads them, and the share API's
credentials no longer write). No email is sent: someone sees what's
shared with them when they sign in to tabs.cam (with Google, or with
Apple on iOS). To share a capture with other people than the original's,
[clone](library.md#events) it and share the copy's link (its files are
copied into it first).

A build has sharing only with [sign-in and cloud sync](cloud-sync.md) and
`TABCAM_SHARE_API_URL` set.

## The share API's grants

The share API still keeps who a capture is shared with (by email, to
read: a grant to edit is refused, and one made before reads as `read`;
one's own address and more than 50 people per capture refused; up to 500
more by its link), and `CloudSync` still has its client (`grants`,
`grant`, `revoke`), which only tests use now. The owner's app
recorded the people and roles on the event (`shares`: `[{email, role}]`,
`role` `edit` or `read`) when it listed or changed them, so they synced
with the capture ([event.json](cloud-sync.md#whats-synced-and-where));
the grants in the share API are what count.

## Shared with me

A capture shared with the user comes down at the next
[sync pass](cloud-sync.md#when-and-how) (within 5 minutes while the app is in front, at once on opening it) and shows in
the [library](library.md)'s **Shared with me** section, below the user's
own (**My captures**), with "shared by <their email>" on its card. Its
event screen says **"Shared by <email> · Read only · What you add goes to
your copy"** under the app bar.

- **Read only**, whatever the grant says: Rename, reordering, Rotate,
  Edit (a video), Delete (a file) and editing the text tab are the
  owner's, and their buttons aren't there at all, not greyed out (the
  view changes only what shows), nothing reads it here, and nothing of it
  goes up; Share (its link) and Clone work. The owner's changes come
  down.
- **Adding** (Add, dragging files, a tab site's print) adds to the user's
  own copy of it, and **Cam** opens on that copy
  ([event screen](event-screen.md)): their newest capture `clonedFrom`
  it, or a new clone, made then. The copy is the user's own, synced with
  their folder; its pages show the owner's files until they change, and
  get copies of their own before the owner's go (the capture deleted, a
  file deleted, the share removed or left; [copy on
  write](library.md#events)). Its phrase passes start from the user's
  own ones on the shared capture.
- **A link to a file's edit view** (`e=1`, [sharing](sharing.md)) opens
  the video editor on the user's copy too (made then, as Adding does),
  over the copy's page of that file, in the shared capture's place; when
  their copy has no page showing that file, the file opens on the shared
  capture, read only, as its plain link does. Only a video of the
  capture's own files does this: any other file opens as a file link.
- The user's own [contribution](contributions.md), from before adding
  went to their copy, still shows under **Your files**, with Delete; Cam's
  phrase passes on the shared capture are kept there.
- **Remove** (a card's menu, instead of Delete, after a confirmation that
  the owner keeps it, with **Don't ask again**, see
  [delete confirmations](delete-confirms.md)) takes it off the user's devices and leaves the
  share.
- A share the owner removed, or a capture the owner deleted, goes from
  the user's devices at the next pass (the user's copies keep the files
  they showed of it).

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
| `GET /shares/{captureId}` | the owner | the capture's grants, with each reader's `identity` once known and `via: "link"` for those who joined |
| `PUT /shares/{captureId}` | the owner | grants `{email, role}` (role `read`, the default; `edit` is refused: only the owner changes a capture) |
| `DELETE /shares/{captureId}?email=` | the owner | removes a grant |
| `GET /shared` | anyone | the captures shared with them: owner, capture, owner's email, role (always `read`, a grant made to edit before too) |
| `DELETE /shared/{owner}/{captureId}` | the grantee | leaves a share |
| `POST /shared/{owner}/{captureId}/credentials` | the grantee | temporary credentials for that capture's folder |
| `PUT /links/{captureId}` | the owner | records the capture's link key (`{key}`): anyone with the link may read it ([sharing](sharing.md)) |
| `POST /links/{captureId}/join` | anyone signed in | `{key}`: joins the capture the link opens, with a read grant of their own ([contributions](contributions.md#joining-by-the-link)); the owner's own link answers `own`, and an existing grant stays |
| `POST /public/{captureId}/credentials` | anyone, no token | `{key}`: read-only credentials for the capture's folder, and its owner; a wrong or unknown key is a 404 |
| `DELETE /account` | anyone | [deletes their account](cloud-sync.md#deleting-the-account): what they contributed to others' captures, the grants of their captures, the grants to their address, their record in the cloud OCR service's accounts table, then their Cognito identity. Under `/apple`, with `{appleAuthorizationCode}`, it first revokes their Sign in with Apple tokens ([below](cloud-sync.md#revoking-apples-tokens)) |

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
  addresses count as verified: each is the user's, for tabs.cam, and is
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
  `<bucket>/<owner>/events/<capture id>/*` (get: read only, for every
  grant, those made to edit before too) and listing that prefix; also
  get, put, delete and list the grantee's own contribution's folder,
  `<owner>/contrib/<capture id>/<their identity>/` (`contribPrefix`), and
  their grant records their identity. The role itself allows at most the
  `events/` and `contrib/` folders, and only the function may assume it.
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
minutes before they expire): the same comparison as for the user's own
([cloud sync](cloud-sync.md)), but never uploading: shared captures are
read only, whatever the grant's role. A failing share is logged and
skipped; the others go on.

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
  is to read and is listed; a grant to edit, bad emails, roles,
  IDs and one's own address are refused; a grant made to edit before
  lists as read and its credentials only read; unverified addresses are
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
  bucket: a capture shared to edit before is read only (her change
  uploads nothing, the owner's stays); read only uploads nothing; the
  grantee's own events stay in their folder; revoked, it goes, and shared
  again it comes back; the grantee removes it and leaves; the owner
  deletes it and it goes; a role change leaves it read only; a clone of a
  shared capture is the user's own, `clonedFrom` it. Adding to a shared
  capture adds to her own copy, made once (adding again goes to the same
  one), the shared capture unchanged; her folder gets the copy's
  `event.json` and her own file, not the owner's file, which her copy
  shows, on her other device too. The owner deletes the capture: her copy
  keeps a copy of the file, which goes up to her folder; she removes the
  shared capture: her copy keeps the file; a file of the copy replaced is
  its own, the owner's unchanged; before the copy gets a link its files
  become its own and go up. Cam on a shared capture opens on her copy,
  in its place. Files dropped on a shared capture go to her copy, which
  opens. The API client's requests. A capture's link with its
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
- A copy's page whose file never came to the user's device before the
  owner's went (deleted, or the share removed, before a download
  finished) can't be copied, and has no file. Each of the user's devices
  makes its own copy of a file that goes (the same file, at the same
  name: the last one up stays).
- People shared to edit before have no way left to change what they
  edited: they add to their own copy, like anyone the capture is shared
  with.
