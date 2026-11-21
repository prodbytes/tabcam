# tabcam_index

The site root: the index page, [site/index.html](site/index.html), which
presents tabs.cam (a header, and its three key features, each a picture
with its text in a box over it) and links to the app at `/app/`. One
static file with its pictures and the logo in [site/img/](site/img); no
build. What's on it and how it's laid out:
[specs/index-page.md](../specs/index-page.md).

To add or change a feature's picture, write it as WebP in two widths and
name both in the section's `<img>`:

```
cwebp -q 82 picture.jpeg -o site/img/NAME.webp
cwebp -q 80 -resize 800 0 picture.jpeg -o site/img/NAME-800.webp
```

Locally it also serves [site/status.json](site/status.json), the
[maintenance mode](../specs/maintenance-mode.md) switch (off), so the
local web app's status checks don't 404, and the
[privacy policy](../specs/privacy.md). Deploys upload `index.html`,
`img/`, the privacy policy, `.well-known/` and
[site/robots.txt](site/robots.txt) (everything allowed; it names
production's sitemap, which the share API answers), never `status.json`:
the live sites' status files are set with `scripts/maintenance.sh`.

Only [site/](site) is served, so this README isn't.

## Running it

`devbox services up` serves it as `5-index`, on http://localhost:2013/
(`INDEX_PORT`), with Python's `http.server` bound to 127.0.0.1. In
production it's the CloudFront distribution's default origin
([tabcam_infra/site.yaml](../tabcam_infra/site.yaml)).

Edits to `site/` show up on the next request; nothing needs restarting.
