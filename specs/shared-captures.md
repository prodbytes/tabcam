# Shared captures

A signed-in user can share any capture (event) of their own with other
people by **email address**, to **edit** (the default, "Can edit": they
change it as the owner does, and the owner sees their changes) or **read
only** (they see it, and get its updates, but can't change it). No email
is sent: someone sees what's shared with them when they sign in to TabScan
with that address. To share a capture with other people than the
original's, [clone](library.md#events) it and share the copy.

A build has sharing only with [sign-in and cloud sync](cloud-sync.md) and
`TABSCANNER_SHARE_API_URL` set.

## Sharing

The [event screen](event-screen.md)'s **Share with people** (people icon,
in the app bar of the user's own events while signed in) opens a sheet:

- what it does ("People you add find this capture when they sign in to
  TabScan with that email address. No email is sent.");
- **Email** and the role (**Can edit**, the default, or **Read only**),
  and **Add**, which checks the address looks like one ("Enter an email
  address"), grants it and syncs the capture, so it's in the cloud;
- the people it's shared with ("Not shared yet." when nobody), each with
  their role, to change, and **Remove** (×).

Addresses are compared in lower case. One's own address, and more than
50 people per capture, are refused, with the API's message.

## Shared with me

A capture shared with the user comes down at the next
[sync pass](cloud-sync.md#when-and-how) (within a minute) and shows in
the [library](library.md)'s **Shared with me** section, below the user's
own (**My captures**), with "shared by <their email>" on its card. Its
event screen says **"Shared by <email> · Can edit"** or **"· Read only"**
under the app bar.

- **Can edit**: everything works as for the user's own, except Share with
  people (only the owner shares). Changes go up to the owner's folder,
  and the owner's changes come down; the later one wins, as between one's
  own devices.
- **Read only**: Rename, Add, Filter, Rotate, Read tab, Delete (a page)
  and editing the text tab are off; Share (export) and Clone work. A clone
  is the user's own.
- **Remove** (a card's menu, instead of Delete, after a confirmation that
  the owner keeps it) takes it off the user's devices and leaves the
  share.
- A share the owner removed, or a capture the owner deleted, goes from
  the user's devices at the next pass. A role change applies at the next
  pass too.

Who shared it and the role are kept on the device only (`sharedBy`,
`readOnly`), never in the capture's cloud copy.

## How it works

The capture stays in its owner's folder,
`<owner identity>/events/<capture id>/`. The **share API**
([tabscan_api/shares/index.py](../tabscan_api/shares/index.py), Python
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

- Every request carries the user's Google ID token, checked by the HTTP
  API's JWT authorizer (issuer `https://accounts.google.com`, audience the
  web client). Only verified addresses (`email_verified`) are used. The
  owner's folder is their Cognito identity, found from the same token
  (`GetId`), so a user can only grant their own captures.
- Grants are in a DynamoDB table: key `<owner>#<capture id>` and the
  email, with the role, the owner's identity and email, and when; an index
  by email lists what's shared with someone.
- **Credentials**: the function assumes the `tabscan-share-access` role
  for an hour with a session policy that allows only
  `<bucket>/<owner>/events/<capture id>/*` (get; put and delete too to
  edit) and listing that prefix. The role itself allows at most the
  `events/` folders, and only the function may assume it.
- Inputs are checked: capture IDs `[a-z0-9]{1,32}`, owners
  `<region>:<uuid>`, emails, roles. The API is throttled (10 requests a
  second, bursts of 20).

In the app ([lib/cloud/share_api.dart](../tabscan_app/lib/cloud/share_api.dart)),
each sync pass, after the user's own folder: lists `GET /shared`, removes
the local copies of captures no longer listed, then syncs each listed
capture as a folder of one, with its credentials (reused until five
minutes before they expire, or the role changes): the same comparison as
for the user's own ([cloud sync](cloud-sync.md)), but read-only ones
never upload. A failing share is logged and skipped; the others go on.

## Infrastructure

[tabscan_infra/share-api.yaml](../tabscan_infra/share-api.yaml), stack
`tabscan-share-api`: the table, the function (its code uploaded by
`scripts/deploy-share-api.sh`), its role, the access role, the HTTP API
(CORS for the web app's origins) and its log group (30 days). An
administrator deploys it, after `tabscan-user-data` and
`tabscan-identity`: see [tabscan_infra/README.md](../tabscan_infra/README.md).
The script prints `TABSCANNER_SHARE_API_URL`.

## Verified

- The function's tests (`python3 -m unittest discover -s
  tabscan_api/shares`, with in-memory DynamoDB, Cognito and STS): a grant
  defaults to edit and is listed; read-only grants; bad emails, roles,
  IDs and one's own address are refused; unverified addresses are
  refused; the grantee lists, gets credentials narrowed to the capture's
  folder (read only: get only), and leaves; no grant, no credentials; the
  owner revokes.
- The app's tests, two devices and a fake share API over the in-memory
  bucket: a capture shared to edit comes down and edits go back (without
  the sharing fields); read only uploads nothing; the grantee's own
  events stay in their folder; revoked, it goes, and shared again it
  comes back; the grantee removes it and leaves; the owner deletes it and
  it goes; a role change reaches the copy; a clone of a shared capture is
  the user's own. The API client's requests.
- The template passes `validate-template`.
- Not yet verified: the deployed API, which needs the Google OAuth
  clients and the stacks.

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
