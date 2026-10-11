# Privacy

TabScan's privacy policy, for the stores' listings and anyone using the
app, and the iOS privacy declarations.

## The policy page

- **Where**: https://tabscan.nu01.com/privacy (and the RC's
  https://rc.tabscan.nu01.com/privacy), from
  [tabscan_index/site/privacy/index.html](../tabscan_index/site/privacy/index.html).
  CloudFront rewrites directory URIs only under `/app*`, so
  [deploy](deploy.md) uploads the file as the S3 object `privacy`
  (`text/html`), and its smoke test checks `/privacy` serves it. The local
  index server (`python3 -m http.server`, port 2013, and Floci in front of
  it) serves it at `/privacy/`, redirecting `/privacy` there; the page's
  links are absolute so both work.
- **Linked from**: the index page's footer, and **Privacy policy** in the
  Profile tab's About ([navigation](navigation.md#profile)), which opens
  the production URL in the browser (`url_launcher`, external) on every
  build.
- **Look**: a single static page with inline CSS, TabScan's amber on warm
  white, dark in dark mode; readable at phone width.
- **Who**: Julio Faerman, an individual developer (the personal store
  accounts' seller). **Contact**: a visible placeholder,
  "[CONTACT EMAIL TO BE ADDED]", until the maintainer gives a public
  address.

## What it says, and what that's based on

| Statement | Based on |
|---|---|
| Signed out, captures stay on the device (in memory on the web) | [cloud sync](cloud-sync.md#signed-out), [platforms](platforms.md) |
| Signed in: Google name, email, photo and account ID; name and photo only shown, not stored on servers | `AuthUser`, `SavedSession`; the share API and OCR service store only emails and identity IDs |
| Captures (pages, photos, videos, files, text, links, titles, artists, text tabs) synced to the user's own S3 folder | [cloud sync](cloud-sync.md#whats-synced-and-where) |
| Grantee emails and roles, no email sent | [shared captures](shared-captures.md) |
| Email checked with rbacr for Premium; identity → email in `tabscan-accounts` | [cloud OCR](cloud-ocr.md#who-is-premium) |
| On-device reading with ML Kit; ML Kit may send Google anonymous metrics | [tab recognition](tab-recognition.md); ML Kit pulls in GoogleDataTransport |
| Premium pages transcribed in AWS Lambda, results in the user's folder | [cloud OCR](cloud-ocr.md#transcription) |
| AWS (S3, DynamoDB, Cognito, Lambda), us-east-1, encrypted at rest, HTTPS only | [tabscan_infra/](../tabscan_infra): SSE-S3, TLS-only bucket policy |
| Substack and Stripe for subscriptions; no payment details reach TabScan | [cloud OCR](cloud-ocr.md#who-is-premium) |
| Web: session (name, email, photo URL, ID token) in `localStorage` until sign-out | [cloud sync](cloud-sync.md#signing-in) |
| Links name a capture by ID and give no access by themselves | [sharing](sharing.md#opening-a-link) |
| Deleted files kept 30 days (bucket versions); DynamoDB point-in-time recovery 35 days; Lambda logs 30 days, no capture content, OCR logs without emails | `user-data.yaml`, `share-api.yaml`, `ocr.yaml`, [cloud OCR](cloud-ocr.md#troubleshooting-log) |
| **Delete account** in the Profile tab deletes the account's cloud data | Added in a parallel change; the policy's wording must match what it deletes |
| No ads, analytics, crash reporting or tracking | No such packages in `pubspec.lock` or `Podfile.lock`; the site keeps no CloudFront access logs |
| Not directed to children under 13 | |

When a change alters what's collected, where it goes or how long it's
kept, update the page (and its "Last updated" date), this table, the iOS
privacy manifest and the stores' privacy answers together.

## iOS declarations

- `ITSAppUsesNonExemptEncryption` = false in `Info.plist`: HTTPS and
  SigV4 signing (HMAC, authentication) only.
- `Runner/PrivacyInfo.xcprivacy`: no tracking; email, name, user ID,
  photos or videos, and other user content, linked, for app
  functionality; no required-reason APIs in the app's own code.

Details in [platforms](platforms.md).
