# Data safety, privacy labels, rating and audience (draft answers)

Draft answers for the stores' forms, derived from the code and the specs
([privacy](../specs/privacy.md),
[cloud sync](../specs/cloud-sync.md),
[shared captures](../specs/shared-captures.md),
[cloud OCR](../specs/cloud-ocr.md)). Keep them in step with the privacy
policy (https://tabcam.nu01.com/privacy) and the iOS privacy manifest
(`tabcam_app/ios/Runner/PrivacyInfo.xcprivacy`): when one changes, the
others change too.

## What TabCam does with data, in short

- **Signed out**: the app is only a welcome with the sign-in buttons;
  nothing can be captured and nothing leaves the device.
- **Signed in** (with Google; on iOS, with Apple too): the app gets the
  Google account's name, email, photo and ID, or the Apple ID's name and
  email (Apple's private relay address if the user hides theirs) and
  user ID. The **email** and the **identity ID** (Cognito) reach TabCam's
  servers; the name and photo are only shown in the app. The user's
  **captures** (scanned pages, photos, videos, Cam's takes with their
  sound, recordings, PDFs and other files, text tabs, titles, artists,
  links) sync to their own folder in AWS S3. When
  they share a capture, the **grantee's email** and role are stored. For
  Premium, the email is checked with rbacr (the maintainer's own role
  service); Premium pages are transcribed in AWS Lambda.
- **Processors**: AWS (S3, DynamoDB, Cognito, Lambda; us-east-1),
  encrypted at rest; HTTPS only. Google, and Apple on iOS, for sign-in.
- **Cam's head gestures**: ML Kit face detection on the device; only the
  head's angles are used, nothing about the face is kept or sent.
- **No** ads, crash reporting or tracking SDKs, and no analytics of
  TabCam's own (ML Kit's, below, aside); no data sold or shared for
  advertising.
- **ML Kit** (on-device text recognition and, on Android, the document
  scanner) may send Google anonymous diagnostics and usage metrics about
  the ML Kit APIs (GoogleDataTransport). Google's guidance on declaring
  it: https://developers.google.com/ml-kit/android-data-disclosure. The
  maintainer should confirm the answers below against that page before
  submitting.
- **Deletion**: Profile → Delete account deletes the account's cloud data;
  deleted files linger up to 30 days in bucket
  versions, DynamoDB backups 35 days, Lambda logs 30 days.

## Google Play: Data safety

**Overview questions**

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | Yes |
| Is all of the user data collected by your app encrypted in transit? | Yes |
| Do you provide a way for users to request that their data is deleted? | Yes: in the app (Profile → Delete account) and by the URL below |
| Account deletion URL (App content → Data deletion) | https://tabcam.nu01.com/app/ (sign in, open Profile, tap Delete account) |
| Can users create an account? | Yes, with Google sign-in (OAuth); the app needs one |

**Data types** (collected = sent off the device; none is **shared**: AWS
and Google sign-in are service providers acting for TabCam, which Play
doesn't count as sharing). They're **required**: signed out the app is
only the welcome, so every user signs in (the diagnostics row aside). None
is processed ephemerally only.

| Category → type | Collected | Purposes | Notes |
|---|---|---|---|
| Personal info → Email address | Yes | App functionality, Account management | The account's email (identity, Premium check) and the emails a user shares captures with |
| Personal info → User IDs | Yes | App functionality, Account management | Cognito identity ID; Google account ID in the sign-in token |
| Personal info → Name | Yes (conservative) | App functionality | Shown in the app only, not stored on servers. Strictly not "collected" under Play's definition; declared to match the iOS manifest. The maintainer may answer No |
| Photos and videos → Photos, Videos | Yes | App functionality | Scans, photos and videos synced to the user's folder |
| Audio → Music files, Other audio files | Yes | App functionality | Recordings added to captures, and Cam's takes' sound (in their videos) |
| Files and docs | Yes | App functionality | PDFs and files added to captures |
| App activity → Other user-generated content | Yes | App functionality | Text tabs, titles, artists, links |
| App info and performance → Diagnostics | Yes, if ML Kit's disclosure says so | Analytics (by Google ML Kit) | Anonymous ML Kit metrics; collected also signed out; confirm against Google's ML Kit page |
| Device or other IDs | Yes, if ML Kit's disclosure says so | Analytics (by Google ML Kit) | The installation identifier ML Kit's metrics carry; not linked to the account |

Not collected: location, financial info (Premium is paid through Stripe
via Substack, outside the app), health, messages, voice recordings, contacts,
calendar, web browsing, app interactions, crash logs.

## Apple: App Privacy labels

**Tracking**: No (no data used to track users across apps or websites;
no ATT prompt).

**Data linked to the user** (all for **App Functionality** only; none
used for tracking):

| Apple category → type | Notes |
|---|---|
| Contact Info → Email Address | Account email (Google's, or Apple's, maybe a private relay address); shared-with emails |
| Contact Info → Name | Shown only; declared to match `PrivacyInfo.xcprivacy` |
| Identifiers → User ID | Cognito identity ID, Google account ID, Apple user ID |
| User Content → Photos or Videos | Scans, photos, videos, Cam's takes |
| User Content → Audio Data | Recordings added to captures; Cam's takes record sound |
| User Content → Other User Content | PDFs and files, text tabs, titles, links |

App Store Connect takes these answers in its web UI (App Privacy); the
App Store Connect API key used by `scripts/store-upload-ios.sh` can't set
them.

All six are in `PrivacyInfo.xcprivacy`, the same way.

**Data not linked to the user**, for **Analytics** only (by Google's
ML Kit, a third-party SDK; not used for tracking):

| Apple category → type | Notes |
|---|---|
| Identifiers → Device ID | The installation identifier ML Kit's metrics carry |
| Diagnostics → Performance Data | ML Kit's timings and outcomes |
| Diagnostics → Other Diagnostic Data | ML Kit's diagnostics (GoogleDataTransport) |

These come from ML Kit's own privacy manifests (MLKitCommon,
MLKitFaceDetection, GoogleDataTransport), which Xcode merges into the
app's privacy report, so the app's own manifest doesn't repeat them.
Those manifests also list Product Interaction, Other User Content and
Other Data Types, not linked, for Analytics and App Functionality: the
maintainer should check the app's privacy report (Xcode → Archive →
Generate Privacy Report) and Google's ML Kit disclosure, and add any of
them App Review expects.

## Content rating (IARC questionnaire, Play; Apple's age rating)

- **Category**: Utility, Productivity, Communication, or Other (not a
  game, not reference/news, not social).
- Violence, fear, sexuality, nudity, profanity or crude humor, drugs,
  alcohol, tobacco, gambling, simulated gambling: **No** to all.
- **Users can interact or exchange content**: **Yes**: a user can share
  their captures with specific people by email (to edit or read only),
  and copy a capture's link, which lets whoever they give it to see that
  capture, read only; there's no chat, no public feed, no search for
  other users' captures, no profile browsing. No user location is shared.
- **Digital purchases**: **No** (no in-app purchases; Premium is not sold
  in the app).
- **Unrestricted web access**: **No**: links open in the external
  browser. The one in-app web view is Cam's play-along frame, which
  shows a link the user added to the capture (a YouTube video in its
  embedded player, or that page) with no address bar or browsing.
  Arguable, since the page itself can be any link the user typed: if
  Apple counts it, the answer is Yes (and the rating goes up).
- **Messaging or chat**: **No**. **Advertising**: **No**. **Social
  media**: **No**. **Parental controls, age assurance**: **No**.
  **Health or wellness topics**: **No**. **Loot boxes, contests**: **No**.
- **User-generated content** (Apple's question): **Yes**: captures are
  the user's own, shared only with the people the owner picks, or with
  whoever they give the capture's read-only link.
- Expected result: **Everyone / PEGI 3 / USK 0** on Play; **4+** on the
  App Store ("None" throughout Apple's questionnaire, the answers above
  for its yes/no questions;
  [age-rating.json](ios/age-rating.json), which
  `scripts/store-upload-ios.sh` uploads).

## Target audience and content (Play)

- **Target age groups**: 18 and over (optionally 13–17 as well). **Not**
  under 13: the app isn't designed for children, so it stays out of the
  Families policy. The privacy policy says it's not directed to children
  under 13.
- **Appeals to children**: No.
- **Ads**: The app contains no ads.
- **News app**: No. **Government app**: No. **Health**: No. **Financial
  features**: None.
- **App access**: everything needs sign-in; provide the Google test
  account and steps (see [ios/REVIEW_NOTES.md](ios/REVIEW_NOTES.md)).

## Category

- **Google Play**: Music & Audio; tags from Play's list that fit a music tool (up to five).
- **App Store**: primary **Music**, secondary **Productivity**.
