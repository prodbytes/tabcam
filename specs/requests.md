# Request log

Requests that shaped the specification, oldest first. Each entry summarizes
what was asked and what changed. See [README.md](README.md) for the current
spec.

## 2026-10-10

1. **Which OCR library for a Flutter guitar tab scanner?** Recommended
   Google ML Kit text recognition on the device
   (`google_mlkit_text_recognition`), with layout logic of our own on top:
   OCR reads the numbers, but tabs are a grid, so which line a number is on
   and how numbers line up across lines must be worked out separately.
2. **Copy the repository structure of prodbytes/presence, without its app,
   and build a camera app like Adobe Scan or CamScanner for scanning and
   sharing guitar tabs.**
   - Structure, adapted from presence: devbox (Flutter, Python, AWS CLI,
     make, curl), the dev container with its post-create script, the
     `Makefile` and `scripts/` (build, run on web and Android, logs,
     version, RC and GA release tags, deploy, private settings link, health
     monitor), `process-compose.yaml` (web app, index page, health check),
     the Release, Deploy and Deploy RC workflows, `tabscan_infra/` (the
     S3 + CloudFront site and the GitHub OIDC deploy roles),
     `tabscan_index/`, the version files, and this `specs/` folder with
     the CLAUDE.md rules. Left out, as presence's own: the auth API, local
     AWS emulation (Floci), cloud sync, the install script site, and the
     Linux / Raspberry Pi builds. The blank template's PostgreSQL service
     was removed.
   - The app ([tabscan_app/](../tabscan_app)): a [library](library.md) of
     scans, [scanning](scanning.md) with the system document scanner,
     [page filters](page-filters.md), the [scan screen](scan-screen.md),
     [tab recognition](tab-recognition.md) and [sharing](sharing.md).
3. **Fix `devbox services up`, and give this project its own ports
   (not 8080).** It failed because presence's dev stack already held 8080
   and 8081. The web app now serves on **2012** and the index page on
   **2013** (process-compose, the scripts' defaults, the dev container's
   forwarded ports and the docs), so both stacks run side by side.
4. **Create the `tabscan.nu01.com` hosted zone and its delegation, and
   prepare to deploy.** Created the public zone `Z10277161AEN9OU2H73PJ`
   and its NS delegation in `nu01.com` (TTL 3600, like `rbacr` and
   `uplink`); see [deploy](deploy.md). Set the repository variable
   `HOSTED_ZONE_ID`. `TABSCAN_HEALTH_EMAILS` is now read from a repository
   secret, not a variable: the repository is public and run logs show
   variables. Pending: deploying the `tabscan-github-deploy` roles stack,
   then the `AWS_DEPLOY_ROLE_ARN` / `AWS_DEPLOY_RC_ROLE_ARN` variables and
   the `TABSCAN_HEALTH_EMAILS` secret.
5. **One health check line per run, with an icon, short label and status
   for each dependency; print the local URL once at startup.** The
   monitor now prints the app's and the index's URLs when it starts, then
   one line per check (`🏠 index ✅  🎸 web ✅`) instead of a line per
   service. See [development environment](dev-environment.md).
6. **Merge all pending changes and rebuild.** Merged #1 and the health
   check change (as #3: GitHub closed #2 when #1's branch was deleted).
   Rebuilt web, Android and iOS from `main`; the dev stack restarted
   healthy.
7. **Run on the attached iPhone, with the personal team of
   julio@nu01.com.** iOS now signs with the developer's own team from
   `.env` (`IOS_DEVELOPMENT_TEAM`), through a git-ignored xcconfig; see
   [platforms](platforms.md). Installed and launched on the iPhone after
   trusting the developer certificate.
8. **Make a better icon for the app, then relaunch on the iPhone.** New
   [app icon](app-icon.md): a scanned tab page in amber scanner corners,
   generated for Android, iOS and web. Relaunched on the iPhone with it.
9. **Show a scanned tab in the list; let an opened scan add more tabs,
   photos, and image or video files.** A finished scan now stays on the
   [library](library.md) list (scrolled to, highlighted, with Open in the
   confirmation) instead of opening. Pages can be videos: the scan
   screen's **Add** offers Scan pages, Photos & videos, and Files
   ([scanning](scanning.md#adding-to-a-scan)); videos play in place, are
   skipped by Filter, Rotate, Read tab and the PDF, and are shared as
   they are under the new **Files** format ([sharing](sharing.md)).
10. **Let users rename the scans.** Rename was only inside an opened scan;
    it's now also in each card's menu in the [library](library.md), and a
    long-press on a card. The dialog selects the current title, so typing
    replaces it.
11. **Is there a library or service that reliably transcribes tabs from
    images? Test real services with an uploaded tab.** None does it
    reliably end to end: Soundslice's scanner (paid, no API) and
    PhotoScore read typeset tab; vision LLMs are the only option with an
    API; open-source tools cover ASCII tab or other steps. Proposed a
    benchmark against a made-up riff with a known answer; waiting for the
    sample tab. No change to the app.
12. **Let users sign in, as Presence does, get S3 access through Cognito,
    and sync files with S3.** New [sign-in and cloud sync](cloud-sync.md):
    optional Google sign-in from the library's cloud button; the ID token
    goes to a Cognito identity pool (enhanced flow, no server) for
    credentials limited to the user's own folder in a new user-data
    bucket; scans and their pages sync both ways, deletions as tombstones.
    Scans now have `updated`, and `owner` once synced; Rotate stores a new
    page ([library](library.md)). New stacks `tabscan-user-data` and
    `tabscan-identity` (deployed once by an administrator); the settings
    come from `.env` or repository variables
    ([deploy](deploy.md), [platforms](platforms.md)). The Google OAuth
    clients are still to be created.
13. **Call a scan an "event" from now on, since it can hold more than
    scans; in the code, `CaptureEvent`.** The app and the specs say
    "event" for what was a scan ([library](library.md#events), the
    [event screen](event-screen.md), sharing, sync); scanning pages is
    still **Scan**. In the code `Scan` is `CaptureEvent`, `ScanPage` is
    `EventPage`, `ScanStore` is `EventStore` and `ScanScreen` is
    `EventScreen`. Files on the device keep their names
    (`scans/<id>/scan.json`), so existing libraries load; the cloud
    layout, not yet deployed, becomes `<identity>/events/<id>/event.json`
    in the `nu01-user-events-<account>` bucket
    ([cloud sync](cloud-sync.md)).
14. **Let users add links to events as well.** The event screen's **Add**
    has **Link**: an address (http or https; `https://` added when
    missing) and an optional title, kept as a link page with no file
    ([scanning](scanning.md#adding-to-an-event)). It shows as a card with
    **Open** and **Copy** ([event screen](event-screen.md)); the library
    card counts links; Text and the PDF share them, Files leaves them out
    ([sharing](sharing.md)); they sync inside `event.json`
    ([cloud sync](cloud-sync.md)).
15. **Add a clone button, so captures can be cloned and shared with
    different people.** **Clone**, in a library card's menu and the event
    screen's app bar, copies an event as a new one of the user's own
    ("<title> (copy)", the pages' files copied, links as they are, never
    synced or shared); the event screen opens the copy
    ([library](library.md#events)).
16. **Share captures by email, without sending email: add the granted
    address so they can access it; edit (collaborate) by default, or read
    only.** New [shared captures](shared-captures.md): the event screen's
    **Share with people** grants addresses, to edit or read only. A share
    API (`tabscan_api/shares/`, stack `tabscan-share-api`: Lambda,
    DynamoDB, an HTTP API with a Google JWT authorizer) keeps the grants
    and hands out credentials for one capture's folder. Each sync pass
    then syncs what's shared with the user; read-only copies are locked
    in the app and never upload; **Remove** leaves a share. The API is
    to be deployed by an administrator (`scripts/deploy-share-api.sh`)
    once the OAuth clients exist.
17. **Prefix all variables with `TABSCANNER_`.** Every setting now has
    the prefix, with one name everywhere: `.env`, the scripts, the app's
    dart-defines and the repository variables and secrets
    (`TABSCANNER_GOOGLE_WEB_CLIENT_ID`, `TABSCANNER_HOSTED_ZONE_ID`,
    `TABSCANNER_AWS_DEPLOY_ROLE_ARN`, …); `TABSCAN_STAGE`,
    `TABSCAN_VERSION`, `TABSCAN_BIND_HOST` and `TABSCAN_HEALTH_EMAILS`
    became `TABSCANNER_*`. `AWS_REGION` is unchanged
    ([dev environment](dev-environment.md)), and so is the share
    function's own environment (set by its stack, not by people).
18. **Let anonymous users capture, stored only locally; require sign-in
    for processing and sharing.** Signed out, capturing works and stays on
    the device; **Read tab** and **Share** open a
    "Sign in to read tabs" / "Sign in to share" sheet first, which goes
    on with the action once signed in
    ([signed out](cloud-sync.md#signed-out)); Share with people already
    showed only signed in. Builds without sign-in set up don't ask. A
    sync pass ending after the app closed no longer notifies.
19. **Let admins put the system in maintenance mode; while it's on, no UI
    is shown at all, just a sorry message.** New
    [maintenance mode](maintenance-mode.md): `scripts/maintenance.sh
    on|off|status` (STAGE=prod or rc) writes the site's `/status.json`
    and invalidates it. The apps check it before showing anything, every
    2 minutes and on resume; in maintenance mode they show only the sorry
    message (the admin's, or a default) and stop syncing. Unreadable
    status fails open, so offline capture keeps working.
20. **Add a copy button to the top of the transcription view.** The text
    tab screen's **Copy** moved from an app-bar icon to a labeled button
    above the text ([text tab editor](tab-recognition.md#text-tab-editor)).
21. **Transcribe a photographed tab with several OCR kits, compare with the
    real tab, and say which combination comes closest.** A local bench
    (`test_data/ocr_bench/`, kept out of git: it holds a published tab):
    Tesseract, EasyOCR, RapidOCR, PaddleOCR, docTR (TensorFlow), Apple
    Vision, AWS Rekognition and Textract, on the photo raw, cleaned and
    binarized, whole-page and cut into string lines. Whole-page OCR loses
    the dash runs; reading line by line with a vote of Tesseract,
    PaddleOCR and RapidOCR came closest. No change to the app.
22. **Could the best one run in AWS Lambda?** Yes, as a container image;
    no change.
23. **Add `tabscan_locr`, a Lambda that transcribes tabs as they're
    scanned, for premium users only (premium from rbacr), offering the
    upgrade to free users.** New [TabScan Premium: cloud OCR](cloud-ocr.md):
    the service in [tabscan_locr/](../tabscan_locr/README.md), triggered by
    page uploads to the user-data bucket (now sending its events to
    EventBridge), checking rbacr's `tabscan/premium` role with a root token
    in Secrets Manager, and writing transcriptions beside the user's events;
    new stacks `tabscan-ocr-repo` and `tabscan-ocr`. The app fills in text
    tabs from them, asks for pages from before upgrading, and offers
    Premium in the account sheet and on the event screen
    ([cloud sync](cloud-sync.md), [tab recognition](tab-recognition.md));
    new setting `TABSCANNER_OCR_URL` ([deploy](deploy.md),
    [dev environment](dev-environment.md)).
24. **TabScan doesn't work on the iPhone: relaunch and verify.** It
    crashed at launch ("Null check operator used on a null value" in
    `MaintenanceCheck.start`): the maintenance check, started before
    `runApp`, used `WidgetsBinding.instance` before there was one. `main`
    now initializes the binding first. Verified on the iPhone (a profile
    build: it launches, with no errors in its log).
25. **Commit all changes, by intention.** The Swift packages Google
    sign-in's iOS build resolves (Xcode's `Package.resolved`, both copies)
    are committed, so every build uses the same versions;
    [platforms](platforms.md) says where iOS dependencies come from and
    notes the two copies of Google's utilities (ML Kit's CocoaPods and
    sign-in's Swift packages) that iOS warns about.
26. **Create the DNS record for https://local.tabscan.nu01.com, pointing
    to localhost.** Added `local.tabscan.nu01.com` to the
    `tabscan.nu01.com` zone: A `127.0.0.1` and AAAA `::1`, TTL 300, made
    by hand with the AWS CLI (no stack owns it)
    ([deploy](deploy.md), [dev environment](dev-environment.md)).
27. **Local HTTPS through Floci, merged as it was, when asked to merge
    everything.** The dev stack gets Floci as a local CloudFront (HTTP on
    2014, HTTPS on 2443, both on 127.0.0.1) in front of the dev servers,
    with an mkcert certificate for `local.tabscan.nu01.com` and the
    `*.localhost` names (`scripts/local-certs.sh`; the key stays in the
    git-ignored `tabscan_floci/certs`); the health monitor checks the CDN
    and HTTPS too. Still to write: `tabscan_floci/README.md` (with the
    one-time `mkcert -install`) and the [dev environment](dev-environment.md)
    spec for it.
28. **Make the navigation like Presence's: a bottom navigation bar with
    Home (the list), Capture and Profile; Capture with Scan for the camera
    and Add buttons for uploads.** New [navigation](navigation.md): the
    bar (flat, the open tab by color only, the Profile icon the user's
    photo), the tab's name in the app bar. **Capture** has Scan and Add
    (Photos & videos, Files, Link; a link's title names its event), each
    making a new event shown on Home. **Profile** has the account (was
    the app bar's cloud button and its sheet) and About (was an app bar
    button). Import photos through the scanner is gone: photos are added
    as they are.
29. **On the home screen, show both the captures I created and the
    captures shared with me.** Shared captures were already on Home, mixed
    in with the user's own. Home now splits them into two headed sections
    once something is shared: **My captures** above, **Shared with me**
    below, each newest first ([library](library.md),
    [shared captures](shared-captures.md)). With nothing shared, the grid
    has no headings.
