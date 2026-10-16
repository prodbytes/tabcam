# Maintenance mode

Administrators can put the system in maintenance mode. While it's on, the
apps (web, Android, iOS) show no UI at all: only a sorry message, centered
on a dark screen.

## The switch

The site's `/status.json`, at the root of the site bucket (outside
`/app/`, so deploys never touch it):

```json
{"maintenance": true, "message": "Back at 18:00 UTC"}
```

`message` is optional; without it the apps say "Sorry, TabCam is down
for maintenance. Please try again later." Production
(https://tabcam.nu01.com/status.json) and the release candidate
(https://rc.tabcam.nu01.com/status.json) each have their own. The local
stack's is [tabcam_index/site/status.json](../tabcam_index/site/status.json),
off; edit it to try maintenance mode locally (deploys upload only the
index page, never this file).

An administrator flips it with `scripts/maintenance.sh` (also
`devbox run maintenance`), which needs AWS credentials that may write the
site's bucket and invalidate its CloudFront distribution:

- `bash scripts/maintenance.sh on ["message"]`: maintenance mode on;
- `bash scripts/maintenance.sh off`: back to normal (writes
  `{"maintenance": false}`);
- `bash scripts/maintenance.sh status`: what the site says now.

`STAGE=rc` targets the release candidate (production by default). The
script writes the file (`Cache-Control: no-cache`), invalidates
`/status.json`, waits for the invalidation, and checks the live file says
what it wrote.

## In the app

- **At start** the app checks the status before showing anything (a blank
  dark screen, for at most 4 seconds). The library, sign-in and sync start
  only once the status says the system is up.
- **While running** it checks again every 2 minutes and whenever the app
  comes back to the foreground. If maintenance mode starts, the app is
  replaced by the sorry message and sync (and Premium's cloud OCR)
  stops; when it ends, the app comes back and they start again.
- **Where it looks**: the web app reads its own site's `/status.json`;
  Android and iOS builds read their stage's site (the RC's for
  `TABCAM_STAGE=rc`, otherwise production's).
  `TABCAM_STATUS_URL` overrides it (e.g. for testing).
- **It fails open**: if the status can't be read at start (offline, no
  file, not JSON), the app runs, so capturing without a network keeps
  working. A failed check later keeps what was known: an app in
  maintenance mode stays there until a check says it's over.
