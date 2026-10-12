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
29. **Make https://local.tabscan.nu01.com work over HTTPS using Floci, as
    presence does.** Finished the local HTTPS from 27. Floci no longer gets
    `FLOCI_PORT` in its environment: it read that as its own listen port,
    so its setup hook couldn't reach it and the container restarted in a
    loop. Wrote [tabscan_floci/README.md](../tabscan_floci/README.md), and
    described `4-floci` and the `cdn` and `https` checks in the
    [dev environment](dev-environment.md) spec, the README and AGENTS.md.
    Checked with `devbox services up`:
    https://local.tabscan.nu01.com:2443/app/ answers with a trusted
    certificate.
30. **The local Google OIDC client ID should be
    `1061413485511-2ndd6lqkmi61j17vpk5f2ntjb91tt38r`; verify and fix.**
    Local builds used the production web client, whose only origin is
    https://tabscan.nu01.com. New setting
    `TABSCANNER_GOOGLE_LOCAL_WEB_CLIENT_ID` (the "local - web" client),
    which the dev web server uses in its place
    ([dev environment](dev-environment.md)). That client needs
    `https://local.tabscan.nu01.com:2443` among its JavaScript origins, and
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
    `tabscan_infra/identity.yaml` (deployed), with S3 writes to the user's
    own folder. What failed: the pool trusted only the production web
    client, so local builds' tokens (the local web client) were refused
    before any role was assumed. The pool, the OCR service and the share
    API now also trust `GoogleLocalWebClientId`, and the bucket, the OCR
    function URL and the share API allow the origin
    `https://local.tabscan.nu01.com:2443`
    ([cloud sync](cloud-sync.md), [cloud OCR](cloud-ocr.md),
    [shared captures](shared-captures.md)). No `lambda:InvokeFunction` was
    granted to users: the app reaches its functions through the OCR function
    URL and the share API with the Google token, and invoking
    `tabscan-ocr-api` or `tabscan-ocr` directly would let a user forge S3
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
    show as a file chooser. It now opens TabScan's own camera screen (the
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
    `PoolName`; export `<stack>-pool-id`): `tabscan-identity` (unchanged)
    and the new `tabscan-identity-local`, pool `tabscan-local`, trusting the
    local web client, with its own role on the bucket. The dev web server
    uses `TABSCANNER_COGNITO_LOCAL_IDENTITY_POOL_ID` with the local client
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
    `tabscan_index/site/status.json` (`{"maintenance": false}`); flip it to
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
    `https://tabscan.nu01.com/app/?c=<capture id>`; the web app opens it
    from the user's events (own or shared), after signing in and a sync
    pass if needed. `event.json` in the cloud now has `owner` and
    `shares`, which the owner's app records from the share API
    ([cloud sync](cloud-sync.md), [shared captures](shared-captures.md)).
    Android app links are a follow-up. The text tab and links go in the
    PDF and the zip. (There are no PDF pages: pages are images, videos and
    links, so PDF combines the images.)
38. **Let the owner hide the original image and show only the text and
    attachments.** A capture's owner can now **Hide images** (and **Show
    images**) from the event screen's app bar. This is a synced setting
    (`hideImages` in `event.json`), so it applies to everyone: the owner's
    devices and the people it's shared with, who can't change it. Hidden,
    the event screen shows the text tab as the first page, then the videos
    and links. Library cards show no image, and PDF and Files exports
    leave the images out. The images are kept, Read tab still reads them,
    and grantees still sync them ([hidden images](hidden-images.md)).
42. **(Continuing 37) Android links.** Android App Links: the app opens
    `https://tabscan.nu01.com/app…` and the RC's (verified intent filter),
    and opens the capture a link names, launched or running
    (`IncomingLinks`). Deploys upload `/.well-known/assetlinks.json`, which
    lists the maintainer's debug key; Release-workflow APKs, signed with a
    new debug key each run, aren't verified until there's a release key
    ([sharing](sharing.md#android-app-links), [platforms](platforms.md),
    [release](release.md), [deploy](deploy.md)).
43. **In the camera screen, make auto shutter off the default and remove
    filters.** On the phone, Scan is the system document scanner, which
    lets the app set neither the shutter mode nor (on iOS) the filters.
    Android's scanner now runs in ML Kit's base mode, so it has no filters
    (and no ML clean-up). Auto capture stays the scanners' default, and iOS
    keeps VisionKit's filters ([scanning](scanning.md),
    [platforms](platforms.md)). TabScan's own camera screen (the web) has
    neither auto shutter nor filters.
44. **Bring back the "Text" button in the capture view to flip from scan
    to text; remove the flip button from the top and leave flipping to
    the bottom bar.** The event screen's tools are the view (**Original ↔
    Scan**), then **Text**, which shows the text view in place of the
    pages and reads **Pages** to go back; then Add, Rotate, Delete. The
    app bar's Hide images / Show images button is gone. `hideImages` is
    still honoured, so a capture already hidden stays hidden
    ([event screen](event-screen.md), [hidden images](hidden-images.md),
    [tab recognition](tab-recognition.md#text-view)).
45. **Show the user's role on the profile screen.** The signed-in account
    on Profile has a "Role: Premium" or "Role: Free" line under the name,
    from the premium status the cloud OCR service gets from rbacr ("Free
    (couldn't check)" when rbacr doesn't answer, "Checking…" until the
    first answer). Builds without the service show no role
    ([cloud OCR](cloud-ocr.md#in-the-app), [navigation](navigation.md#profile),
    [cloud sync](cloud-sync.md#signing-in)).
46. **Help me publish the app to the Apple and Google stores, step by
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

47. **Hide the Premium purchase links in the store apps** (part of
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
48. **In-app account deletion** (part of publishing to the stores: App
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
    fastlane yet: [tabscan_store/](../tabscan_store) with the Play title,
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
    https://tabscan.nu01.com/privacy (`tabscan_index/site/privacy/`,
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
52. **Sign in with Apple on iOS** (App Store guideline 4.8: an app with
    Google sign-in must offer an equally private one). iOS offers **Sign
    in with Apple** above Google's button, per Apple's guidelines, on the
    Profile tab and the sign-in sheets, in builds with
    `TABSCANNER_APPLE_SIGN_IN=1` (a new dart-define; it also adds the
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
    ([cloud sync](cloud-sync.md#sign-in-with-apple-ios),
    [shared captures](shared-captures.md#how-it-works),
    [cloud OCR](cloud-ocr.md#who-is-premium), [platforms](platforms.md),
    [app stores](app-stores.md), [tabscan_infra](../tabscan_infra/README.md)).
    Merged after account deletion and localization: Apple users delete
    their account under `/apple` too, and the sign-in buttons and Apple's
    messages are in English, Spanish and Portuguese.
60. **Add instructions to the README on how to install a release on iOS
    or Android.** The README has "Installing a release on a phone". For
    Android: the APK opened on the phone or installed with `adb install
    -r`, what to do about a key conflict, and that Google sign-in waits
    for the upload key's OAuth client. For iOS: the release's app is
    unsigned, so the tag is built and installed with the tester's own
    team, with Developer Mode and trusting the developer, and a free
    team's 7 days ([release](release.md#installing-a-release)).
61. **In the capture's pages, let every file type have a preview: a PDF or
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
62. **The app says Premium isn't active: make sure the rbacr integration
    is set up and the premium role is returned for julio@nu01.com.**
    rbacr was fine (`allowed: true` for `tabscan`/`premium`, through the
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
    [app stores](app-stores.md), [tabscan_infra](../tabscan_infra/README.md)).
63. **Make profiles work like in Presence: an authenticated user without a
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
    `login.tabscan.profiles`; the cloud OCR service checks Premium by
    profile. The app gets its folder through the profile, moves the user's
    captures when their folder changes, and shows the profile, its roles
    and Linked accounts on the Profile tab
    ([profiles](profiles.md), [cloud sync](cloud-sync.md),
    [shared captures](shared-captures.md), [cloud OCR](cloud-ocr.md),
    [navigation](navigation.md#profile)).
64. **In the capture view, where there are the Scan, Photos, Files and Link
    options, add a Document option for PDFs, first in the Add list; leave
    Scan as is.** Capture's Add list starts with **Document** ("PDF
    files"), which picks PDFs only and makes an event of them, like Files;
    Scan is unchanged. In English, Spanish and Portuguese
    ([navigation](navigation.md#capture)).
65. **When a PDF is added, just like an image, try to parse it into text,
    and present it as a tab.** PDF pages are read by themselves into the
    text tab: their text where they have one (PDFium through `pdfrx`, the
    characters' positions laid out as a text tab, chords and lyrics kept),
    else their pages rendered and read by the device's OCR. Found on the
    way: a read could overwrite pages added while it ran (it saved an old
    copy of the event); it now writes only its text onto the event as it
    is, adding pages does the same, and pages changed during a read are
    read again ([tab recognition](tab-recognition.md#pdfs)).
67. **I still don't see the button for adding PDFs: make sure everything is
    merged and deployed.** The Document option was on the Capture tab
    only (and the web was still the release from before it). The open
    capture's **Add** menu now has **Document** right after Scan pages, the
    menu scrolls (five items overflowed a small phone), and a release
    puts it all on the web ([scanning](scanning.md#adding-to-an-event)).
