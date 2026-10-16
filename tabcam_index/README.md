# tabcam_index

The site root. Its only page, [site/index.html](site/index.html), sends
visitors to the app at `/app/`: a script redirect (`location.replace`,
keeping any query string), a `meta refresh` for browsers without
JavaScript, and a plain link as a last resort.

Locally it also serves [site/status.json](site/status.json), the
[maintenance mode](../specs/maintenance-mode.md) switch (off), so the
local web app's status checks don't 404. Deploys upload only
`index.html`: the live sites' status files are set with
`scripts/maintenance.sh`.

Only [site/](site) is served, so this README isn't.

## Running it

`devbox services up` serves it as `5-index`, on http://localhost:2013/
(`INDEX_PORT`), with Python's `http.server` bound to 127.0.0.1. In
production it's the CloudFront distribution's default origin
([tabcam_infra/site.yaml](../tabcam_infra/site.yaml)).

Edits to `site/` show up on the next request; nothing needs restarting.
