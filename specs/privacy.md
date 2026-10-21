# Privacy

TabCam's privacy policy, for the stores' listings and anyone using the
app, and the iOS privacy declarations.

## The policy page

- **Where**: https://tabcam.nu01.com/privacy (and the RC's
  https://rc.tabcam.nu01.com/privacy), from
  [tabcam_index/site/privacy/index.html](../tabcam_index/site/privacy/index.html).
  CloudFront rewrites directory URIs only under `/app/`, so
  [deploy](deploy.md) uploads the file as the S3 object `privacy`
  (`text/html`), and its smoke test checks `/privacy` serves it. The local
  index server (`python3 -m http.server`, port 2013, and Floci in front of
  it) serves it at `/privacy/`, redirecting `/privacy` there; the page's
  links are absolute so both work.
- **Linked from**: the index page's footer, and **Privacy policy** in the
  Profile tab's About ([navigation](navigation.md#profile)), which opens
  the production URL in the browser (`url_launcher`, external) on every
  build.
- **Look**: a single static page with inline CSS, TabCam's amber on warm
  white, dark in dark mode; readable at phone width.
- **Who**: Julio Faerman, an individual developer (the personal store
  accounts' seller). **Contact**: privacy@nu01.com (a `mailto:` link).

## What it says, and what that's based on

| Statement | Based on |
|---|---|
| Sign-in is required: signed out the app is only the welcome, nothing captured or sent (but for opening a capture's link) | [cloud sync](cloud-sync.md#signed-out), [navigation](navigation.md#signed-out-the-welcome) |
| Google (name, email, photo, account ID) or, in the iOS and Android apps, Sign in with Apple (name, email or Apple's private relay address, user ID), or email (the address, a code emailed; the user pool's user ID); emails and IDs stored on servers, name and photo only shown | `AuthUser`, `SavedSession`, [Sign in with Apple](cloud-sync.md#sign-in-with-apple-ios-and-android); the share API and OCR service store emails, subjects and identity IDs |
| A profile (random ID, linked accounts' emails and IDs, link times) | [profiles](profiles.md) |
| Captures (pages, photos, videos, audio recordings, Cam's takes with their sound, PDFs and files, links, titles, artists, text tabs) synced to the user's own S3 folder | [cloud sync](cloud-sync.md#whats-synced-and-where), [Cam](cam.md) |
| Camera to scan and record in Cam; microphone for Cam's sound; photos and files only as picked | `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryUsageDescription`; [Cam](cam.md) |
| Grantee emails and roles, no email sent | [shared captures](shared-captures.md) |
| Email checked with rbacr for Premium; identity → email in `tabcam-accounts` | [cloud OCR](cloud-ocr.md#who-is-premium) |
| On-device reading with ML Kit | [tab recognition](tab-recognition.md) |
| ML Kit (phone apps) may send Google diagnostic and performance data with a device or installation ID, not linked to the account, never images, faces or tabs | ML Kit's own privacy manifests (MLKitCommon, MLKitFaceDetection, GoogleDataTransport): device ID, performance and other diagnostic data, not linked, analytics |
| Head gestures: face detection on the device (ML Kit on Android and iOS; MediaPipe in the browser on the web, its library and model downloaded from jsDelivr and Google, the camera's picture never sent), only the head's angle used; nothing about the face saved, sent or used to identify anyone; can be switched off | [Cam](cam.md#head-gestures) |
| Premium pages transcribed in AWS Lambda, results in the user's folder | [cloud OCR](cloud-ocr.md#transcription) |
| Premium's Fix sends the song's name and the tab's text (no image) to Anthropic's Claude, which searches the web | [auto-correct](autocorrect.md#checking-it-online-premium) |
| CloudFront delivers users' files from its US, Canada, Europe and Israel locations (PriceClass_100), cached as each file says (pages up to a year, details and transcriptions not at all), to hour-long signed URLs only; deleting an account invalidates its folder. The apps keep up to 512 MB of downloaded files in a cache, emptied on sign-out | [caching users' files](cdn.md) |
| AWS (S3, DynamoDB, KMS, Cognito, Lambda), us-east-1, encrypted at rest, HTTPS only; Google, Apple and Cognito's user pool (its emails through Cognito, later SES) for sign-in | [tabcam_infra/](../tabcam_infra): SSE-S3, TLS-only bucket policy; [encryption](encryption.md) |
| Substack and Stripe for subscriptions; no payment details reach TabCam | [cloud OCR](cloud-ocr.md#who-is-premium) |
| Web: session (name, email, photo URL, ID token) in `localStorage` until sign-out; iOS: the Apple session in `apple_sign_in.json` until sign-out or expiry; email sign-in: the session in `email_sign_in.json` (web: `localStorage`) until sign-out or the refresh token's 30 days | [cloud sync](cloud-sync.md#signing-in) |
| Share copies the capture's link, whose key lets anyone holding it open the capture read only, signed out too, live; it can't be turned off yet (deleting the capture or the account ends it); chat apps' previews show title, artist and contents. No PDF or text export | [sharing](sharing.md), [shared captures](shared-captures.md) |
| Deleted files kept 30 days (bucket versions); DynamoDB point-in-time recovery 35 days; Lambda logs 30 days, no capture content, OCR logs without emails | `user-data.yaml`, `share-api.yaml`, `ocr.yaml`, [cloud OCR](cloud-ocr.md#troubleshooting-log) |
| **Delete account** in the Profile tab (the web app's too) deletes the folder, the device's copies, grants, links, the profile and the Premium record; for Apple sign-ins it revokes Apple's tokens, for email sign-ins it deletes the address from the user pool; Premium isn't cancelled | [cloud sync](cloud-sync.md#deleting-the-account), [revoking Apple's tokens](cloud-sync.md#revoking-apples-tokens) |
| Links (YouTube's too) open outside TabCam, in the browser or the app for them, under that site's own policy; the one exception is a link chosen to play along with in Cam, shown in a frame on that screen (a YouTube video in its privacy-enhanced player, youtube-nocookie.com) | [event screen](event-screen.md), `link_page.dart` (`launchLink`); [Cam](cam.md#playing-along-with-a-file) |
| No ads, crash reporting or tracking, no analytics of TabCam's own (ML Kit's diagnostics aside) | No such packages in `pubspec.lock` or `Podfile.lock`; the site keeps no CloudFront access logs |
| Not directed to children under 13 | |

When a change alters what's collected, where it goes or how long it's
kept, update the page (and its "Last updated" date), this table, the iOS
privacy manifest and the stores' privacy answers together.

## iOS declarations

- `ITSAppUsesNonExemptEncryption` = false in `Info.plist`: HTTPS and
  SigV4 signing (HMAC, authentication) only.
- `Runner/PrivacyInfo.xcprivacy`: no tracking; email, name, user ID,
  photos or videos, audio data (Cam's takes' sound, recordings) and
  other user content, linked, for app functionality; no required-reason
  APIs in the app's own code. ML Kit's device ID, performance and
  diagnostic data (not linked, analytics) are declared by its own
  manifests, not repeated here. App Store Connect's labels: those six
  linked for App Functionality, and Device ID, Performance Data and Other
  Diagnostic Data not linked, for Analytics
  ([data safety](../tabcam_store/data-safety.md)).

Details in [platforms](platforms.md).
