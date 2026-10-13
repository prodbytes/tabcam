# Sharing

**Share** (the event screen's app bar, a link icon, or a library card's
menu) copies the capture's link to the clipboard, nothing else: no
choice of format, no text around it. "Link copied" says it's done.
Signed out, it asks to sign in first
([signed out](cloud-sync.md#signed-out)).

- The link is `https://tabscan.nu01.com/app/?c=<capture id>`
  ([`CaptureLink`](../tabscan_app/lib/export/capture_link.dart)); it
  names the capture by its ID only. On the web it's to the site the app
  runs on (the RC's, or a local one); in the phone apps, to production's,
  or the RC's for RC builds. Copying it starts a sync pass, so the capture
  is in the cloud. See [opening a link](#opening-a-link).
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

- signed out, it says to sign in (Profile) to open it, and opens it once
  signing in has synced it;
- signed in, it waits for a sync pass (starting one if none is running);
  if the pass doesn't bring it, it says the capture isn't shared with the
  user and to ask its owner to share it with their email address;
- in a build without cloud sync, it says the capture isn't on this
  device.

The link gives no access by itself: who can open it is who the owner
shared it with ([Share with people](shared-captures.md)).

## Android App Links

On Android, `https://tabscan.nu01.com/app…` and
`https://rc.tabscan.nu01.com/app…` open in the TabScan app instead of
the browser (an `autoVerify` intent filter; every web app address, not
only capture links: without `?c=` the app just opens). A link that
launches the app, or reaches it while it runs, goes to `IncomingLinks`
([lib/export/incoming_links.dart](../tabscan_app/lib/export/incoming_links.dart)),
a binding observer added before `runApp`, so the Navigator never takes
the link for a named route; Home then opens the capture as above. The
app's initial route is always `/`.

Android opens them in the app only when the site vouches for the app's
signing key: `https://<site>/.well-known/assetlinks.json` (from
[tabscan_index/site/.well-known/](../tabscan_index/site/.well-known/assetlinks.json),
uploaded by every deploy, both sites) lists the SHA-256 fingerprints of
the keys allowed. It lists the maintainer's debug key (builds without the
upload key) and the upload key, which signs release builds: those
installed with `scripts/android-install.sh` and the Release workflow's.
Google Play's app signing key is to be added once the app is on Play
([app stores](app-stores.md#android-signing)); until then, Play's builds
open the links in the browser.
