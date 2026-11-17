# Index page

The site's front page, at https://tabs.cam/ (and https://rc.tabs.cam/):
what tabs.cam does, and the way into the app at `/app/`. One static
file, [tabcam_index/site/index.html](../tabcam_index/site/index.html),
with its pictures in [img/](../tabcam_index/site/img); no build, no
framework, no third-party requests (the fonts are the device's, Roboto
where it's installed). In English. It no longer redirects to the app:
only a capture's link that names the root (`/?c=…`) is sent on to
`/app/`, its query kept.

## The page

Dark, in the brand's colours ([app icon](app-icon.md): `#1E1A15`, cream
`#FBF7EF`, gold `#E0A030`), from top to bottom:

- **Top bar**, kept at the top while scrolling: the
  [logo](app-icon.md), links to the three features (Scan, Record, Share;
  hidden on phones) and **Open the app** (`/app/`).
- **Header**: "For guitar and bass players", the title **A camera for
  your guitar tabs**, a sentence on what it does, **Open tabs.cam**
  (`/app/`), "Runs in your browser, on your phone or your computer", and
  a faint six-line staff under them.
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
  adds, in their own account), no ads, no tracking, and **Open
  tabs.cam**.
- **Footer**: Open the app and the [Privacy Policy](privacy.md)
  (`/privacy`).

**Where a box sits** depends on the width. From 1200 px it's over a
corner of the picture (`bl`, `br`, `tl` or `tr` on the box, chosen per
picture so it covers nothing that matters; both pictures have it bottom
left), 430 px wide at most, hanging 72 px below the picture when at the
bottom. From 700 px it's under the picture, 48 px over its bottom edge,
at the left. On phones it's under the picture, the page's width less 16
px a side, 12 px over its edge.

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

[Deploy](deploy.md) uploads `index.html` and syncs `img/` to the site's
bucket, and checks that `/` is this page and `/img/logo.svg` is served.
Locally `5-index` serves the folder as it is
([development environment](dev-environment.md)), through Floci at
https://local.tabcam.nu01.com:2443/.
