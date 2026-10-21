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
     the Release, Deploy and Deploy RC workflows, `tabcam_infra/` (the
     S3 + CloudFront site and the GitHub OIDC deploy roles),
     `tabcam_index/`, the version files, and this `specs/` folder with
     the CLAUDE.md rules. Left out, as presence's own: the auth API, local
     AWS emulation (Floci), cloud sync, the install script site, and the
     Linux / Raspberry Pi builds. The blank template's PostgreSQL service
     was removed.
   - The app ([tabcam_app/](../tabcam_app)): a [library](library.md) of
     scans, [scanning](scanning.md) with the system document scanner,
     [page filters](page-filters.md), the [scan screen](scan-screen.md),
     [tab recognition](tab-recognition.md) and [sharing](sharing.md).
3. **Fix `devbox services up`, and give this project its own ports
   (not 8080).** It failed because presence's dev stack already held 8080
   and 8081. The web app now serves on **2012** and the index page on
   **2013** (process-compose, the scripts' defaults, the dev container's
   forwarded ports and the docs), so both stacks run side by side.
4. **Create the `tabcam.nu01.com` hosted zone and its delegation, and
   prepare to deploy.** Created the public zone `Z01245733BIHST1A417HE`
   and its NS delegation in `nu01.com` (TTL 3600, like `rbacr` and
   `uplink`); see [deploy](deploy.md). Set the repository variable
   `HOSTED_ZONE_ID`. `TABCAM_HEALTH_EMAILS` is now read from a repository
   secret, not a variable: the repository is public and run logs show
   variables. Pending: deploying the `tabcam-github-deploy` roles stack,
   then the `AWS_DEPLOY_ROLE_ARN` / `AWS_DEPLOY_RC_ROLE_ARN` variables and
   the `TABCAM_HEALTH_EMAILS` secret.
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
    page ([library](library.md)). New stacks `tabcam-user-data` and
    `tabcam-identity` (deployed once by an administrator); the settings
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
    API (`tabcam_api/shares/`, stack `tabcam-share-api`: Lambda,
    DynamoDB, an HTTP API with a Google JWT authorizer) keeps the grants
    and hands out credentials for one capture's folder. Each sync pass
    then syncs what's shared with the user; read-only copies are locked
    in the app and never upload; **Remove** leaves a share. The API is
    to be deployed by an administrator (`scripts/deploy-share-api.sh`)
    once the OAuth clients exist.
17. **Prefix all variables with `TABCAM_`.** Every setting now has
    the prefix, with one name everywhere: `.env`, the scripts, the app's
    dart-defines and the repository variables and secrets
    (`TABCAM_GOOGLE_WEB_CLIENT_ID`, `TABCAM_HOSTED_ZONE_ID`,
    `TABCAM_AWS_DEPLOY_ROLE_ARN`, …); `TABCAM_STAGE`,
    `TABCAM_VERSION`, `TABCAM_BIND_HOST` and `TABCAM_HEALTH_EMAILS`
    became `TABCAM_*`. `AWS_REGION` is unchanged
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
23. **Add `tabcam_locr`, a Lambda that transcribes tabs as they're
    scanned, for premium users only (premium from rbacr), offering the
    upgrade to free users.** New [TabCam Premium: cloud OCR](cloud-ocr.md):
    the service in [tabcam_locr/](../tabcam_locr/README.md), triggered by
    page uploads to the user-data bucket (now sending its events to
    EventBridge), checking rbacr's `tabcam/premium` role with a root token
    in Secrets Manager, and writing transcriptions beside the user's events;
    new stacks `tabcam-ocr-repo` and `tabcam-ocr`. The app fills in text
    tabs from them, asks for pages from before upgrading, and offers
    Premium in the account sheet and on the event screen
    ([cloud sync](cloud-sync.md), [tab recognition](tab-recognition.md));
    new setting `TABCAM_OCR_URL` ([deploy](deploy.md),
    [dev environment](dev-environment.md)).
24. **TabCam doesn't work on the iPhone: relaunch and verify.** It
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
26. **Create the DNS record for https://local.tabcam.nu01.com, pointing
    to localhost.** Added `local.tabcam.nu01.com` to the
    `tabcam.nu01.com` zone: A `127.0.0.1` and AAAA `::1`, TTL 300, made
    by hand with the AWS CLI (no stack owns it)
    ([deploy](deploy.md), [dev environment](dev-environment.md)).
27. **Local HTTPS through Floci, merged as it was, when asked to merge
    everything.** The dev stack gets Floci as a local CloudFront (HTTP on
    2014, HTTPS on 2443, both on 127.0.0.1) in front of the dev servers,
    with an mkcert certificate for `local.tabcam.nu01.com` and the
    `*.localhost` names (`scripts/local-certs.sh`; the key stays in the
    git-ignored `tabcam_floci/certs`); the health monitor checks the CDN
    and HTTPS too. Still to write: `tabcam_floci/README.md` (with the
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
29. **Make https://local.tabcam.nu01.com work over HTTPS using Floci, as
    presence does.** Finished the local HTTPS from 27. Floci no longer gets
    `FLOCI_PORT` in its environment: it read that as its own listen port,
    so its setup hook couldn't reach it and the container restarted in a
    loop. Wrote [tabcam_floci/README.md](../tabcam_floci/README.md), and
    described `4-floci` and the `cdn` and `https` checks in the
    [dev environment](dev-environment.md) spec, the README and AGENTS.md.
    Checked with `devbox services up`:
    https://local.tabcam.nu01.com:2443/app/ answers with a trusted
    certificate.
30. **The local Google OIDC client ID should be
    `1061413485511-2ndd6lqkmi61j17vpk5f2ntjb91tt38r`; verify and fix.**
    Local builds used the production web client, whose only origin is
    https://tabcam.nu01.com. New setting
    `TABCAM_GOOGLE_LOCAL_WEB_CLIENT_ID` (the "local - web" client),
    which the dev web server uses in its place
    ([dev environment](dev-environment.md)). That client needs
    `https://local.tabcam.nu01.com:2443` among its JavaScript origins, and
    no redirect URI.
31. **Read tab is not working; add the logging needed to troubleshoot it,
    in the client and the server.** The app logs each step of Read tab
    (sign-in, the path taken, per-page preparation, OCR and layout
    results, failures with stack traces), every OCR API call and the cloud
    results it collects. The OCR service logs JSON lines per request, S3
    event, rbacr check and page read, including unexpected failures with
    tracebacks. See the troubleshooting logs in
    [tab recognition](tab-recognition.md#troubleshooting-log) and
    [cloud OCR](cloud-ocr.md#troubleshooting-log).
32. **The Cognito role is failing to assume; create the identity pool in
    infrastructure as code so that authenticated users can write to S3 and
    invoke Lambda functions.** The pool and its role were already in
    `tabcam_infra/identity.yaml` (deployed), with S3 writes to the user's
    own folder. What failed: the pool trusted only the production web
    client, so local builds' tokens (the local web client) were refused
    before any role was assumed. The pool, the OCR service and the share
    API now also trust `GoogleLocalWebClientId`, and the bucket, the OCR
    function URL and the share API allow the origin
    `https://local.tabcam.nu01.com:2443`
    ([cloud sync](cloud-sync.md), [cloud OCR](cloud-ocr.md),
    [shared captures](shared-captures.md)). No `lambda:InvokeFunction` was
    granted to users: the app reaches its functions through the OCR function
    URL and the share API with the Google token, and invoking
    `tabcam-ocr-api` or `tabcam-ocr` directly would let a user forge S3
    events for other users' pages. Deploying the pool change failed:
    Cognito takes one Google client ID of at most 128 characters, so a pool
    can't trust two clients (rolled back, the pool unchanged; see 36).
33. **When a photo is added by hand, crop it to the page, without what's
    under it.** Photos added with Photos & videos or Files are cropped and
    straightened to the page when one stands out (the largest bright
    region, its four corners, a perspective correction), as a JPEG; when
    no page stands out, they're kept as picked
    ([scanning](scanning.md#cropping-photos-to-the-page)).
34. **Hide status messages after a while.** The "Saved … (Open)" message
    after a capture stayed until dismissed, since Flutter keeps a message
    with a button by default; it now goes after 6 seconds, like the
    others, which already went after 4 ([navigation](navigation.md#capture)).
35. **In the Capture view, Scan should open the camera, Photos the album,
    Files the upload.** Photos & videos and Files already did; on the
    web, Scan was a file input with a camera hint, which desktop browsers
    show as a file chooser. It now opens TabCam's own camera screen (the
    browser's camera: a preview, a shutter, several pages, Flip, Done;
    photos instead when there's no camera)
    ([scanning](scanning.md#web)). Android and iOS keep the system
    document scanner. Its pages are cropped to the page, as photos added
    by hand are.
36. **Merge, run and deploy (the local client in AWS); then: a separate
    identity pool for local builds.** Merged the logging and local-client
    PRs and deployed the bucket's CORS, the OCR service (with the
    logging) and the share API. As a Cognito pool can trust only one
    Google client, `identity.yaml` now makes one pool per stack (parameter
    `PoolName`; export `<stack>-pool-id`): `tabcam-identity` (unchanged)
    and the new `tabcam-identity-local`, pool `tabcam-local`, trusting the
    local web client, with its own role on the bucket. The dev web server
    uses `TABCAM_COGNITO_LOCAL_IDENTITY_POOL_ID` with the local client
    ([dev environment](dev-environment.md), [cloud sync](cloud-sync.md)).
    Premium and sharing still don't work in local web builds (the OCR
    service and share API look identities up in the main pool).
37. **In the capture view, let the first button cycle Original, Scan and
    Text (the original, processed and OCR views); no Read tab button: read
    every tab submitted by itself.** The event screen's first tool is the
    view, Original → Scan → Text, which sets the image pages' filter or
    shows the text in place of the pages ([event screen](event-screen.md)).
    Read tab is gone: `AutoReader` reads each capture whenever its image
    pages change (on the device, or Premium's cloud), never replacing a
    text the user edited (`tabTextAuto`), and waits for sign-in signed out
    ([tab recognition](tab-recognition.md)). The text tab screen became
    the Text view.

38. **404s for `/status.json` on the local site.** The local stack had no
    status file, so every [maintenance](maintenance-mode.md) check of the
    local web app logged a 404 (harmless: the app reads a missing file as
    "not in maintenance"). The index now serves
    `tabcam_index/site/status.json` (`{"maintenance": false}`); flip it to
    `true` to try maintenance mode locally. Deploys still upload only the
    index page, so the live sites' status files are untouched.
39. **On the home screen, show both the captures I created and the
    captures shared with me.** Shared captures were already on Home, mixed
    in with the user's own. Home now splits them into two headed sections
    once something is shared: **My captures** above, **Shared with me**
    below, each newest first ([library](library.md),
    [shared captures](shared-captures.md)). With nothing shared, the grid
    has no headings.
40. **Let a user mark an OCR reading as correct; once marked, show the
    text tab by default instead of the image, and the image while it
    isn't.** The text tab editor has **Mark correct** next to Copy (then
    **Correct**, tapped again to unmark), saved on the event as
    `tabTextCorrect` and synced. An event marked correct opens on its text
    tab, its pages one step back; otherwise on its pages, as before. A new
    on-device reading clears the mark; cloud OCR never replaces a marked
    text tab. Specs: [tab recognition](tab-recognition.md#text-tab-editor),
    [event screen](event-screen.md), [cloud OCR](cloud-ocr.md).
41. **The Share button should offer only Link (the default: a link to this
    capture), PDF (every PDF and image combined) or Files (a zip of
    everything); then: keep the text-only share too. The link holds only
    the capture ID; save the owner and the shares in the capture event.
    Web link first, then Android links.** [Sharing](sharing.md) offers
    Link (default), PDF, Text and Files; Files is now one zip with the
    pages, `tab.txt` and `links.txt`. The link is
    `https://tabcam.nu01.com/app/?c=<capture id>`; the web app opens it
    from the user's events (own or shared), after signing in and a sync
    pass if needed. `event.json` in the cloud now has `owner` and
    `shares`, which the owner's app records from the share API
    ([cloud sync](cloud-sync.md), [shared captures](shared-captures.md)).
    Android app links are a follow-up. The text tab and links go in the
    PDF and the zip. (There are no PDF pages: pages are images, videos and
    links, so PDF combines the images.)
42. **Let the owner hide the original image and show only the text and
    attachments.** A capture's owner can now **Hide images** (and **Show
    images**) from the event screen's app bar. This is a synced setting
    (`hideImages` in `event.json`), so it applies to everyone: the owner's
    devices and the people it's shared with, who can't change it. Hidden,
    the event screen shows the text tab as the first page, then the videos
    and links. Library cards show no image, and PDF and Files exports
    leave the images out. The images are kept, Read tab still reads them,
    and grantees still sync them ([hidden images](hidden-images.md)).
43. **(Continuing 37) Android links.** Android App Links: the app opens
    `https://tabcam.nu01.com/app…` and the RC's (verified intent filter),
    and opens the capture a link names, launched or running
    (`IncomingLinks`). Deploys upload `/.well-known/assetlinks.json`, which
    lists the maintainer's debug key; Release-workflow APKs, signed with a
    new debug key each run, aren't verified until there's a release key
    ([sharing](sharing.md#android-app-links), [platforms](platforms.md),
    [release](release.md), [deploy](deploy.md)).
44. **In the camera screen, make auto shutter off the default and remove
    filters.** On the phone, Scan is the system document scanner, which
    lets the app set neither the shutter mode nor (on iOS) the filters.
    Android's scanner now runs in ML Kit's base mode, so it has no filters
    (and no ML clean-up). Auto capture stays the scanners' default, and iOS
    keeps VisionKit's filters ([scanning](scanning.md),
    [platforms](platforms.md)). TabCam's own camera screen (the web) has
    neither auto shutter nor filters.
45. **Bring back the "Text" button in the capture view to flip from scan
    to text; remove the flip button from the top and leave flipping to
    the bottom bar.** The event screen's tools are the view (**Original ↔
    Scan**), then **Text**, which shows the text view in place of the
    pages and reads **Pages** to go back; then Add, Rotate, Delete. The
    app bar's Hide images / Show images button is gone. `hideImages` is
    still honoured, so a capture already hidden stays hidden
    ([event screen](event-screen.md), [hidden images](hidden-images.md),
    [tab recognition](tab-recognition.md#text-view)).
46. **Show the user's role on the profile screen.** The signed-in account
    on Profile has a "Role: Premium" or "Role: Free" line under the name,
    from the premium status the cloud OCR service gets from rbacr ("Free
    (couldn't check)" when rbacr doesn't answer, "Checking…" until the
    first answer). Builds without the service show no role
    ([cloud OCR](cloud-ocr.md#in-the-app), [navigation](navigation.md#profile),
    [cloud sync](cloud-sync.md#signing-in)).
47. **Help me publish the app to the Apple and Google stores, step by
    step; with personal (individual) accounts.** A new
    [app stores](app-stores.md) spec tracks the steps. First, Android
    release signing: `scripts/android-keystore.sh` creates the upload key
    outside the repo and writes the git-ignored `key.properties`, which
    the Gradle build signs release builds with (else the debug key, as
    before); `make appbundle` builds the App Bundle; the Release workflow
    signs Android with the upload key from two secrets (never on pull
    requests) and publishes the `.aab` too; `scripts/android-install.sh`
    explains a signing key mismatch ([release](release.md),
    [platforms](platforms.md), [sharing](sharing.md#android-app-links),
    [cloud sync](cloud-sync.md), [dev environment](dev-environment.md)).

## 2026-10-11

48. **Hide the Premium purchase links in the store apps** (part of
    publishing to the stores). Apple's guidelines 3.1.1 and 3.1.3(b) and
    Google Play's payments policy reject apps that link out to buy
    digital features, and Premium is sold on the web. On Android and iOS
    the Premium card has no Upgrade, Redeem a voucher or "Subscribe with
    <address>" (a free user's card says Premium isn't active, with Check
    again), and the event screen has no Premium hint. Premium users still
    see the role, that Premium is on and until when. The web is
    unchanged. The widgets take a `store` flag, defaulting to the
    platform, tested both ways ([cloud OCR](cloud-ocr.md#in-the-app),
    [navigation](navigation.md#profile), [platforms](platforms.md),
    [app stores](app-stores.md)).
49. **In-app account deletion** (part of publishing to the stores: App
    Store guideline 5.1.1(v), Google Play). The signed-in Profile has
    **Delete account**: a confirmation that says what goes (events in the
    cloud and on the device, shares both ways), that it can't be undone,
    that the Google account stays and a Premium subscription is managed
    where it was bought (no purchase links in the apps); then, with
    progress, it empties the user's S3 folder (paged listing, batch
    DeleteObjects), calls the share API's new `DELETE /account` (grants
    both ways, the OCR service's accounts record, the Cognito identity),
    deletes the user's events on the device and signs out. Failures stop
    it, say what was deleted and offer Try again, the user still signed
    in. The share API gets a `byOwner` index and `DeleteIdentities`; the
    bucket's CORS allows `POST`. What can't be deleted (30-day old
    versions, backups, logs) and the deletion URL for Google Play (the web
    app's Profile; a static page proposed) are in the spec
    ([cloud sync](cloud-sync.md#deleting-the-account),
    [shared captures](shared-captures.md),
    [navigation](navigation.md#profile), [cloud OCR](cloud-ocr.md),
    [app stores](app-stores.md)).
50. **(Continuing 46) The upload key's App Links.** The upload key was
    created (`scripts/android-keystore.sh`, at the default path), backed up
    to the maintainer's Google Drive, set as the Release workflow's
    secrets, and its SHA-256 added to `assetlinks.json`, so release builds it signs open
    the sites' links in the app once deployed
    ([sharing](sharing.md#android-app-links), [app stores](app-stores.md)).
51. **Fix: the minute's sync pass stopped after signing out and back in**
    (found while adding account deletion). Sign-out cancelled the periodic
    timer but kept it, so the next sign-in didn't start a new one; now
    it's cleared, with a test ([cloud sync](cloud-sync.md)).
53. **Draft the Google Play and App Store listings** (part of publishing
    to the stores), in fastlane's layout for a later upload, without
    fastlane yet: [tabcam_store/](../tabcam_store) with the Play title,
    short and full descriptions and changelog; the App Store name,
    subtitle, description, keywords, promotional text, release notes and
    URLs; App Review notes (the test Google account is the maintainer's to
    provide); and draft Data safety, App Privacy, content rating,
    audience and category answers. `scripts/store-metadata-check.sh`
    checks the lengths ([app stores](app-stores.md#store-listings)).
54. **On the Text view, remove the Share text button (the event's Share
    in the app bar is enough), make Copy and Mark correct look alike, and
    make Mark correct a toggle.** Share text is gone. Mark correct is now
    a button like Copy, a toggle: tonal while off, filled and reading
    **Correct** while on ([tab recognition](tab-recognition.md#text-view)).
55. **Add auto-correct: a Lambda that does its best to correct the tab,
    for now from a button on the Text view; short button labels to fit the
    screen's width. It searches online, popular tab sites first, for the
    song's tab, works out the corrections and shows them per note in the
    text view, for the user to accept or not. Make the text view a text
    editor so the tab is easy to correct.** Chosen with the user: Claude
    with web search does the search and comparison, Premium only, and the
    editor gets an overtype mode. The cloud OCR service's API function
    answers `POST /autocorrect` (Premium; Claude `claude-opus-5-5` with
    web search and fetch, corrections by note id, checked against the
    reading); its timeout went to 300 s and it may read the Claude API
    key's secret. The Text view's buttons are now **Copy**, **Correct**
    and **Fix**; Fix asks for the song and shows the corrections per note
    to accept or reject. The editor has **Overtype** (on by default) and
    no keyboard suggestions. Store apps show Fix to Premium users only,
    as they show no upgrade offer ([auto-correct](autocorrect.md),
    [tab recognition](tab-recognition.md#text-view),
    [cloud OCR](cloud-ocr.md#infrastructure)).
56. **In the text editor, add + and − buttons that increment or decrement
    the number under the cursor, up to two digits (15 + → 16, 5 + → 6).**
    − and + under the Text view's buttons change the fret under the
    cursor by one, 0 to 99, keeping the columns
    ([tab recognition](tab-recognition.md#text-view)).
57. **If the document has other notations, such as lyrics and chords, add
    them to the text as well.** Reading keeps the page's notations with
    the tab, in their place: titles, section names, chord names (at the
    tab's columns) and lyrics, without web addresses, page numbers or
    stray marks. On the device for text and typeset tabs, and in the
    cloud, which now also reads the page off the staves with RapidOCR
    ([tab recognition](tab-recognition.md#notations-around-the-tab),
    [cloud OCR](cloud-ocr.md#transcription)).
58. **In the profile panel, add a language setting, for now English,
    Spanish and Portuguese; extract all the texts, translate them, make
    it work, verify and redeploy.** The app's texts moved to ARB files
    (Flutter's gen-l10n), translated to Spanish (neutral Latin American)
    and Portuguese (Brazilian). Profile has **Language**: the device's
    language by default, or one of the three, kept on the device and
    applied at once. iOS lists the three languages
    ([localization](localization.md), [navigation](navigation.md#profile)).
59. **Privacy policy and iOS privacy declarations** (part of publishing
    to the stores). A privacy policy page at
    https://tabcam.nu01.com/privacy (`tabcam_index/site/privacy/`,
    uploaded by `scripts/deploy.sh` as the object `privacy` and checked by
    its smoke test; served by the local index server too), based on what
    the code does; linked from the index page's footer and the Profile
    tab's About (**Privacy policy**). The contact email is a placeholder
    until the maintainer gives one. iOS: `ITSAppUsesNonExemptEncryption`
    false in `Info.plist`, and the app's privacy manifest,
    `PrivacyInfo.xcprivacy`, in the Runner target
    ([privacy](privacy.md), [platforms](platforms.md),
    [deploy](deploy.md), [navigation](navigation.md#profile),
    [app stores](app-stores.md)).
60. **Sign in with Apple on iOS** (App Store guideline 4.8: an app with
    Google sign-in must offer an equally private one). iOS offers **Sign
    in with Apple** above Google's button, per Apple's guidelines, on the
    Profile tab and the sign-in sheets, in builds with
    `TABCAM_APPLE_SIGN_IN=1` (a new dart-define; it also adds the
    `com.apple.developer.applesignin` entitlement through the git-ignored
    `Private.xcconfig`, so free Personal Team and CI builds, which can't
    sign it, have no entitlements). The app keeps one session at a time,
    with its provider; the Apple sign-in checks a hashed nonce, keeps the
    name and email Apple sends once, labels a private relay address "Apple
    ID (private email)", keeps its session in the app's private files
    until the token expires, and signs out a user who stopped using Apple
    ID with the app. Cognito gets Apple's token under `appleid.apple.com`
    (each provider its own identity); the identity pool trusts Apple with
    the new optional `AppleClientId` (the bundle ID); the share API takes
    Apple's tokens on the same routes under `/apple`, with an Apple JWT
    authorizer, the function checking each token's issuer matches its path
    and accepting `email_verified` as a string; the cloud OCR service
    verifies Apple's tokens too (`APPLE_CLIENT_ID`), Premium going by the
    verified address (a relay address has none; without Apple set up the
    app says "Premium needs Google sign-in"). Not on Android or the web
    (the web would need a Services ID, a domain and a return URL: a
    follow-up). Needs the paid Apple Developer Program, the App ID's
    capability and the stacks redeployed
    ([cloud sync](cloud-sync.md#sign-in-with-apple-ios-and-android),
    [shared captures](shared-captures.md#how-it-works),
    [cloud OCR](cloud-ocr.md#who-is-premium), [platforms](platforms.md),
    [app stores](app-stores.md), [tabcam_infra](../tabcam_infra/README.md)).
    Merged after account deletion and localization: Apple users delete
    their account under `/apple` too, and the sign-in buttons and Apple's
    messages are in English, Spanish and Portuguese.
61. **Add instructions to the README on how to install a release on iOS
    or Android.** The README has "Installing a release on a phone". For
    Android: the APK opened on the phone or installed with `adb install
    -r`, what to do about a key conflict, and that Google sign-in waits
    for the upload key's OAuth client. For iOS: the release's app is
    unsigned, so the tag is built and installed with the tester's own
    team, with Developer Mode and trusting the developer, and a free
    team's 7 days ([release](release.md#installing-a-release)).
62. **In the capture's pages, let every file type have a preview: a PDF or
    image as shown, a video or audio with a play / pause button, a link
    with a button to open it in a browser inside the app (mobile) or a new
    tab (web).** Events take two more kinds of page, **audio** (`mp3`,
    `m4a`, `aac`, `wav`, `ogg`, `oga`, `opus`, `flac`) and **pdf**, added
    with Add → Files (now offering those extensions too). On the event
    screen a PDF shows the document itself, scrolling and zoomable
    (`pdfrx`; its PDFium WASM, about 5 MB, loads on the web only when a
    PDF is shown); a recording shows a card with play / pause, a
    scrubbable progress bar and the time (played through `video_player`);
    a video has a play / pause button by its progress bar; a link's Open
    shows it in a browser inside the app on Android and iOS (falling back
    to the browser or the app that handles it), and in a new tab on the
    web. The library card has a PDF icon and a music note for events
    without images, and counts recordings and PDFs; Files (zip) holds
    them too; page MIME types come from one table. An unknown page kind
    from a newer app loads as an image. New texts in English, Spanish and
    Portuguese ([event screen](event-screen.md),
    [scanning](scanning.md#adding-to-an-event),
    [library](library.md), [sharing](sharing.md),
    [cloud sync](cloud-sync.md)).
63. **The app says Premium isn't active: make sure the rbacr integration
    is set up and the premium role is returned for julio@nu01.com.**
    rbacr was fine (`allowed: true` for `tabcam`/`premium`, through the
    service's token). The iPhone's calls never reached it: the identity
    pool refused the app's Google tokens ("Token is not from a supported
    provider"), because an iOS token's `azp` is the iOS client and the
    pool's built-in Google login takes one client ID; sync failed on iOS
    the same way. Both pools now trust Google through an IAM OpenID
    Connect provider listing the web, iOS and local web clients
    (`identity.yaml`: `GoogleAppClientIds`, `GoogleProviderArn`),
    deployed. On the iPhone, `/account` answers premium and sync uploads.
    Existing users got new identity IDs (nothing was stored yet). Android
    clients are to add to the list ([cloud sync](cloud-sync.md#googles-token),
    [app stores](app-stores.md), [tabcam_infra](../tabcam_infra/README.md)).
64. **Make profiles work like in Presence: an authenticated user without a
    profile gets one, in the same style (unguessable, adjectives and an
    animal at the end); identities can be added to the profile; the
    profile has the sum of all roles from all identities.** Chosen with
    the user: the profile owns the data (one Cognito developer identity per
    profile), accounts join with a link code or automatically by the same
    verified address, and the profile API is in the share API. The share
    API makes, finds and links profiles (`/profile` routes; profiles,
    subjects and link-code tables; Presence's word lists), its sharing
    works by profile, and a profile's roles are its addresses' rbacr roles
    together; the identity pool gets the developer provider
    `login.tabcam.profiles`; the cloud OCR service checks Premium by
    profile. The app gets its folder through the profile, moves the user's
    captures when their folder changes, and shows the profile, its roles
    and Linked accounts on the Profile tab
    ([profiles](profiles.md), [cloud sync](cloud-sync.md),
    [shared captures](shared-captures.md), [cloud OCR](cloud-ocr.md),
    [navigation](navigation.md#profile)).
65. **In the capture view, where there are the Scan, Photos, Files and Link
    options, add a Document option for PDFs, first in the Add list; leave
    Scan as is.** Capture's Add list starts with **Document** ("PDF
    files"), which picks PDFs only and makes an event of them, like Files;
    Scan is unchanged. In English, Spanish and Portuguese
    ([navigation](navigation.md#capture)).
66. **When a PDF is added, just like an image, try to parse it into text,
    and present it as a tab.** PDF pages are read by themselves into the
    text tab: their text where they have one (PDFium through `pdfrx`, the
    characters' positions laid out as a text tab, chords and lyrics kept),
    else their pages rendered and read by the device's OCR. Found on the
    way: a read could overwrite pages added while it ran (it saved an old
    copy of the event); it now writes only its text onto the event as it
    is, adding pages does the same, and pages changed during a read are
    read again ([tab recognition](tab-recognition.md#pdfs)).
67. **When the app is reloaded, keep it on the same page it was.** The app
    remembers, on the device, the tab and the event open (Text view or
    pages, and the page), and reopens there after a reload or a restart;
    a capture's link at launch wins
    ([navigation](navigation.md#coming-back-where-the-user-was)).
68. **I still don't see the button for adding PDFs: make sure everything is
    merged and deployed.** The Document option was on the Capture tab
    only (and the web was still the release from before it). The open
    capture's **Add** menu now has **Document** right after Scan pages, the
    menu scrolls (five items overflowed a small phone), and a release
    puts it all on the web ([scanning](scanning.md#adding-to-an-event)).

## 2026-10-12

69. **PDF reading doesn't work: a PDF uploaded wasn't read, and Read again
    does nothing. Fix it, check the logs; PDFs must be scanned just as if
    they were photographed.** The logs showed the PDF was a scan (an image,
    no text), uploaded on the web, signed in with an address that isn't
    Premium: the web has no OCR, and the cloud read photos only, so it was
    "no tab found" every time. The cloud OCR service now reads PDFs (each
    page rendered and read as a photo; the rule takes `.pdf`); Premium
    users' PDFs are read by their text on the device, else in the cloud;
    on the web without Premium, a scanned PDF says what it needs. The
    user's PDF turned out to be a handwritten tab on drawn staff lines,
    which the cloud's engines never read (photographed either): Claude
    (vision) now reads the pages the engines find no tab on, with the
    Claude API key in Secrets Manager (`tabcam/anthropic-api-key`, read
    by name: on as soon as it exists). Read again now makes the cloud read
    every page again, and shows while the text is on its way
    ([tab recognition](tab-recognition.md#pdfs), [cloud OCR](cloud-ocr.md)).
70. **Let users reorder the files they add.** The event screen's app bar
    has **Reorder** (with more than one page, when the user can edit):
    a sheet lists the pages with a thumbnail or icon and what each is,
    dragged by their handles into a new order, saved at each drop and
    synced; photos and PDFs moved are read again in their new order. With
    the images hidden, only the other pages are listed and the images
    stay put. In English, Spanish and Portuguese
    ([event screen](event-screen.md)).
71. **When a user renames a capture, just make it a name, no artist and
    song name; let the user name it whatever.** The rename dialog has one
    **Name** field instead of Song and Artist; what the user types is the
    title, and renaming clears the artist
    ([library](library.md#events)).
72. **Embed a YouTube player when the link added is for a YouTube video;
    if the video can't be seen for any reason, just show the link and
    open it in a new tab.** A link page for a YouTube video gets
    **Play**, which plays it in YouTube's embedded player
    (`youtube_player_iframe`, youtube-nocookie.com) on the web, Android
    and iOS, from the link's start time. Any failure (YouTube's error,
    the page not loading, a 20-second timeout, no web view) goes back to
    the link card, which says the video can't be played here and opens
    it in a new tab ([event screen](event-screen.md),
    [platforms](platforms.md)). The privacy policy names YouTube, which
    is contacted only on Play ([privacy](privacy.md)).
73. **Improve the capture page: keep the title, Rename and Clone; one
    Share, not Share and Share with people; take out the Scan toggle and
    make the first tool the capture's files, then Text, then Add; Rotate
    and Delete are fine but confusing. Home shows every capture; a capture
    shows the list of its files (with the one just scanned) and a preview
    of each; a tap on a file opens only that file.** The event screen is
    now a list of its files, each with a preview (the image itself, or a
    badge for videos, PDFs, recordings and links) and a name ("Page 2",
    "Video 1", a link's title); after Add it scrolls to the new files. A
    tap opens the file alone on a new **file screen**, which has the
    view (Original ↔ Scan, now per image), Rotate and Delete (back to the
    list after a delete). The bottom tools are **Files**, **Text** and
    **Add**; the Original/Scan toggle, Rotate and Delete left the capture
    screen, and so did the pager and its "2 / 5". The app bar has one
    **Share**; **Share with people** moved into its sheet, right after
    Link. A reload reopens the file that was open. In English, Spanish
    and Portuguese ([event screen](event-screen.md),
    [sharing](sharing.md), [shared captures](shared-captures.md),
    [hidden images](hidden-images.md), [page filters](page-filters.md),
    [navigation](navigation.md#coming-back-where-the-user-was)).
74. **Remove the Claude key for now; read it without an LLM first, as well
    as possible.** No key had been stored; Claude's reading is now off
    unless switched on (`VISION_FALLBACK=1`). The cloud OCR service reads
    tabs on drawn staff lines with its engines: staves found, lines erased
    under the numbers, each number read on its own and set on its string,
    in columns; notations read at full size; scanner watermarks dropped.
    Printed tabs on drawn lines read exactly; the user's handwritten page
    reads about two notes in three
    ([cloud OCR](cloud-ocr.md#transcription)).
75. **On the text recognition, make the lines (strings) align as well as
    possible, so a chord shows properly, and all the same length, ending
    together.** On the device, when ML Kit says where each character is
    (its symbols), a text tab's staff is laid out on one grid: every
    character at the column its x implies, from the staff's start in its
    character pitch, so dashes OCR dropped or doubled no longer shift the
    notes after them; every line is padded to the longest, chord names
    placed on the same grid. In the cloud, a staff's lines are measured
    from one start and column width (medians across the staff), and end
    together (trailing dashes trimmed, all padded to the staff's width)
    ([tab recognition](tab-recognition.md#text-tabs),
    [cloud OCR](cloud-ocr.md#transcription)).
76. **Always let users rename added content: captures, files, links, all of
    it.** Every file of a capture (photos, scans, PDFs, recordings, videos,
    links) has a name the user can change: **Rename file** on each row of
    the capture's list (or a long press) and on the file screen's title;
    files added are named after their file name; an empty name goes back
    to the default. Captures renamed as before. Not on captures shared
    read only. In English, Spanish and Portuguese
    ([event screen](event-screen.md)).
77. **When sharing, just copy the link to the capture, no options or extra
    text.** Share copies the capture's link to the clipboard and says "Link
    copied"; the share sheet (Link, PDF, Text, Files) and the exports are
    gone. Share with people, which was in that sheet, has its own button
    in the capture's app bar ([sharing](sharing.md)).
78. **Present the login on the home screen.** Signed out, Home has a Sign
    in card above the captures, with the sign-in buttons; it goes once
    signed in ([library](library.md)).
79. **Make the Fix button also re-format the tab so that the lines
    (strings) are correctly matching.** Fix first lines the tab up, for
    everyone, on the device: each staff's strings named and the bars lined
    up measure by measure, every string ending together, everything else
    untouched; then, with Premium, the online check as before
    ([auto-correct](autocorrect.md#lining-the-tab-up)).
80. **Verify that the Share button immediately copies the share link to the
    clipboard: the URL only, no options or extra text.** It did, but after
    an await (the sign-in check, even signed in) and the start of a sync:
    now, signed in, the copy is the first thing on the tap, the sync after.
    Tests check the clipboard holds exactly `https://tabcam.nu01.com/app/?c=<id>`
    right after the tap, with no sheet, from the capture and from a Home
    card ([sharing](sharing.md)).
81. **Make the home screen a simple welcome / login only, and offer the
    features only to logged-in users.** Signed out (in a build with
    sign-in), the app is a welcome: TabCam, what it does, the sign-in
    buttons, Privacy policy. Home, Capture and Profile come once signed in;
    signing out goes back to the welcome. The Home sign-in card is gone;
    the sign-in text no longer says capturing works signed out
    ([navigation](navigation.md#signed-out-the-welcome), [library](library.md),
    [cloud sync](cloud-sync.md#signed-out)).

## 2026-10-13

82. **Keep #75 (the welcome), but let anonymous users open a shared
    capture in read only mode.** A capture's link now carries a key
    (`…/app/?c=<id>&k=<key>`), made the first time its owner copies it and
    recorded by the share API; anyone holding the link opens the capture,
    read only, signed out (instead of the welcome, with **Sign in**) or
    signed in without it being shared with them. The share API swaps the
    key for read-only credentials to that capture's folder, without a
    token ([sharing](sharing.md#opening-a-link),
    [shared captures](shared-captures.md#how-it-works),
    [navigation](navigation.md#signed-out-the-welcome)).
84. **Let users rename a file, just beside the delete button.** The file
    screen's Rename moved from a pencil in its app bar to a **Rename** tool
    along the bottom, just before Delete (off, like Delete, on a capture
    shared read only); tapping the file's name still renames it, and the
    list keeps its pencil and long press
    ([event screen](event-screen.md#file-screen)).
85. **Generate a preview of the capture to show on the list instead of a
    blank.** A Home card without an image thumbnail showed only an icon.
    Now it shows a preview: a PDF's first page, rendered (and kept in
    memory); else the text tab's first lines in miniature, monospaced;
    else a video's play badge; else a link's title and host; the icon only
    when there's nothing else (a recording alone). A small badge in the
    corner says what else the capture holds. Hidden images are never shown
    ([library](library.md), [hidden images](hidden-images.md)).
86. **Make added links / YouTube open in a new tab on web and on the
    browser on mobile.** Links open outside the app: a new tab on the
    web; the browser on Android and iOS (or the app the system hands
    them to, such as YouTube), no longer a browser inside the app. A tap
    on a link in a capture's list opens it straight away; its chevron
    (**Details**) shows it on the file screen, whose **Open** does the
    same. YouTube's embedded player is gone (and with it
    `youtube_player_iframe` and the web views): a YouTube link shows a
    video icon and opens like any link. The privacy policy no longer says
    YouTube is loaded in the app ([event screen](event-screen.md),
    [platforms](platforms.md), [privacy](privacy.md)).
87. **If you can, make the reorder in the same capture list view, not a
    separate one.** The capture's files list reorders in place: editable,
    with more than one file, each row has a drag handle (in place of the
    arrow) that moves it in the list, saved at each drop as before; tap,
    the rename pencil and long press still work. The Reorder button and
    its sheet are gone (and their "Drag to reorder", "Photo" and "PDF"
    strings). With the images hidden, only the other files move and the
    images keep their places ([event screen](event-screen.md#reordering)).
88. **I renamed a file in a capture (from "PDF 1") but its link still
    shows "PDF 1": make renames and changes effective in captures as soon
    as they're made, on devices and shares.** A file's name was dropped
    whenever an event was read back (only links kept it): the cloud had
    the new name, but other devices, people it's shared with, link
    viewers and the same device after a restart showed the default.
    Names are now kept for every kind of file. Sync looks for changes
    every 10 seconds while the app is in front (every minute behind) and
    at once when it comes back to the front; a capture opened by its link
    reads it again every 10 seconds and on coming back to the front
    ([cloud sync](cloud-sync.md#when-and-how),
    [sharing](sharing.md#opening-a-link)).
89. **Do the best possible locally to make a thumbnail of each added file or
    link; if one can't be made, use a generic one.** The capture's file
    list now shows a PDF's first page and a video's first frame, drawn on
    the device; images already showed themselves. Recordings, and links
    (whose picture would have to come from the internet, YouTube's
    included), keep their generic badges, as does any file that can't be
    drawn ([event screen](event-screen.md)).
90. **Tabs are misaligned: make sure the lines finish together, add or
    remove dashes appropriately, fixed-width font and a little bigger.**
    The stored tabs were aligned (each staff's strings the same length,
    since reading aligns them on one grid); the font wasn't fixed-width
    on the web, which has no system monospace font. Tabs now show in
    Roboto Mono, shipped with the app, a little bigger (15 px in the Text
    view, from 13; 17 px in the review, from 15)
    ([tab recognition](tab-recognition.md)).
91. **Add search to the home screen.** Home has a search field above the
    cards that keeps the captures matching every word typed, in their
    title, artist, text tab, file names, links or who shared them, case
    and accents aside; with no match it says so, with Clear search. In
    English, Spanish and Portuguese ([library](library.md)).
92. **Let users just drag files to the capture view to add them.** Files
    dragged onto the Capture tab make a new capture, and dragged onto a
    capture's screen are added to it, as the Files button would, with
    "Drop files to add" shown while they're over it. On the web, desktops
    and Android (`desktop_drop` 0.8.4), not iOS
    ([navigation](navigation.md#capture), [event screen](event-screen.md)).
93. **When a link is shared, let it have the title and description of the
    capture instead of "TabCam" and the app's description.** Chat apps'
    crawlers asking for a capture's link are sent to its preview page,
    from the share API: the capture's title (and artist) and what it
    holds, as Open Graph tags, read with the link's own read-only
    credentials; a wrong key previews as TabCam. People still get the
    app ([sharing](sharing.md#link-previews)).
94. **In the capture's file list, add a mini player to video and audio
    files so they can be played right from the list; make the rows
    taller.** Videos and recordings have a play / pause button in their
    row and play there, one at a time (a video in its thumbnail), with a
    scrubbable progress bar and the time under the name. Rows are taller:
    80 px previews (from 64), 10 px padding (from 4)
    ([event screen](event-screen.md)).
95. **Protect user privacy per profile: make sure all data is encrypted,
    with keys generated when the profile is created; asymmetric keys; shares
    must still work, even anonymous ones.** Encrypting with the private
    key (for others to decrypt with the public one) would hide nothing, so
    it's the other way round: each capture's own AES key, wrapped with the
    profile's public key. The keys are kept by the API in DynamoDB, the
    private ones wrapped by a single KMS key (about $1 a month, against $1
    a profile a month for a KMS key each). Stage 1, the keys: the KMS key
    and the keys table (deployed with the share API), every profile's key
    pair, the public key in `GET /profile`, content keys unwrapped for the
    owner, people it's shared with and link holders, and link previews of
    sealed captures ([encryption at rest](encryption.md)).

## 2026-10-14

1. **Tag every AWS resource with `project` and `tenancy`, so Cost Explorer
   can split cost by product and stage.** Every stack is deployed with the
   stack tags `project=tabcam` and `tenancy` (`GA` for `tabcam-web`, `RC`
   for `tabcam-rc-web`, `dev` for `tabcam-identity-local`, `shared` for
   the rest), which CloudFormation copies to the resources; the deploy
   roles may now also remove certificate tags
   ([deploy](deploy.md), [tabcam_infra/README.md](../tabcam_infra/README.md)).
2. **Cut TabCam's AWS cost: drop the Route 53 health check, move the rbacr
   token to SSM Parameter Store, and run the cloud OCR on arm64 if it
   can.** The sites' Route 53 health check, its `HealthCheckStatus` alarm,
   the SNS health topic and its email subscriptions, the
   `HealthNotificationEmails` parameter, the `IsRc` condition, the
   `HealthCheckId` and `HealthTopicArn` outputs and the `LanguageExtensions`
   transform are gone from `site.yaml`, with `TABCAM_HEALTH_EMAILS` in
   `scripts/deploy.sh`, the deploy workflows and `.env.example`; the
   `nu01-monitor` stack (nu01 repository) polls both sites'
   `/app/version.json` every 5 minutes instead. The deploy roles keep the
   permissions to delete the old resources until the next GA deploy. The
   rbacr token moved from the Secrets Manager secret `tabcam/rbacr-token`
   to the SSM SecureString `/tabcam/rbacr-token` (standard tier, `aws/ssm`
   key: free): the share API and `tabcam-ocr-api` read it with
   `ssm:GetParameter` (decrypted, once per container; env
   `RBACR_TOKEN_PARAMETER`, stack parameter `RbacrTokenParameterName`),
   and the deploy scripts check it exists without reading its value. The
   OCR functions stay x86_64: PaddlePaddle 3.3.1 has no Linux ARM wheel on
   PyPI, and the one on Paddle's own index aborts loading the PaddleOCR
   models in an arm64 build
   ([deploy](deploy.md), [cloud OCR](cloud-ocr.md), [profiles](profiles.md),
   [tabcam_infra/README.md](../tabcam_infra/README.md)).

## 2026-10-16

1. **Add a "cam" feature: from the capture view, open the camera with the
   tab's OCR text along the bottom, one line of the neck (a "neckline")
   at a time, with Rec and Play, so guitarists can record themselves
   playing along. Any key moves to the next neckline; Backspace, back
   and up to the one before.** The event screen has a fourth tool,
   **Cam**, opening the camera view
   ([`PlayAlongScreen`](../tabcam_app/lib/capture/play_along_screen.dart)):
   the front camera first, the text tab cut into necklines (each staff
   with the chords and labels right above it,
   [`necklines`](../tabcam_app/lib/recognition/necklines.dart)) shown
   one at a time, shrunk to the screen's width. Any key goes to the next
   neckline; Backspace, ←, ↑ and Page Up to the one before (modifiers and
   Escape alone do nothing); a tap and the arrows beside it too. **Rec**
   records video and sound and adds the take to the capture as a video
   named "Take N"; **Play** plays the last take back with the necklines
   turning where they did while recording. Off on captures shared read
   only or opened by link. iOS got `NSMicrophoneUsageDescription`; the
   strings are in English, Spanish and Portuguese
   ([Cam](cam.md), [event screen](event-screen.md),
   [platforms](platforms.md)).
2. **Rename to "tabcam" everywhere: TabScan is gone. Files, dirs,
   domains, repo, everything.** The app is TabCam: the code and docs
   (directories `tabcam_*`, the `tabcam_app` package, `TABCAM_` settings,
   `com.nu01.tabcam` on Android and iOS), the repository
   (`prodbytes/tabcam`), the domains (`tabcam.nu01.com`, its own zone),
   a new Google Cloud project (`tabcam-nu01`) with its own sign-in
   clients, and every AWS stack made again under `tabcam-` names: a new
   bucket, identity pool (provider `login.tabcam.profiles`), share API
   (and KMS key), OCR service and deploy roles. Each profile's folder
   moved to its identity in the new pool, with the tables
   ([migrate-to-tabcam.py](../scripts/migrate-to-tabcam.py)); rbacr has a
   `tabcam` system mirroring `tabscan`. The old domains redirect
   ([deploy](deploy.md#the-old-domains)). Apps installed as TabScan don't
   update to TabCam: it's installed anew (what synced comes back at
   sign-in).
3. **Let the user turn the tab with head gestures: nod up or right for the
   next neckline, down or left for the one before; make it a strong
   gesture so it doesn't trigger by accident.** Cam's frames go to ML
   Kit's face detector (`google_mlkit_face_detection`, on the device;
   Android and iOS). A `NodDetector` counts a gesture only when the head
   swings at least 20° up or down, or 25° sideways, from where it rests,
   and returns to rest within a second (held away longer, like looking at
   the fretboard, it's no gesture), with 0.8 s between gestures. A face
   icon in Cam's app bar switches them on (the default) and off, green
   while a face is seen. Not on the web. The privacy policy now says
   faces are detected on the device, only the head's angle used, nothing
   saved or sent
   ([Cam](cam.md#head-gestures), [platforms](platforms.md),
   [privacy](privacy.md)).
4. **Make the "Text" icon in the capture's bottom bar show the reading
   status: normal when the text is ready, disabled when no text was found
   or it was deleted, a spinner while processing.** The Text tool (an
   `EventTool` with `working` and `dimmed`) shows a spinner while
   `AutoReader` reads the capture (on the device or in the cloud), the
   usual icon with a text tab, and is greyed out without one. It stays
   tappable when greyed, so the Text view can still say why and offer
   Read again or Sign in ([event screen](event-screen.md)).
5. **Show the recorded videos on the capture page by themselves.** Back
   from Cam with new takes, the capture shows its file list (even if it
   was on the Text view), scrolled to the end, where the takes are
   ([Cam](cam.md), [event screen](event-screen.md)).
6. **Make Cam's head gestures work in the web build (the user tried it in
   the browser and nothing happened).** The web now has a
   `WebHeadTracker` (`web_head_tracker.dart`, conditionally imported):
   MediaPipe Tasks Vision's Face Landmarker (`@mediapipe/tasks-vision`
   0.10.21 from jsDelivr, the `face_landmarker.task` model from Google's
   storage), loaded only when Cam opens with gestures on, reads the
   camera preview's `<video>` about 10 times a second; the head's pitch
   and yaw come from its facial transformation matrix (`headAngles`,
   tested with made-up matrices) and feed the same `NodDetector`, so the
   gesture stays as strong. If MediaPipe can't load, it's logged and Cam
   works on without gestures. Recording on the web no longer asks the
   camera for frames it can't stream, and the face icon now also stops
   the tracker's own watching. The privacy policy (dated October 16,
   2026) says the web detects faces in the browser with MediaPipe, its
   code and model downloaded from jsDelivr and Google
   ([Cam](cam.md#head-gestures), [platforms](platforms.md),
   [privacy](privacy.md)).
7. **Add a delete button in the file list to delete a file.** Each row
   of the capture's file list has **Delete file** (a bin, after the rename
   pencil): it asks to confirm, then deletes the file; the last file
   stays, as on the file screen. Not on captures shared read only
   ([event screen](event-screen.md)).
8. **Put the tab overlay into the recorded video, on every device, with no
   server-side spend; Flutter can run platform-specific code for each
   platform.** Cam's takes now have the tab in them: each neckline as a
   band along the bottom of the video while it showed. The bands are
   drawn by the app (`renderBand`); the web records the camera and the
   band onto a canvas as it goes (`MediaRecorder`); Android (Media3
   Transformer) and iOS (AVFoundation) burn them in after recording,
   through the method channel `tabcam/take_overlay`. All on the device;
   a failure keeps the take as recorded ([Cam](cam.md#the-tab-in-the-take),
   [platforms](platforms.md)). Also: the iOS `Podfile.lock` was brought up
   to date with the face detection pod head gestures added.
9. **"The spinner icon is showing for a tab that was already read. Only
   read tabs that were not yet read or that were forced to re-read by
   clicking the icon when it is already ready."** Then: **"icon seems to
   be spinning forever, make it sure it fails after 2x the lambda
   timeout"**, **"make it 3x"**. The cause: with Premium, `AutoReader`
   set `inCloud` and nothing ever cleared it, as the cloud's text comes
   with sync, which it didn't watch, so the Text tool spun on a read tab.
   Now the reader watches every library change (sync's too) and drops the
   state once the event has a text tab or is gone, and `CloudOcr`
   tells it when an event's results are collected (`collected`). Pages
   reordered, rotated, added or deleted no longer re-read an event that
   has a text tab; events without one are read as before. Tapping the
   Text tool on the Text view with a tab asks "Read the tab again?"
   (Cancel / Read again; en, es, pt) and reads it again with the
   spinner. Read again in the cloud now waits for every page's new
   result (by ETag) and replaces an auto text, on-device ones too (it
   used to skip events whose pages it had filled). A read still waiting
   after `cloudReadTimeout`, 3 x the OCR Lambda's 15-minute timeout
   (45 minutes), fails, with Read again; a text that comes later still
   fills in ([tab recognition](tab-recognition.md#reading-by-itself),
   [event screen](event-screen.md), [cloud OCR](cloud-ocr.md)).
10. **The tab overlay isn't in the recorded video: make sure it is.** The
   web recorder was checked end to end (the real Cam screen in Chromium,
   Firefox and WebKit with a fake webcam, the saved take's frames read
   back): the band is there. Where it can't be added, Cam no longer
   stays silent: a message says the take was recorded or saved without
   the tab, and why; a band image that fails is drawn as plain text
   instead. The band is smaller (a six-string staff takes about a third
   of a landscape take) ([Cam](cam.md#the-tab-in-the-take)).
11. **When the app loads, data takes a long while to come: make it
   quicker, perhaps by getting a list first, showing it with a loading
   icon, then fetching.** A pass downloaded each new capture's files one
   after another before showing it, one capture at a time. Now it fetches
   the changed `scan.json` files 8 at a time and shows the captures at
   once; their files download after, 4 at a time (pictures and PDFs
   first, newest captures first), each preview showing a spinner until
   its file is here, and whatever needs a file waiting for it. A file that
   fails to come is asked for again at the next pass
   ([cloud sync](cloud-sync.md#listed-first-files-after),
   [platforms](platforms.md)).
12. **Home shows no tabs though there are some: show a loading icon while
   a signed-in user's captures load, or just the welcome without features
   signed out.** Signed in with nothing on the device, Home now shows
   "Loading your captures…" with a spinner until the first sync pass since
   signing in ends (`CloudSync.firstPassDone`), then the captures (or "No
   tabs yet" if there are truly none); a failed first pass says so, with
   Try again. Signed out was already only the welcome and sign-in
   ([library](library.md)).
13. **Add a button to download each file, and one to download all, on
   top.** Each file row has **Download** (its file under its name in the
   list; scanned `img` pages as `.jpg`), and the app bar **Download
   all**: `<title>.zip` with every file, the text tab and the links
   (`lib/export/download.dart`). The browser downloads; Android and iOS
   show the system's "save as" (`file_picker`). On a phone narrower than
   600 px, Rename, Download and Delete move into a ⋮ menu on each row
   ([event screen](event-screen.md)).
14. **Optimize the OCR Lambda: increase its memory and scan until it stops
   improving, to find the sweet spot of cost and performance.** Measured
   `tabcam-ocr` on a made-up riff page at 2048, 2560 and 3008 MB (the
   account's cap): 144 s, 106 s and 97 s a page warm, $4.79, $4.40 and
   $4.77 per 1000 pages. It now has **2560 MB** (was 3008 MB): the
   cheapest, 8% slower than the cap. Set live with the CLI and in
   `tabcam_infra/ocr.yaml`, so the next deploy keeps it; the spec's
   timeout (15 min) and per-page time were corrected too
   ([cloud OCR](cloud-ocr.md#memory)).
15. **In the text edit screen make the buttons be Copy, Fix, Rescan and
   "Verified" on the first line; on the second line, add borders to make
   clear those are buttons, and make the checkbox a toggle button.** The
   Text view's top line is now **Copy**, **Fix**, **Rescan** (new: Read
   again from the Text view, as the Text tool tapped again) and
   **Verified** (was Correct; the same `tabTextCorrect` mark), compact and
   on one line, scaled down rather than wrapped on a narrow phone. The
   editing tools under it are outlined: − and + as outlined icon buttons,
   and Overtype, which was a checkbox, a toggle button, filled while on
   ([tab recognition](tab-recognition.md#text-view)).
16. **Add ++ and −− buttons to move the note up / down one line (string),
   cycling round past the first or last line.** The Text view's editing
   tools have **++** (up a string) and **−−** (down), after − and +: the
   note under the cursor moves to the next string with room at its column,
   cycling within its staff, leaving dashes behind (`moveNote` in
   `lib/screens/tab_editing.dart`;
   [tab recognition](tab-recognition.md#text-view)).
17. **The Rescan button doesn't seem to work: when pressed, re-scan all the
   original PDFs and images in the capture, delete the current content and
   replace it with the new content.** Rescan ran Read again, which keeps
   a text the user edited (Fix counts) or marked verified, so it seldom
   changed anything. It now asks "Rescan the pages?", empties the text
   tab and clears Verified, then reads every photo and PDF again (on the
   device, or every page in the cloud with Premium), and the new reading
   fills it; meanwhile the Text view shows how the read stands
   ([tab recognition](tab-recognition.md#text-view)).
18. **"The text recognition is still not accurate. Research and test
   pre-processing techniques to make it as accurate as possible. Test with
   the two songs already uploaded."** Then: **"try this one too, black
   magic woman intro by santana"**. The cloud OCR was measured on the
   bench's three pages (a photographed printed tab with red ink, a
   scanned handwritten page, a handwritten intro in fine pen), scoring
   each note by string, order and column, and changed where a technique
   paid: what's still red after the red channel becomes paper; a page
   tilted half a degree or more is levelled; rows of flat marks that
   aren't evenly spaced aren't dash lines, and fewer than four lines
   aren't a staff (a broken drawn line had sent a handwritten page down
   the text-tab path); each note's column comes from its ink on the strip,
   not from the dashes the engines read; on drawn staves, broken lines are
   bridged, the band reaches higher above the staff, cut digits are joined,
   flat strokes and string numbers are left out, PaddleOCR reads the
   crops first, a fine pen's crops are made bolder, and `$`, `C` and
   "5(6)5" are read. Notes read: 77.5% → 90%, 0% → 82.9% and
   42.9% → 88.1%. Strip contrast (CLAHE), sharpening, Sauvola
   binarization, upscaling, dash erasure, label cropping and other page
   sizes were tried and scored worse ([cloud OCR](cloud-ocr.md#verified)).
19. **"Could we highlight in red the notes that were identified with low
   confidence and likely wrong?"** The cloud OCR now says which notes it
   was unsure of (`doubts` in each page's result): on tab lines, a note
   neither other engine read the same; on drawn staves, a number
   PaddleOCR scored under 0.8, or only RapidOCR read. Measured on the
   bench: 21 of 158 notes doubtful, 9 of them wrong, catching 9 of the 16
   wrong notes (most of the rest only a vibrato's length). The app keeps
   them with the text tab (`tabTextDoubts`, synced) and the Text view shows
   them in red, with a line saying what red means, until the user changes
   the note or marks the text Verified. On-device reads have none
   ([cloud OCR](cloud-ocr.md#doubtful-notes),
   [tab recognition](tab-recognition.md#text-view)).
20. **In the camera view add a sidebar to play one of the audio, video or
   link files in the capture while recording; the space bar pauses and
   plays the file or link, in a separate frame above, so the user can
   play while recording.** Cam has **Play along** in the app bar: a
   sidebar of the capture's recordings, videos and links; the one tapped
   plays in a frame above the camera while the user plays and records,
   and the space bar pauses and plays it (instead of turning the tab).
   A YouTube link plays in YouTube's embedded player, any other page
   shows in the frame (on Android and iOS in a web view, the new
   `webview_flutter` dependency); a link straight to a sound or video
   file plays in the app. The privacy policy now says a link chosen in
   Cam shows inside TabCam ([cam](cam.md#playing-along-with-a-file),
   [privacy](privacy.md)).
21. **Make the head icon in the camera view use the primary theme colour,
   not green.** Cam's head gestures icon is now in the theme's primary
   colour (was green) while it sees a face ([cam](cam.md#head-gestures)).
22. **Get TabCam ready for App Store submission: turn on Sign in with
   Apple for store builds, and have Delete account revoke the user's
   Apple tokens (guideline 5.1.1(v)).** Deployed `tabcam-identity`
   (the pool now takes `appleid.apple.com` for `com.nu01.tabcam`),
   `tabcam-ocr` and `tabcam-share-api` with Apple, and set
   `TABCAM_APPLE_SIGN_IN=1` in the maintainer's `.env`. Deleting an
   account signed in with Apple now shows Apple's sheet once more, at the
   share API's step, and sends its fresh authorization code with
   `DELETE /apple/account`; the share API trades it for the user's tokens
   with a client secret signed by TabCam's Sign in with Apple key (the new
   SSM SecureString `/tabcam/apple-sign-in-key`, `{teamId, keyId,
   privateKey}`, which only its function may read), checks they're the
   caller's, and revokes them at `appleid.apple.com/auth/revoke` before
   deleting anything. Until the key's parameter exists, accounts are
   deleted without revoking ([cloud sync](cloud-sync.md#revoking-apples-tokens),
   [shared captures](shared-captures.md#how-it-works),
   [app stores](app-stores.md#status)).
23. **Produce an App Store distribution build and upload it to App Store
   Connect.** `make ipa` archives and exports the signed App Store build
   (automatic signing for the paid team; Xcode made the Apple Distribution
   certificate and the App Store profile, with Sign in with Apple), and
   `scripts/ios-upload.sh` uploads the archive with `xcodebuild
   -exportArchive` (destination `upload`, as Xcode's signed-in account or
   an App Store Connect API key). The first upload waits for the app's
   App Store Connect record ([app stores](app-stores.md#ios-distribution),
   [release](release.md#make)).
24. **Produce all the store graphics needed to publish: Play's icon,
   feature graphic and phone screenshots; the App Store's 6.9" iPhone
   screenshots, and the 13" iPad's if the app runs on iPads. The real app's
   UI with made-up riffs only.** The app runs on iPads
   (`TARGETED_DEVICE_FAMILY` 1,2), so both sets are there. A widget test
   outside `flutter test`'s folder
   ([store_screenshots_test.dart](../tabcam_app/screenshots/store_screenshots_test.dart),
   run by `bash scripts/store-screenshots.sh`) pumps the real app, signed in
   with a fake account (`ana@example.com`, shared with
   `sam@example.com` and `lee@example.com`), over ten made-up captures
   (printed pages of made-up riffs, drawn by the test), with real fonts
   (Roboto; San Francisco for iOS) and a drawn status bar, and writes six
   screens per device at the stores' pixel sizes, RGB without alpha: the
   Text view, a page with the Tab filter, Home, Capture, Cam (a drawn
   guitar neck as the camera's picture) and Share with people; plus Play's
   512 px icon (RGBA) and a 1024 x 500 feature graphic.
   `scripts/store-metadata-check.sh` now also checks each image's size and
   alpha ([app stores](app-stores.md#store-graphics)).
25. **Make the store copy accurate to the app (App Store guideline 2.3),
    set up fastlane, and upload the App Store listing and the TestFlight
    build.**
    - The copy ([tabcam_store/](../tabcam_store)): signing in first
      (Apple or Google on iOS, Google on Play; no scanning signed out),
      Verified (not "Mark correct"), Fix lining the tab up, the tab
      editing tools, Cam (the tab under the camera, takes, playing
      along), search, the zip download, Share copying a read-only link
      (no PDF, text or zip sharing; the link does give access), Share
      with people; dropped: hiding photos (no control any more),
      swiping pages, a link opening only for the people shared with.
      Premium only as cloud transcription, never offered for sale. The
      review notes: the welcome's Sign in with Apple and Google, any
      account working, no sample page attached, Cam among the steps.
      [data-safety.md](../tabcam_store/data-safety.md): data required
      (the app needs signing in), Sign in with Apple's data, audio
      (recordings, Cam's takes), the read-only link, Cam's play-along web
      view (no unrestricted web access, with the caveat), Apple's newer
      age rating questions.
    - The App Store metadata moved to `tabcam_store/ios/metadata/` (deliver
      takes every folder of its metadata path for a language);
      `scripts/store-metadata-check.sh` and `.gitignore` follow.
    - fastlane ([tabcam_store/fastlane/](../tabcam_store/fastlane/Fastfile),
      `scripts/store-upload-ios.sh`) with the App Store Connect API key
      from the environment: `metadata` (deliver: metadata, screenshots,
      categories, copyright, age rating, `ios/age-rating.json`; no
      binary, no submission) and `testflight` (export compliance, the
      internal group Internal, the account holder).
    - Run against App Store Connect: version 0.1.202610161805 has the
      listing, the 6 iPhone 6.9" and 6 iPad 13" screenshots, Music and
      Productivity, the copyright and the age rating; build 1792173901 is
      in Internal, with the account holder, testing internally. Still to
      do before submitting: App Privacy labels, price and availability,
      review contact details ([app stores](app-stores.md#status)).
26. **Bring the privacy policy up to date with the app, add a contact
    email, and make the iOS privacy manifest and the store answers match
    the App Store Connect labels.**
    - The policy ([privacy](privacy.md),
      `tabcam_index/site/privacy/index.html`): signing in is required
      (Google, or Sign in with Apple on iOS; the welcome only, signed
      out), Apple's data and session, the profile, Cam's takes with
      their sound and the microphone, ML Kit's diagnostics (a device or
      installation ID, performance and diagnostic data, not linked) in
      place of "no analytics", Premium's Fix sending the song and the
      tab's text to Anthropic's Claude, Apple and Anthropic among the
      processors, KMS; Share copying a link that anyone holding it can
      open, read only, and that can't be turned off yet (replacing "a
      link gives no access by itself" and PDF or text sharing); Delete
      account's whole scope, Apple token revocation included, and that it
      doesn't cancel Premium. Contact: privacy@nu01.com, replacing the
      placeholder.
    - `PrivacyInfo.xcprivacy`: Audio Data, linked, not tracking, App
      Functionality; its comment names ML Kit's own manifests for the
      not-linked analytics data.
    - [data-safety.md](../tabcam_store/data-safety.md): Apple's labels as
      entered (Name, Email, Photos or Videos, Audio Data, Other User
      Content, User ID linked for App Functionality; Device ID,
      Performance Data, Other Diagnostic Data not linked, for Analytics),
      Play's Device or other IDs row for ML Kit, and a note that ML
      Kit's manifests also list Product Interaction, Other User Content
      and Other Data Types, to check against the app's privacy report.
27. **Disable Fix for now and take it out of the UI** (after an estimate
    of the cost per user put Fix's Claude runs at most of a Premium
    user's cost).
    - The Text view no longer shows **Fix**: it's behind a build flag,
      `TABCAM_FIX` (off; `true` shows it), passed through
      `scripts/dart-defines.sh` and listed in `.env.example`. Lining the
      tab up goes with it. The code, the `/autocorrect` route and the
      tests stay; the tests turn the button on.
    - Specs ([auto-correct](autocorrect.md#hidden-for-now),
      [tab recognition](tab-recognition.md), [app stores](app-stores.md))
      and the store descriptions no longer offer Fix.
28. **Set Premium's price to $10 a month or $100 a year.** The web's
    upgrade offer on the Premium card now gives the price ("$10 a month
    or $100 a year: subscribe with …", US$ in Spanish and Portuguese);
    the store apps still show no purchase information. The charge itself
    is Substack's paid-subscription setting, set there
    ([cloud OCR](cloud-ocr.md#who-is-premium)).
29. **Set cache headers on user data, fetch and cache it through
    CloudFront, and cache it on the device by the same headers** (signed
    URLs chosen over keeping S3 only, or waiting for encryption).
    - Every object says how to cache it: pages a year (`immutable`),
      `event.json` and OCR results `no-cache` (the app's uploads, and the
      OCR service's results).
    - The sites' distributions serve the user-data bucket at `/us-east-1:*`
      to signed URLs only (the share API's new key group, `tabcam-user-data`,
      its key in SSM via `scripts/make-cdn-key.sh`), cached as the objects
      say; the bucket policy names the two distributions alone. The share
      API signs a grant per folder with each set of credentials (profile,
      shared capture, link), one policy per site, and invalidates a
      deleted account's folder.
    - The app reads granted keys through CloudFront and a device cache
      (`HttpCache`: files on phones, IndexedDB on the web, 512 MB),
      falling back to S3; the cache empties on sign-out.
    - The privacy policy names CloudFront, where it caches and for how
      long, the device cache, and that deleting an account drops
      CloudFront's copies. See [caching users' files](cdn.md).
30. **In Cam, open the play-along sidebar by default, with the first file
    that isn't a tab, paused; hide it when there's none; give the player
    Stop and Play.** Cam now opens with the sidebar showing and the
    capture's first recording, video or link loaded in the frame,
    paused (a YouTube video's embed doesn't autoplay; a page that plays
    by itself is paused once loaded). With none, no sidebar and no ♫.
    The frame has **Stop** (pause, back to the start) beside Pause /
    Play. See [Cam](cam.md#playing-along-with-a-file).
31. **Rescan: wait until the reading is done to remove the existing text,
    and only on success; on failure, only a message; keep spinning
    meanwhile.** Rescan no longer empties the text tab first. It reads
    with `readSoon(id, replace: true)` (the cloud's collection and the
    device's write replace the text, edited or verified, only when a
    tab is found), the Text view spins with "Rescanning the pages…" and
    the text, Fix, Rescan and Verified waiting, and a read that finds no
    tab, fails or can't run leaves the text and Verified as they were,
    with a message ending "The text was kept.". The confirmation's text
    says so (en, es, pt). See [tab recognition](tab-recognition.md) and
    [cloud OCR](cloud-ocr.md).
32. **Add to CLAUDE.md design guidelines: always use the client device and
    save as much as possible of the server side's resources; if a feature
    needs the server, add it there but make it available only to Premium
    users.** CLAUDE.md has a Design guidelines section saying so.
33. **When a user adds a link, check whether it's from a known tab site
    (a list of the most popular ones); if so, import the page as if it
    were a PDF print of it, then scan it for tabs.**
    - A list of 14 tab sites (Ultimate Guitar, Songsterr, 911Tabs,
      GuitarTabs.cc, AZ Chords, E-Chords, Guitaretab, Chordie,
      Tabs4Acoustic, Big Bass Tabs, Classtab, Cifra Club, Cifras,
      LaCuerda). A link to one of them, from Capture or an event's Add,
      also adds a PDF print of the page (the title, the tab's text in
      Courier, the address and date at the foot), which the PDF reader
      reads for tab on the device. The link stays.
    - The device fetches the page (Android, iOS); on the web, where CORS
      forbids it, the cloud OCR service's new `POST /page` does, for
      Premium only, from the listed sites only (redirects included).
    - The tab is Ultimate Guitar's page data, other sites' `<pre>`
      blocks, or a plain-text page.
    - Reading tells apart staves one right under another (by a blank
      line's gap, or the first string's name coming back), which merged
      into one before.
    See [tab site links](tab-site-links.md).
34. **When a capture is shared: its owner sees all files; signed out, the
    person opening the link sees only the owner's; signed in, they add
    their own files and recordings and see only theirs and the owner's,
    not other sharees'; the owner sees everyone's and can publish them.
    (A teacher publishes a tab and resources; students upload videos and
    links without seeing each other's; the teacher publishes the ones they
    like.)** Added [contributions](contributions.md):
    - Someone signed in who opens a capture's link joins it (`POST
      /links/{captureId}/join`), with a read grant of their own, so it's
      in their Shared with me; the owner's people sheet says "Joined by
      the link". Up to 500 may join, apart from the 50 email grants.
    - The **read** role is now "Can view and add": readers (by email or
      by the link) see the owner's files and add their own (Add, dropped
      files, Cam's takes) to a contribution in its own folder,
      `<owner>/contrib/<capture>/<their identity>/`, which their
      credentials alone reach besides the capture's (the
      `tabcam-share-access` role now allows `contrib/` too). Editors are
      as before and don't see contributions.
    - The owner's devices list `contrib/` each pass and show each
      reader's files under "From <email>" (the grants now record each
      reader's identity); **Publish** copies one into the capture (a new
      page whose `from` names theirs), for everyone (its link too), and
      tapping again takes it back.
    - Deleting an account deletes what it contributed to others'
      captures (the share API may now delete under `*/contrib/*`).
    - Event screen, file screen, Cam and Home changed to match; strings in
      English, Spanish and Portuguese. [Shared captures](shared-captures.md),
      [sharing](sharing.md), [event screen](event-screen.md),
      [Cam](cam.md), [cloud sync](cloud-sync.md) and the
      [library](library.md) updated.
35. **In the Text view, when the user taps a red (suspicious) note, or
    right to its left or right, remove the red marker.** A tap that puts
    the cursor in a red note or one character beside it, on its line,
    drops that doubt from the event (`doubtAt`), saved and synced; the
    hint under the tools now says to tap a note once it's checked (en,
    es, pt). Not on a capture shared to read. See
    [tab recognition](tab-recognition.md).

## 2026-10-17

1. **In the Cam view, open the player sidebar by default (hidden when
   there's nothing to play), play the video or song in a separate frame,
   always visible, with play / pause, open the first file by default, and
   put that frame in the sidebar, compact, above the list (inside the
   sidebar, not the screen's width).** The sidebar already opened with
   the first file loaded; its frame moves from above the camera into the
   sidebar's top, as wide as the sidebar, pinned above the scrolling
   list, with smaller type and compact Play / Pause and Stop. Close is
   gone (the frame is always there; its string was dropped in en, es,
   pt). ♫ hides the whole sidebar, which pauses what plays; while it's
   hidden, space turns the tab. See [Cam](cam.md).
2. **Merge and check all changes, verify the app is ready for the App
   Store and help release it there.** Merged the Cam sidebar PR (#130;
   the zone merge, #90, stays a draft until its DNS wait is over), with
   `flutter analyze` and `flutter test` passing; released
   `0.2.202610171036` (RC and GA, live on both sites); built the App Store
   build from that commit (build 1792233362) and uploaded it. The App
   Store status is brought up to date: the Sign in with Apple key and the
   privacy contact are done; what's left is the maintainer's (App Privacy
   labels, price and availability, App Review's contact, trying Sign in
   with Apple on a phone) and the submission. See
   [app stores](app-stores.md).
3. **Reduce the font and icons on the capture list on mobile, just a
   little.** On screens narrower than 600 dp, the Home cards' title and
   details line are a point smaller, the ⋮ is 20 dp (24 elsewhere), and
   the preview's icon 40 dp (48) with a 14 dp badge (16). See
   [library](library.md).
4. **Release on the Android store too.** The Play Console account
   exists but can't publish yet: Google is verifying the maintainer's
   identity, and the contact phone is verified after. Added
   `scripts/store-upload-android.sh` and the Fastfile's Android lanes
   (`supply`): the Play listing, and a signed App Bundle (a path or a
   release tag's) to a testing track, as a draft by default, never to
   production. The `0.2.202610171036-GA` App Bundle is checked as signed
   with the upload key. Making the app in Play Console, its first upload
   by hand and the service account wait on the verification. See
   [app stores](app-stores.md#uploading-to-google-play).
5. **TestFlight build 0.1 tested, all good: merge everything and ship
   the latest.** The app PRs were merged already; draft #90 (the DNS
   zone merge) stays open, gated on its migration. Cut
   `0.2.202610171102-RC` and `-GA` at the tip of `main`, built and
   uploaded that App Store build (1792234961), added it to TestFlight's
   **Internal** group and renamed the listing's version to it, ready for
   review once the maintainer finishes App Store Connect's web-only
   steps. Sign in with Apple is marked tried on a phone. See
   [app stores](app-stores.md#status).
   The `testflight` lane no longer fails when a tester is already in
   **Internal**.
6. **Check whether App Store Connect's remaining steps are done.**
   Checked over the API: 0.2.202610171102 with build 1792234961 is
   Waiting for Review (manual release), free in all 175 territories,
   with the review contact, the age rating and the content rights set.
   See [app stores](app-stores.md#status).
7. **A box constraints error in the Text view.** On screens wider than
   1600 px (a 1920 px browser window) the Text view showed Flutter's red
   error: its text asked to be at least the screen's width and at most
   1600 px. It now goes up to the screen's width on such screens. See
   [tab recognition](tab-recognition.md).
8. **The play-along sidebar should be open by default whenever there are
   playable files; add « and » to its mini player; open it in the PDF
   and text viewers too; add a repeat button, on by default.** The
   sidebar already opened when Cam did; it now also opens when a
   recording, video or link arrives later (a sync, the first take),
   unless the user has hidden it. The frame has « and » (10 seconds back
   and forward; a YouTube video's from the time it says) and Repeat (on
   by default). The sidebar moved out of Cam (`PlayAlong`,
   `PlayAlongSidebar`) and is beside the Text view and a PDF too; the
   Text view's text now takes the view's width, not the screen's. See
   [Cam](cam.md#playing-along-with-a-file) and
   [event screen](event-screen.md).
9. **Remove "read again" from the Text tool in the nav bar; leave it
   only in the Text view's button, which is clearer.** Tapping the Text
   tool on the Text view no longer asks "Read the tab again?" (the
   dialog and its strings are gone); it only opens the Text view.
   Reading again is the Text view's Rescan (or Read again, when there's
   no tab). See [event screen](event-screen.md) and
   [tab recognition](tab-recognition.md).
10. **When a zip file is added, add all files inside it.** A zip picked
    with Files (Capture's or an event's Add) or dragged onto the app is
    unzipped on the device and its files added in its place, in order,
    folders flattened, a nested zip too; macOS's metadata files are left
    out; a zip that can't be read, is empty or is too big (over 1000
    files or 1 GB) is counted as left out. The Files picker offers
    `.zip`. Fixed on the way: files made from bytes now carry their name
    on Android and iOS too. See [scanning](scanning.md).
11. **No separate "Share with people" and "Share": just Share, which
    copies the link to send to other people; make sure it works.** The
    Share with people button and its people sheet are gone (with their
    strings); Share is the one way to share: it copies the read-only
    link, and someone signed in who opens it joins the capture to read.
    Captures shared by email before stay shared; the owner can no
    longer list or remove people in the app. Checked live: a link copied
    in the app opened without signing in (the share API's public
    credentials, then `event.json` through tabcam.nu01.com and
    rc.tabcam.nu01.com). Store screenshot 6 is now Share's "Link
    copied", and the listing text, review notes and data-safety answers
    say Share by link only, for the next upload (0.2's listing is in
    review). See [sharing](sharing.md) and
    [shared captures](shared-captures.md).
12. **Make the file names links with proper params, so a file can be
    opened in a new tab.** A file's link is the capture's with
    `&f=<file id>`; it opens the capture with that file open (signed
    in, signed out by its key, or after joining). In the list each file
    name is a link to it (a link file's, to its address): on the web a
    real anchor, so Cmd/Ctrl/Shift-click, a middle click or the
    browser's menu opens it in a new tab, while a plain click opens it
    in place. Checked in the local web app: plain click in place, and a
    file's link loaded fresh opens that file. See
    [event screen](event-screen.md) and [sharing](sharing.md).
13. **Swap the build waiting for App Review for the latest.** Added
    `scripts/store-submit-ios.sh` (fastlane `withdraw` and `submit`):
    withdrew 0.2.202610171102 (build 1792234961) before review started,
    renamed the version to 0.2.202610171415 and uploaded its listing and
    screenshots (Share by link only), and submitted it with build
    1792246500: Waiting for Review. Google Play: still verifying the
    maintainer's identity. See [app stores](app-stores.md#submitting-for-review).

## 2026-10-19

1. **Cost review, then: syncing every 10 seconds is too frequent; on
   startup and every 5 minutes is fine; go ahead with the other cost
   changes that don't hurt quality, usability or performance.** This
   change, the app's side:
   - Sync passes run on startup, 2 seconds after a change here, every 5
     minutes while the app is in front (was 10 seconds), none while it's
     behind (was every minute), and at once on coming back to it.
   - The owner's devices list `contrib/` only when a capture can have
     contributions (a link key, recorded shares, or some already).
   - The link viewer looks for the owner's changes every 5 minutes in
     front (was 10 seconds), not while hidden, and stops on a link gone
     for good (404, deleted).
   - The maintenance check pauses while the app is behind.
   See [cloud sync](cloud-sync.md#when-and-how), [sharing](sharing.md),
   [contributions](contributions.md),
   [maintenance mode](maintenance-mode.md).
2. **Cost: Premium pages read once.** The app no longer asks
   `/transcribe` when pages are added (their uploads already start the
   reading, so pages being read were read again); only Read again and
   Rescan ask. The backfill for pages without results waits 20 minutes
   (was 2), past the OCR worker's timeout. `tabcam-ocr` keeps each
   `ok`/`no-tab` reading by the image's ETag too, and an upload of an
   image read before (a clone, a published contribution, the same file)
   copies it instead of reading again. See [cloud OCR](cloud-ocr.md).
3. **Cost: server caps and fewer writes.**
   - `/autocorrect` is off on the server unless `AutocorrectEnabled=1`
     (it answers 503 as when the Claude key is missing), and its fetched
     pages are capped at 30,000 tokens.
   - The OCR API writes an identity's account record once an hour at
     most when nothing changed (it wrote on every request); the share
     API saves a profile's `lastSignInAt` at most hourly (it wrote on
     every request, every sync pass).
   - The OCR image repository keeps 3 images (was 10).
   - Not done: reserved concurrency for OCR (the account's Lambda limit
     is 10, all of which must stay unreserved; it already caps every
     function at 10 at once), and reusing the RC's iOS build in CI (the
     repository is public: Actions minutes are free).
   See [auto-correct](autocorrect.md), [cloud OCR](cloud-ocr.md),
   [profiles](profiles.md).
4. **Publish the app on Google Play and the App Store.** App Store:
   0.2.202610171415 is still Waiting for Review (nothing to do until
   it's approved; released by hand). Google Play: the account is
   verified, so the app was made in Play Console (app ID
   4975838614790670668), the GA App Bundle uploaded to an internal
   testing draft, and the store listing, store settings, privacy policy,
   content rating and most App content declarations filled in from
   [data-safety.md](../tabcam_store/data-safety.md) (Data safety as a
   draft, with voice or sound recordings added, and the privacy page as
   the deletion URL). Left for the maintainer: a Google test account for
   Play's Sign in details, then Target audience and submitting Data
   safety, the internal testers and rollout, and the closed test. See
   [app stores](app-stores.md#status).
5. **Do the rest of the Play setup.** The internal testing release
   (versionCode 1792246557) is rolled out to the **Internal** list (the
   maintainer's account); Play warned the Unix-seconds versionCode nears
   its 2,100,000,000 limit (about 2036; codes can switch to +1 then).
   Play's app signing key is in assetlinks.json. Not done, as they need
   the maintainer: the Google test account for Sign in details (and so
   Target audience and submitting Data safety), and the Android OAuth
   clients for Play's and the upload key's SHA-1 (Google Cloud asks for
   the password again). See [app stores](app-stores.md#android-signing).
4. **Delete everything of TabScan and recreate only what's needed, with
   tabcam names; the outage is fine.** Added `scripts/retire-tabscan.sh`
   for an administrator to run (the deletions are for good, so not run
   by the agent): it keeps the `accounts.google.com` OIDC provider
   (Retain), deletes every `tabscan-*` stack with its data, the old
   secret, parameter, log groups, `local.tabscan.nu01.com` and the old
   GitHub variables, imports the provider into `tabcam-identity`
   (TabCam's 3 Google clients only, the old project's 5 dropped), and
   redeploys the old domains' redirects as `tabcam-old-domain` and
   `tabcam-rc-old-domain`. `identity.yaml` keeps the provider on
   deletion. See [deploy](deploy.md#the-old-domains).
6. **Next Play steps; keep 18+.** Sign in details saved (the maintainer
   entered the reviewers' Google account, nu01test@gmail.com), Target
   audience 18 and over, Data safety submitted, and the closed testing
   track Alpha set up with the bundle, all countries and the Internal
   list. Younger groups were considered and left out: Play applies its
   Families policy to any group under 18 in some countries. The review
   submission waits for Play's key's Android OAuth client. See
   [app stores](app-stores.md#status).
7. **Scan failed on a test device: "Permission Denial … with revoked
   permission android.permission.CAMERA".** Where ML Kit's scanner isn't
   there (no Google Play services), the scanner falls back to the system
   camera app, and Android won't open it for an app that declares CAMERA
   (Cam does) without it granted. Scan now asks for the camera then and
   tries again; refused, it says the camera isn't allowed. See
   [scanning](scanning.md#android-and-ios).
8. **Update the app store releases and give the link to install the
   test version.** `0.2.202610191330-GA` went to both testing tracks:
   on Play, its App Bundle (versionCode 1792416626) to internal testing,
   uploaded by hand (no service account yet; the browser tool takes files
   under 10 MB only), rolled out to **Internal**, installed from the opt-in
   link; on the App Store, `make ipa` and `scripts/ios-upload.sh` (build
   1792417537), then `store-upload-ios.sh testflight 1792417537` into the
   TestFlight group **Internal**. The App Store review submission
   (0.2.202610171415) was left as it is. See
   [app stores](app-stores.md#status).
9. **Say "cam" or "camera", never "scanner" (add to memory and
   CLAUDE.md).** CLAUDE.md's design guidelines now say so. The store
   listings are now "TabCam: Guitar Tab Camera", "a camera app made for
   guitar and bass tablature", with a "POINT, SHOOT, DONE" section; the
   READMEs, the privacy page, the data safety notes, the App Review notes
   and the specs call the system's document scanner "the system document
   camera". Code identifiers and third-party names (`cunning_document_scanner`,
   CamScanner) keep theirs. See [app stores](app-stores.md) and
   [scanning](scanning.md).
9. **Sign-in stopped working in the Play build; offer Sign in with Apple
   there too.**
   - Google: the Play app signing key's Android OAuth client exists
     (`TabCam Android - Play signing`, made 2026-10-19), but neither it
     nor the debug key's client is in `tabcam-identity`'s
     `GoogleAppClientIds`, which AWS checks a Google token's `azp`
     against. Adding them is a stack deploy for the maintainer.
   - Apple on Android, planned first and approved with the share API
     route: the Services ID `com.nu01.tabcam.signin` made, the share
     API's `POST /apple/callback` redirect, both audiences in the
     identity pool, share API, OCR and token revocation, and the app's
     web flow on Android. The maintainer agreed that cheap server-side
     parts may serve everyone; only the expensive features are Premium
     (CLAUDE.md's design guideline says so now). See
     [cloud sync](cloud-sync.md#android-the-web-flow).

## 2026-10-20

1. **Google sign-in picks the account but doesn't get into the app (the
   Play build).** The phone's log: "Android clients and Web clients
   (server client ID) must be in the same project" (28444). Two causes:
   - On 2026-10-19 `retire-tabscan.sh`'s last step redeployed
     `tabcam-identity` with that stack's own Google parameters, which were
     still TabScan's: the Google provider lost TabCam's five clients (web,
     iOS, local web and two Android) and kept TabScan's, so AWS refused
     every TabCam Google sign-in, on every platform. They were put back
     (`GoogleWebClientId` and `GoogleAppClientIds` with TabCam's
     `tabcam-nu01` IDs), and the script now redeploys only right after the
     import, with the provider's clients and the web client from `.env`.
   - Play's Android OAuth client was made in the old TabScan project
     (`tabscan-511213`); it has to be in `tabcam-nu01`, with the web
     client. To do, in the Google Cloud Console. See
     [app stores](app-stores.md#android-signing).
2. **App Review rejected 0.2.202610171415 (guidelines 2.3.10 and
   2.1(b)).** The iOS screenshots' status bar drew Android's (Material)
   icons: it now draws Apple's glyphs, the iPad's with the date and no
   signal. And App Review took the Premium card ("TabCam Premium isn't
   active", Check again) and the listing's "TabCam Premium subscribers"
   for a subscription it couldn't buy (there are no in-app purchase
   products): in the store apps free users now see no word of Premium,
   the App Store and Play descriptions no longer mention it, and the
   review notes say there are no in-app purchases or subscriptions. See
   [cloud OCR](cloud-ocr.md#in-the-app) and
   [app stores](app-stores.md#store-graphics).
3. **Resubmitting after the rejection.** The `submit` lane refused while
   the rejected submission was open (Unresolved Issues), then Apple
   refused it while its item was still marked rejected. The lane now
   resubmits that submission, marking its rejected item resolved:
   0.2.202610201114 (build 1792494901) is Waiting for Review. See
   [app stores](app-stores.md#submitting-for-review).
4. **Sign in with Apple's web flow: Continue and Cancel did nothing.**
   Apple's authorize call answered 403, with no reason, for the return
   URL on the share API's `execute-api.us-east-1.amazonaws.com` address.
   The return URL is now on TabCam's own domain,
   `https://tabcam.nu01.com/apple/callback`, which the site's CloudFront
   passes to the share API (`site.yaml`), and the Services ID was renamed
   "TabCam" (Apple shows it on the sign-in page). See
   [cloud sync](cloud-sync.md#android-the-web-flow).
5. **`/apple/callback` answered 403 on the site.** CloudFront takes the
   first matching path, and `/app*` (the web app, GET only) matched
   `/apple/callback` first; the Apple route now comes before it in
   `site.yaml`.
6. **Match the web app as `/app/*` so it isn't ambiguous.** The site's
   web app routes are now `/app/*` and `/app` (redirected to `/app/` by
   the function), not the prefix `/app*`, deployed and in the local
   Floci CloudFront alike.

## 2026-10-21

1. **Sign in with Apple on Android: verify and fix.** Apple's side works:
   the web flow returns a token for the Services ID, and the "Continue
   does nothing" was a desktop artifact (the first press worked; the
   `intent://` redirect does nothing on a computer, and later presses get
   403). On throwaway pools, Cognito's built-in Apple login took
   `com.nu01.tabcam;com.nu01.tabcam.signin` literally and refused the
   token; so Apple moves to an IAM OpenID Connect provider for
   `appleid.apple.com` listing both IDs (`identity.yaml`), as Google did.
   Folders stay: they're the profiles', found by the sign-in's
   `issuer#sub`. See [cloud sync](cloud-sync.md#android-the-web-flow).
2. **Get TabCam out in the stores.** Apple: 0.2.202610201114 is in
   review (manual release once approved). Play: the listing changes
   (title, description) sent for review; production needs the closed test
   on Alpha to have 12 opted-in testers for 14 days (Play's rule for new
   personal accounts; 1 so far). Android's Apple-enabled build
   0.2.202610210617 to upload to Internal and Alpha. See
   [app stores](app-stores.md#status).
3. **Testers by link: a Google Group, nu01-testers, for all apps.**
   nu01.com's Workspace didn't let outside accounts join groups, so its
   Groups sharing settings now allow public groups and external members;
   `nu01-testers@nu01.com` (anyone can join; members see conversations,
   only the owner posts, only managers see members) replaced Alpha's
   **Internal** email list, whose testers were added to it. Alpha has
   0.2.202610210617, sent for review with the testers change. See
   [app stores](app-stores.md#status).
4. **In the play-along sidebar's mini player, a range with a start and an
   end, to repeat a section; local recordings and videos only.** Under
   the frame's progress bar: a range slider, the section's times (to the
   tenth of a second), start / end it where it plays now, and Play all of
   it. At the section's end it goes back to its start (Repeat) or pauses
   there. Links have none. See [Cam](cam.md).
5. **Drop the Text view's warning about notes in red being low
   confidence: it's obvious.** The line under the editing tools is gone
   (and its string, en, es, pt); the notes are still red. See
   [tab recognition](tab-recognition.md).
