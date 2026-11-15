# Contributions

Who sees which files of a shared capture, and what people added of their
own before 2026-11-15. The case it was for: a teacher publishes a tab and
its resources; students upload videos and links, without seeing each
other's; the teacher sees them all and publishes the ones they like,
which everyone then sees.

**No new contributions are made.** Since 2026-11-15 only a capture's
owner changes it, and what someone it's shared with adds (Add, dropped
files, a tab site's print, Cam's takes) goes to **their own copy** of
the capture instead ([shared captures](shared-captures.md),
[copy on write](library.md#events)). The contributions made before
stay: the owner still sees and publishes them, and each reader still
sees and deletes their own. A reader's contribution also still keeps
their phrase passes on the shared capture.

| Who | Sees | Adds |
|---|---|---|
| The **owner** (the [profile](profiles.md) that made the capture) | everything: the capture's own files and every contribution | to the capture itself; publishes contributions into it |
| Someone it's shared with (by email, to read or, before, to edit), or who **joined by its link** signed in (a reader) | the capture's own files (published ones included), and their own contribution from before | to their own copy of the capture, never to it |
| Someone holding its **link**, signed out | the capture's own files | nothing: Sign in first |

So a reader never sees another reader's files, and nobody but the owner
sees a contribution until the owner publishes it. A build has contributions only with
[sharing](shared-captures.md).

## Joining by the link

Someone signed in who opens a capture's link ([sharing](sharing.md#opening-a-link))
and finds it isn't theirs or shared with them **joins** it: the share API
(`POST /links/{captureId}/join`, with the link's key) gives them a read
grant of their own, the next sync pass brings the capture to their
library's **Shared with me**, and it opens, read only. Signed out, the link opens the
capture read only with **Sign in**; once signed in, the same link joins it.
Joining again changes nothing; the owner, and someone shared with by
email, keep what they have. If joining fails (an old share API, offline), the
link opens the capture by its link, read only, as before.

The app doesn't list who joined (there's no people sheet any more,
[shared captures](shared-captures.md)). Up to 500 people may join one
capture by its link.

## What a reader added

On a capture shared with them, the [event screen](event-screen.md)
says "Shared by <email> · Read only · What you add goes to your copy".
Add, dragging files and [Cam](cam.md) go to the reader's own copy
([shared captures](shared-captures.md)). What their app added before
(Add, dropped files and Cam's takes went to their **contribution**, not
the owner's capture) shows below the
capture's files as **Your files** ("Only you and <owner> see
these"), each with Delete (after a confirmation, with **Don't ask again**,
[delete confirmations](delete-confirms.md)), playable in the list and
opening alone on the file screen (shown as it is: no Rename, Rotate or
saved view). A file the owner published also shows among the capture's
files, and as **Published** in Your files. The
[play-along sidebar](cam.md#playing-along-with-a-file) (in Cam, beside
the Text view, on the file screen) lists the reader's own files too,
after the capture's (not those published: the capture's copy is
listed), so they play along with their takes and
[delete them there](cam.md#deleting-from-the-sidebar).

## What the owner sees and publishes

Below the capture's own files, the owner's event screen shows each
reader's contribution, **From <their email>** ("Only you see these until you
publish them"), each file with **Publish** (a publish icon: "Publish:
everyone sees it"). Publishing copies the file into the capture's own
files, as a new page with a file of its own whose `from` names the
contribution's page: it's then shown to everyone, synced with the capture, in its link
and its exports, and its row says **Published**, its button a check
("Published: tap to take it back"). The copy brings the file's
[phrase passes](cam.md#phrase-passes) (the owner's own for it, else the
reader's), so Cam turns the tab along it as it did along the original.
Tapping again deletes the copy from
the capture, and its passes with it; deleting it from the capture's list does the same. Either way
the reader's contribution keeps its own.

## How it's stored and synced

Each contribution has its own folder beside the capture's, in the owner's
folder of the user-data bucket:

| Object | Content |
|---|---|
| `<owner>/contrib/<capture id>/<reader's identity>/contrib.json` | `{updated, pages}`: the contribution's files and links, as a capture's `pages` are |
| `<owner>/contrib/<capture id>/<reader's identity>/<page id>.<extension>` | each file, written once |

Whose it is is the folder's name, never what `contrib.json` says.

- **Access**: a grantee's [credentials](shared-captures.md#how-it-works)
  for a shared capture (read only) also get, put, delete and list their
  own contribution's folder, and nothing else under `contrib/`. The owner's
  own credentials reach their whole folder, so every contribution. A
  link's credentials don't reach `contrib/` at all.
- **The reader's devices** sync their contribution after the capture,
  both ways, as events sync ([cloud sync](cloud-sync.md#when-and-how)):
  changed only here it goes up (the files its folder lacks, then
  `contrib.json`, then the files it no longer has are deleted), changed
  only there it comes down, changed in both the later `updated` wins. So
  it reaches the reader's other devices.
- **The owner's devices** list `<owner>/contrib/` once per pass (only
  when one of their captures has a link key, recorded shares or
  contributions: no other can have any), bring
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
  reader's; the grant records their identity, kept through a role change.
  Signed-in people join by the link as
  readers, once; the owner and those shared with by email keep what they have; a wrong key
  joins nothing; joins are limited apart from email grants. Deleting an
  account deletes its contributions and no one else's.
- The app's tests, with three devices (a teacher, two students) over the
  in-memory bucket, the students' contributions made as an older app made
  them: a student's files go to their own folder, the
  capture's `event.json` unchanged; the other student's device never asks
  for anything of theirs; the teacher gets every contribution, named by
  email, files and all; publishing puts a copy (a new page, `from` the
  student's) in the capture's folder, which the other student then sees and
  the student sees as published, and taking it back leaves the student's
  own; a contribution whose page has the capture's page ID loses that page; a student's deletion reaches the teacher; a student's files
  reach their other devices; signed in, opening the link joins it, and the
  owner's own link joins nothing. On the event screen: the owner publishes
  and takes back a student's file; a reader sees Your files and deletes
  one (and Cam's sidebar lists and deletes their own take); signed in, a link joins the
  capture and opens it, and when joining fails it opens by its link.

## Known limitations

- The owner can't delete a reader's contribution, only remove the reader
  (who keeps it until they delete it; the owner still sees it).
- A reader who leaves the capture, or whom the owner removes, leaves
  their contribution in the owner's folder; the owner still sees it.
- Readers' files are read from S3 directly, not through CloudFront (a
  signed grant covers one folder: the capture's).
