# Contributions

Who sees which files of a shared capture, and how people add their own.
The case it's for: a teacher publishes a tab and its resources; students
upload videos and links, without seeing each other's; the teacher sees
them all and publishes the ones they like, which everyone then sees.

| Who | Sees | Adds |
|---|---|---|
| The **owner** (the [profile](profiles.md) that made the capture) | everything: the capture's own files and every contribution | to the capture itself; publishes contributions into it |
| Someone it's shared with to **edit** | the capture's own files (published ones included) | to the capture itself, as the owner does |
| Someone it's shared with to **read**, or who **joined by its link** signed in (a reader) | the capture's own files, and their own contribution | to their own contribution only |
| Someone holding its **link**, signed out | the capture's own files | nothing: Sign in first |

So a reader never sees another reader's files, and nobody but the owner
sees a contribution until the owner publishes it. Editors don't see
contributions either. A build has contributions only with
[sharing](shared-captures.md).

## Joining by the link

Someone signed in who opens a capture's link ([sharing](sharing.md#opening-a-link))
and finds it isn't theirs or shared with them **joins** it: the share API
(`POST /links/{captureId}/join`, with the link's key) gives them a read
grant of their own, the next sync pass brings the capture to their
library's **Shared with me**, and it opens. Signed out, the link opens the
capture read only with **Sign in**; once signed in, the same link joins it.
Joining again changes nothing; the owner, and someone shared with to edit,
keep what they have. If joining fails (an old share API, offline), the
link opens the capture by its link, read only, as before.

The app doesn't list who joined (there's no people sheet any more,
[shared captures](shared-captures.md)). Up to 500 people may join one
capture by its link.

## What a reader adds

On a capture shared with them to read, the [event screen](event-screen.md)
says "Shared by <email> · Can view and add". Add (scan, a document, photos
& videos, files, a link, with a [tab site](tab-site-links.md)'s PDF print),
dragging files onto it and [Cam](cam.md)'s takes go to the reader's
**contribution**, not the owner's capture. Below the
capture's files the list shows **Your files** ("Only you and <owner> see
these"), each with Delete (after a confirmation), playable in the list and
opening alone on the file screen (shown as it is: no Rename, Rotate or
saved view). A file the owner published also shows among the capture's
files, and as **Published** in Your files.

## What the owner sees and publishes

Below the capture's own files, the owner's event screen shows each
reader's contribution, **From <their email>** ("Only you see these until you
publish them"), each file with **Publish** (a publish icon: "Publish:
everyone sees it"). Publishing copies the file into the capture's own
files, as a new page with a file of its own whose `from` names the
contribution's page: it's then shown to everyone, synced with the capture, in its link
and its exports, and its row says **Published**, its button a check
("Published: tap to take it back"). Tapping again deletes the copy from
the capture; deleting it from the capture's list does the same. Either way
the reader's contribution keeps its own.

## How it's stored and synced

Each contribution has its own folder beside the capture's, in the owner's
folder of the user-data bucket:

| Object | Content |
|---|---|
| `<owner>/contrib/<capture id>/<reader's identity>/contrib.json` | `{updated, pages}`: the contribution's files and links, as a capture's `pages` are |
| `<owner>/contrib/<capture id>/<reader's identity>/<page id>.<extension>` | each file, written once |

Whose it is is the folder's name, never what `contrib.json` says.

- **Access**: the reader's [credentials](shared-captures.md#how-it-works)
  for a capture shared to read also get, put, delete and list their own
  contribution's folder, and nothing else under `contrib/`. The owner's
  own credentials reach their whole folder, so every contribution. A
  link's credentials, and an editor's, don't reach `contrib/` at all.
- **The reader's devices** sync their contribution after the capture,
  both ways, as events sync ([cloud sync](cloud-sync.md#when-and-how)):
  changed only here it goes up (the files its folder lacks, then
  `contrib.json`, then the files it no longer has are deleted), changed
  only there it comes down, changed in both the later `updated` wins. So
  it reaches the reader's other devices.
- **The owner's devices** list `<owner>/contrib/` once per pass, bring
  each contribution whose `contrib.json` changed and its files, and forget
  one whose folder is gone. The owner never writes them. Readers' email
  addresses come from the share API's grants, which record each reader's
  identity when they first get credentials (`GET /shares/{captureId}`
  returns it as `identity`, and `via: "link"` for those who joined).
- **On the device**, contributions are kept on the event
  (`contributions`, never in its cloud `event.json`), their files with the
  capture's. A contribution's page whose ID is one of the capture's, or of
  another contribution's, isn't taken (its file would be theirs), so a
  reader can't pass a file off as the owner's or as published.
- **Deleting an account** ([cloud sync](cloud-sync.md#deleting-the-account)):
  the share API deletes what the account contributed to others' captures
  (it knows where from the grants), before the grants themselves. What
  others contributed to the account's own captures is in its folder, which
  the app empties.

## Verified

- The share API's tests: a reader's credentials add their own
  contribution's folder (read and write) and list it, and no other
  reader's; the grant records their identity, kept through a role change;
  an editor's have no contribution. Signed-in people join by the link as
  readers, once; the owner and editors keep what they have; a wrong key
  joins nothing; joins are limited apart from email grants. Deleting an
  account deletes its contributions and no one else's.
- The app's tests, with three devices (a teacher, two students) over the
  in-memory bucket: a student's files go to their own folder, the
  capture's `event.json` unchanged; the other student's device never asks
  for anything of theirs; the teacher gets every contribution, named by
  email, files and all; publishing puts a copy (a new page, `from` the
  student's) in the capture's folder, which the other student then sees and
  the student sees as published, and taking it back leaves the student's
  own; a contribution whose page has the capture's page ID loses that page; a student's deletion reaches the teacher; a student's files
  reach their other devices; signed in, opening the link joins it, and the
  owner's own link joins nothing. On the event screen: the owner publishes
  and takes back a student's file; a reader sees Your files and deletes
  one; a reader's dropped files are theirs; signed in, a link joins the
  capture and opens it, and when joining fails it opens by its link.

## Known limitations

- The owner can't delete a reader's contribution, only remove the reader
  (who keeps it until they delete it; the owner still sees it).
- A reader who leaves the capture, or whom the owner removes, leaves
  their contribution in the owner's folder; the owner still sees it.
- Readers' files are read from S3 directly, not through CloudFront (a
  signed grant covers one folder: the capture's).
- Cam's play-along list shows the capture's files, not the reader's own
  takes.
