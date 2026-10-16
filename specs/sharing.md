# Sharing

**Share** (the event screen's app bar, a link icon, or a library card's
menu) copies the capture's link to the clipboard, nothing else: no
choice of format, no text around it, the URL alone. Signed in (or in a
build without sign-in) it copies on the tap itself, before anything else
(browsers let a page write the clipboard only right after a tap; the sync
pass comes after); "Link copied" says it's done. Signed out, it asks to
sign in first ([signed out](cloud-sync.md#signed-out)), then copies.

- The link is `https://tabcam.nu01.com/app/?c=<capture id>&k=<key>`
  ([`CaptureLink`](../tabcam_app/lib/export/capture_link.dart)): the
  capture's ID, and its **link key**, which lets anyone holding the link
  see the capture, read only ([opening a link](#opening-a-link)). On the
  web it's to the site the app runs on (the RC's, or a local one); in the
  phone apps, to production's, or the RC's for RC builds.
- The key is made the first time the owner copies the link (192 random
  bits, base64url, 32 characters), kept on the capture (`linkKey`, synced,
  so every device of theirs copies the same link) and recorded by the
  share API (`PUT /links/{captureId}`, after the copy); if that fails
  (offline), each sync pass tries again. Someone it's shared with copies
  the owner's link, key and all, once it has one; without a key yet, or in
  a build without the share API, the link is `?c=<capture id>` alone,
  which opens it only for its owner and the people it's shared with.
  Copying it starts a sync pass, so the capture is in the cloud.
- **Share with people** has its own button beside it (people with a
  plus), on the user's own captures in a build with sharing: it opens the
  [people sheet](shared-captures.md#sharing).
- There's no PDF, text or zip export any more.

Files are named from the title and artist (`My riff - Me.pdf`,
`My riff - Me 1.png`, `My riff - Me 2.mov`), keeping only letters, digits, spaces, `.`, `_` and
`-`; `tab` if nothing is left. The subject is the event's title.

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
  if the pass doesn't bring it, a link with its key opens it by its link,
  over Home (Back returns); one without says the capture isn't shared with
  the user and to ask its owner to share it with their email address;
- in a build without cloud sync, it says the capture isn't on this
  device.

**By its link** ([PublicCaptureScreen](../tabcam_app/lib/screens/public_capture_screen.dart),
[PublicCaptures](../tabcam_app/lib/cloud/public_capture.dart)): the app
asks the share API, without signing in, for read-only credentials to the
capture's folder (`POST /public/{captureId}/credentials` with the key),
then downloads its `event.json` and files into a library of its own, in
memory, apart from the user's, and gone with the screen. While it
shows, it reads the capture's `event.json` again every 10 seconds and
when the app comes back to the front: when it changed (a rename, a file
added, removed or moved, the text tab), the screen shows the change, so
the owner's edits reach whoever has the link open within seconds. A
failed look (offline) keeps what shows. It shows
"Opening the capture…" meanwhile, then the event screen, read only, with
a banner "Opened by its link · Read only": no Rename, Add, Reorder,
editing or Clone (it isn't in the user's library), no Share with people;
Share copies the same link. Signed out, the banner (and the screen when
it fails) has **Sign in**, which goes to the welcome; the link stays
waiting, so once signed in Home opens it (the user's, shared with them,
or by its link again). A wrong key, a deleted capture, one not in the
cloud yet, or no connection: "This capture can't be opened…", with **Try
again**.

So the link is what gives access: whoever holds a link with its key can
see the capture (never change it). Edit access is still only for the
people the owner shares it with ([Share with people](shared-captures.md)).

## Link previews

Chat apps (WhatsApp, iMessage, Slack, Telegram, Discord, Teams, X,
LinkedIn, Facebook...) preview a link by fetching it with their own
crawler, which reads the page's Open Graph tags and never runs the app.
So a capture's link previews as the capture, not as "TabCam":

- The site's CloudFront function ([site.yaml](../tabcam_infra/site.yaml))
  sends a known crawler (by its user agent) asking for
  `/app/?c=<id>&k=<key>` (ID and key well formed) to
  `/preview/<id>/<key>` (a 302). People always get the app; so does any
  other request.
- `/preview/*` comes from the share API (`GET /preview/{captureId}/{key}`,
  no sign-in; [index.py](../tabcam_api/shares/index.py)), cached by
  CloudFront for 5 minutes. For a key that opens the capture, it reads
  its `event.json` with the link's own read-only credentials and answers
  a small page: the title ("<title> – <artist>"), a description of what
  it holds ("<artist> · 2 pages, 1 PDF, 1 link, a text tab. Shared with
  TabCam."; images left out when hidden), the link itself as `og:url`
  and the app's icon as the image. A wrong key, a deleted capture or a
  malformed link: TabCam's own title and description. Someone who lands
  on the page goes on to the app (a script; crawlers don't run it).
- The site names itself to the API (`x-tabcam-site`, the RC's or
  production's), so the preview links back to the same site. It's on when
  the site is deployed with the share API's domain (`ShareApiDomain`,
  from `TABCAM_SHARE_API_URL`; [deploy](deploy.md)).

A rename shows in new previews within 5 minutes (chat apps keep their
own copy of a preview already shown).

## Android App Links

On Android, `https://tabcam.nu01.com/app…` and
`https://rc.tabcam.nu01.com/app…` open in the TabCam app instead of
the browser (an `autoVerify` intent filter; every web app address, not
only capture links: without `?c=` the app just opens). A link that
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
