# Index page

The site's front page, at https://tabs.cam/ (and https://rc.tabs.cam/):
what tabs.cam does, and the way into the app at `/app/`. One static
file, [tabcam_index/site/index.html](../tabcam_index/site/index.html),
with its pictures in [img/](../tabcam_index/site/img); no build, no
framework, and no third-party requests but Google's sign-in script, for
visitors not signed in ([signing in](#signing-in-here)); the fonts are
the device's, Roboto where it's installed. In English. Two visits go
straight on to the app instead, the page not shown: a capture's link
that names the root (`/?c=…`), its query kept, and anyone
[signed in already](#signed-in-already).

## The page

Dark, in the brand's colours ([app icon](app-icon.md): `#1E1A15`, cream
`#FBF7EF`, gold `#E0A030`), from top to bottom:

- **Top bar**, kept at the top while scrolling: the
  [logo](app-icon.md), links to the three features (Scan, Record, Share;
  hidden on phones) and **Open the app** (`/app/`).
- **Header**: "For guitar and bass players", the title **A camera for
  your guitar tabs**, a sentence on what it does, **the way in** (below),
  "Runs in your browser, on your phone or your computer", and a faint
  six-line staff under them.
- **The three key features**, each a picture as wide as the page (1376
  px at most) with its text in a **box over it**: a dark, slightly
  see-through box with a gold top edge and a deep shadow, holding the
  feature's number, title, a sentence and three points. The boxes rise
  into place as they're scrolled to (not with reduced motion, nor
  without JavaScript, where they just show).
  1. **Scan your tabs** (`#scan`): point the phone at a tab, read into
     text, found and used in seconds; editable text, search by title,
     artist or notes, on every device.
  2. **Record your practice** (`#record`): Cam shows the tab under the
     camera, one phrase at a time, and keeps every take with its tab in
     the video; next phrase by tap, key or pedal, the video edit, the
     download.
  3. **Share and play along** (`#share`): a tab's link for students and
     friends, read only; playing a recording or video above the tab;
     what they record goes to their own copy. Its picture is yet to
     come: until then its box stands alone, centred.
- **The way in, again**: "Start with the tab on your music stand", that
  tabs.cam comes with no songs (everything is what the user scans or
  adds, in their own account), no ads, no tracking, and the way in
  again.
- **Footer**: Open the app and the [Privacy Policy](privacy.md)
  (`/privacy`).

**Where a box sits** depends on the width. From 1200 px it's over a
corner of the picture (`bl`, `br`, `tl` or `tr` on the box, chosen per
picture so it covers nothing that matters; both pictures have it bottom
left), 430 px wide at most, hanging 72 px below the picture when at the
bottom. From 700 px it's under the picture, 48 px over its bottom edge,
at the left. On phones it's under the picture, the page's width less 16
px a side, 12 px over its edge.

## The way in

What the header and the closing section offer to a visitor not signed
in (one signed in never sees the page, [below](#signed-in-already)):

- **With a Google client** (the deploy's or the local
  server's, below): Google's own **Continue with Google** button (white,
  English, 40 px high; "Continue as *name*" when the browser has a Google
  account), then **Open tabs.cam** beside it, an outline of the same
  height, for the other ways in (email; the app's welcome has them all).
  On phones they stack, each as wide as the page less 16 px a side, 360
  px at most. Until Google's script has drawn its button, its place is
  kept (a faint box), so nothing moves.
- **No client, or Google's script fails to load** (blocked, offline): as
  before, **Open tabs.cam** alone, gold.

## Signed in already

Someone signed in on this browser (the app's tabs.cam session in
`localStorage` `tabcam.signed-in`, with its refresh token, or a Google
sign-in whose token is good for another minute, `tabcam.session`) goes
straight on to the app: the page's first script sends them to `/app/`
before anything shows (the page stays blank, in its background colour,
meanwhile), replacing the index in the history so Back doesn't land on
it again. A link to one of the page's sections (`/#record`) goes to the
app too. Google's script isn't loaded. Signing out in the app clears
both keys, so the page shows again; a stale session (a refresh token
the API no longer takes) gets the app, which asks for a sign-in. Search
engines and other visitors with no sign-in get the page.

## Signing in here

Not signed in, the page loads Google Identity Services
(`accounts.google.com/gsi/client`) and offers the sign-in two ways, both
one click:

- **One Tap**: Google's prompt, asked for at once (`prompt()`; FedCM,
  `auto_select` off, so no one is signed in without choosing to, and
  closed by a tap outside it). With FedCM (Chrome) the browser places it,
  top right on computers and a sheet at the bottom on phones; in
  browsers without FedCM Google draws it in `#one-tap`, fixed under the
  top bar at the right, so it never covers the bar's **Open the app**.
- **The buttons** above, in the header and the closing section.

A sign-in hands over to the app without a server of its own: the page
reads the ID token's claims and keeps the sign-in where the app's Google
sign-in keeps its own (`localStorage` `tabcam.session`: the subject as
`id`, email, name, photo, `provider: google`, the token), then opens
`/app/`. The site and the app share the origin, so the app finds it at
launch as a Google sign-in from before the reload, and starts its
[tabs.cam session](sessions.md) from the token, with no prompt. Storage
off (some private modes), it opens the app anyway, which asks again.

**The client ID** is the app's Google web client (a public identifier):
the page has `<meta name="google-signin-client_id" content="">`, which
[`scripts/index_page.py`](../scripts/index_page.py) fills in. The deploy
fills it with `TABCAM_GOOGLE_WEB_CLIENT_ID` before uploading (refusing
anything that isn't a client ID) and checks the live page has it; the
local server (`index_page.py serve`) with the local web client
(`TABCAM_GOOGLE_LOCAL_WEB_CLIENT_ID`, else `TABCAM_GOOGLE_WEB_CLIENT_ID`;
environment, else `.env`), the one the local app signs in with. The
client's JavaScript origins are the app's already (`/` and `/app/` are
one origin). Empty, there's no Google sign-in on the page.

## Pictures

In [tabcam_index/site/img/](../tabcam_index/site/img), WebP made with
`cwebp` from the 1376 x 768 originals, in two widths, the browser
picking by the page's width (`srcset`): `scan.webp` and `record.webp`
(1376 px, quality 82, about 160 KB each) and `scan-800.webp` and
`record-800.webp` (800 px, quality 80, about 60 KB). All but the first
load only when scrolled near (`loading="lazy"`). `logo.svg` is a copy of
the app's logo, which [`scripts/app-icon.sh`](../scripts/app-icon.sh)
writes there too. The favicon is the app's (`/app/favicon.png`).

## Serving

[Deploy](deploy.md) uploads `index.html` (its client ID filled in) and
syncs `img/` to the site's bucket, and checks that `/` is this page (with
the client ID, when there is one) and `/img/logo.svg` is served.
Locally `5-index` serves the folder with `scripts/index_page.py serve`,
the client ID filled in ([development environment](dev-environment.md)),
through Floci at https://local.tabcam.nu01.com:2443/.
