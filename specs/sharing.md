# Sharing

**Share** (the event screen's app bar, a link icon, or a library card's
menu; the file screen's app bar and the video editor's too, for the
file's link) copies the capture's link to the clipboard, nothing else: no
choice of format, no text around it, the URL alone. Signed in (or in a
build without sign-in) it copies on the tap itself, before anything else
(browsers let a page write the clipboard only right after a tap; the sync
pass comes after); "Link copied" says it's done. Signed out, it asks to
sign in first ([signed out](cloud-sync.md#signed-out)), then copies.

- A file's link adds `f=<file id>` (`CaptureLink.of(event, file:)`,
  the [file names](event-screen.md) in the list): it opens the capture
  with that file open on the file screen over its list (Back goes to the
  list), signed in, signed out by its key, or after joining; an unknown
  or bad file ID opens just the capture. **Share on the file screen** (a
  link icon in its app bar, for the capture's own files) copies it.
  **Share in the video editor** (a link icon before About) copies the
  file's **edit view's link**, `e=1` too (`CaptureLink.of(event, file:,
  edit: true)`; only with a file, `CaptureLink.editIn`): it opens the
  editor over the file, the context it was shared from. On a capture
  shared with the user (read only: the editor doesn't open on it), the
  editor opens on their **copy** of it, made then if they have none, on
  the copy's page of that file (copy on write: the page shows the
  owner's file until it changes;
  [shared captures](shared-captures.md#shared-with-me)), in the shared
  capture's place, with "The editor opens on your copy, …"; a copy that
  has no page showing that file (it owns its files since it was shared,
  or the file came after it), or one that can't be made, opens the file
  on the shared capture instead, read only, as its plain link does. Opened by its
  key, signed out or not shared with the user, the file opens, read only
  (there's no copy to edit); once signed in and joined, the same link
  opens the editor on their copy. An image's edit view is just the file.
  A reload or restart comes back to the editor too
  ([navigation](navigation.md#coming-back-where-the-user-was)).
- The link is a **short link**, `https://tabs.cam/s/<key>`
  ([`CaptureLink`](../tabcam_app/lib/export/capture_link.dart)), a file's
  `https://tabs.cam/s/<key>?f=<file id>` (its edit view's `&e=1` too):
  the capture's **link key**
  alone, which lets anyone holding the link see the capture, read only
  ([opening a link](#opening-a-link)). The site answers it with a
  redirect to the **full link**, `https://tabs.cam/app/?c=<capture
  id>&k=<key>` ([short links](#short-links)). On the web it's to the
  site the app runs on (rc.tabs.cam on the RC's); in the phone apps, to
  production's, or the RC's for RC builds. A site that doesn't answer
  short links (a local build's) copies the full link instead.
- The key is made the first time the owner copies the link: 12 random
  letters and digits (about 71 bits; base62), kept on the capture
  (`linkKey`, synced, so every device of theirs copies the same link) and
  recorded by the share API (`PUT /links/{captureId}`, after the copy);
  if that fails (offline), each sync pass tries again. A key from before
  short links (32 base64url characters) is replaced by a short one the
  next time the owner copies the link; links with the old key keep
  working (the share API keeps every key it was given). Someone it's
  shared with copies the owner's link, key and all, once it has one (with
  an old key, `/s/<old key>`); without a key yet, or in a build without
  the share API, the link is the full one with `?c=<capture id>` alone,
  which opens it only for its owner and the people it's shared with.
  Copying it starts a sync pass, so the capture is in the cloud.
- It's the only way to share: there's no Share with people any more
  ([shared captures](shared-captures.md)).
- There's no PDF, text or zip export any more.

Files are named from the title and artist (`My riff - Me.pdf`,
`My riff - Me 1.png`, `My riff - Me 2.mov`), keeping only letters, digits, spaces, `.`, `_` and
`-`; `tab` if nothing is left. The subject is the event's title.

## Short links

`https://<site>/s/<key>` (any link key, short or old) goes, through the
site's CloudFront (a `/s/*` behavior, on when the site is deployed with
the share API's domain, as [previews](#link-previews) are), to the share
API (`GET /s/{key}`, and `HEAD`; no sign-in;
[index.py](../tabcam_api/shares/index.py)). The links table is keyed by
the key's hash, so the key alone finds the capture: the answer is a 302
to `/app/?c=<capture id>&k=<key>` (`&f=<file id>`, and `&e=1` with it,
kept when well formed) on the same site, which the app opens as below;
an unknown or
malformed key goes to `/app/`. CloudFront keeps the answer, by path,
`f` and `e`: a day for a link (it never changes; a deleted capture says so in
the app), a minute for an unknown one. Guessing keys gets 10 tries a
second for everyone, and 2⁷¹ keys.

In the browser the redirect brings the web app the full link itself. On
Android the app is handed the short link ([App Links](#android-app-links)):
`IncomingLinks` asks the site for it without following the redirect
(`CaptureLink.resolve`; the stage's site when Android hands only the
path) and opens the full link it names; offline, or for an unknown link,
nothing opens.

## Opening a link

The web app opened with `?c=<capture id>`, or the Android app opened by
the link ([App Links](#android-app-links)), opens that capture's event
screen, found by its ID among the events on the device: the user's own and
those [shared with them](shared-captures.md). If it isn't there yet:

- signed out, a link with its key opens the capture **by its link**
  (below), instead of the [welcome](navigation.md#signed-out-the-welcome);
  one without a key shows the welcome, and the capture opens once signing
  in has synced it;
- signed in, it waits for a sync pass (starting one if none is running);
  if the pass doesn't bring it, a link with its key **joins** it
  ([contributions](contributions.md#joining-by-the-link)): it's shared with
  the user to read from then on, and opens once the next pass brings it;
  if joining fails, it opens by its link, over Home (Back returns). One
  without a key says the capture isn't shared with the user and to ask its
  owner to share it with their email address;
- in a build without cloud sync, it says the capture isn't on this
  device.

On the web, once the capture opens in the user's own library, the
address keeps where they are instead of the link: `?open=<capture id>`,
without the key, which doesn't come back (not even with the browser's
Back) ([navigation](navigation.md#coming-back-where-the-user-was)).
Opened by its link (read only), the link stays in the address, so a
reload opens it again.

**By its link** ([PublicCaptureScreen](../tabcam_app/lib/screens/public_capture_screen.dart),
[PublicCaptures](../tabcam_app/lib/cloud/public_capture.dart)): the app
asks the share API, without signing in, for read-only credentials to the
capture's folder (`POST /public/{captureId}/credentials` with the key),
then downloads its `event.json` and files (a video's [kept
download](video-edit.md#the-kept-download) too, which plays in its
place; one not in the folder yet is left out, and the capture opens all
the same) into a library of its own, in memory, apart from the user's, and gone with the screen; its settings
too (the count-in, the sidebars' widths…), so on the web they neither
read nor change the device's, which the user's library keeps in
localStorage ([library](library.md#device-settings)). While it
shows, it reads the capture's `event.json` again every 5 minutes while
the app is in front (not while it's behind, a hidden tab say) and when
it comes back to the front: when it changed (a rename, a file added,
removed or moved, the text tab), the screen shows the change, so the
owner's edits reach whoever has the link open within 5 minutes, or on
coming back to it. A failed look (offline) keeps what shows; a link gone
for good (a wrong key, the capture deleted) stops looking. It shows
"Opening the capture…" meanwhile, then the event screen, read only, with
a banner "Opened by its link · Read only": no Rename, Add, Reorder,
editing or Clone (it isn't in the user's library);
Share copies the same link. Signed out, the app bar ends with the
[one-click sign-in](navigation.md#the-one-click-sign-in-top-right) (on
the capture, on a file opened over it, and while it opens or fails),
which signs in right there; and the banner (and the screen when it
fails) has **Sign in**, which goes to the welcome, with every way in.
Either way the link stays waiting, so once signed in Home opens it (the
user's, shared with them, or by its link again). A wrong key, a deleted capture, one not in the
cloud yet, or no connection: "This capture can't be opened…", with **Try
again**.

So the link is what gives access: whoever holds a link with its key can
see the capture's own files (never change them, nor see what people
[contributed](contributions.md) until the owner publishes it); signed in,
it also lets them add files of their own. Edit access is only for the
people the owner shared it with by email before that was removed
([shared captures](shared-captures.md)).

## Link previews

Chat apps (WhatsApp, iMessage, Slack, Telegram, Discord, Teams, X,
LinkedIn, Facebook...) preview a link by fetching it with their own
crawler, which reads the page's Open Graph tags and never runs the app.
So a capture's link previews as the capture, not as "tabs.cam":

- The site's CloudFront function ([site.yaml](../tabcam_infra/site.yaml))
  sends a known crawler (by its user agent) asking for
  `/app/?c=<id>&k=<key>` (ID and key well formed) to
  `/preview/<id>/<key>` (a 302). People always get the app; so does any
  other request. A short link gets there too: its redirect to the full
  link, then this one.
- `/preview/*` comes from the share API (`GET /preview/{captureId}/{key}`,
  no sign-in; [index.py](../tabcam_api/shares/index.py)), cached by
  CloudFront for 5 minutes. For a key that opens the capture, it reads
  its `event.json` with the link's own read-only credentials and answers
  a small page: the title ("<title> – <artist>"), a description of what
  it holds ("<artist> · 2 pages, 1 PDF, 1 link, a text tab. Shared with
  tabs.cam."; images left out when hidden), the short link as `og:url`
  and the app's icon as the image. A wrong key, a deleted capture or a
  malformed link: tabs.cam's own title and description. Someone who lands
  on the page goes on to the app (a script; crawlers don't run it).
- The site names itself to the API (`x-tabcam-site`, the RC's or
  production's), so the preview links back to the same site. It's on when
  the site is deployed with the share API's domain (`ShareApiDomain`,
  from `TABCAM_SHARE_API_URL`; [deploy](deploy.md)).

A rename shows in new previews within 5 minutes (chat apps keep their
own copy of a preview already shown).

## Android App Links

On Android, `https://tabs.cam/s/…` and `https://tabs.cam/app…`, the
RC's (`rc.tabs.cam`) and the old names' (`tabcam.nu01.com`,
`rc.tabcam.nu01.com`) open in the tabs.cam app instead of the browser
(an `autoVerify` intent filter; every web app address, not only capture
links: without `?c=` the app just opens). A short link is resolved
first ([short links](#short-links)). A link that
launches the app, or reaches it while it runs, goes to `IncomingLinks`
([lib/export/incoming_links.dart](../tabcam_app/lib/export/incoming_links.dart)),
a binding observer added before `runApp`, so the Navigator never takes
the link for a named route; Home then opens the capture as above. The
app's initial route is always `/`.

Android opens them in the app only when the site vouches for the app's
signing key: `https://<site>/.well-known/assetlinks.json` (from
[tabcam_index/site/.well-known/](../tabcam_index/site/.well-known/assetlinks.json),
uploaded by every deploy, both sites) lists the SHA-256 fingerprints of
the keys allowed. It lists the maintainer's debug key (builds without the
upload key) and the upload key, which signs release builds: those
installed with `scripts/android-install.sh` and the Release workflow's.
Google Play's app signing key is to be added once the app is on Play
([app stores](app-stores.md#android-signing)); until then, Play's builds
open the links in the browser.
