# Data safety, privacy labels, rating and audience (draft answers)

Draft answers for the stores' forms, derived from the code and the specs
([privacy](../specs/privacy.md) once pull request #46 is merged,
[cloud sync](../specs/cloud-sync.md),
[shared captures](../specs/shared-captures.md),
[cloud OCR](../specs/cloud-ocr.md)). Keep them in step with the privacy
policy (https://tabcam.nu01.com/privacy) and the iOS privacy manifest
(`tabcam_app/ios/Runner/PrivacyInfo.xcprivacy`): when one changes, the
others change too.

## What TabCam does with data, in short

- **Signed out**: nothing leaves the device (captures are kept in the
  app's documents; on the web, in memory).
- **Signed in with Google**: the app gets the Google account's name,
  email, photo and ID. The **email** and the **identity ID** (Cognito)
  reach TabCam's servers; the name and photo are only shown in the app.
  The user's **captures** (scanned pages, photos, videos, files, text
  tabs, titles, artists, links) sync to their own folder in AWS S3. When
  they share a capture, the **grantee's email** and role are stored. For
  Premium, the email is checked with rbacr (the maintainer's own role
  service); Premium pages are transcribed in AWS Lambda.
- **Processors**: AWS (S3, DynamoDB, Cognito, Lambda; us-east-1),
  encrypted at rest; HTTPS only. Google for sign-in.
- **No** ads, analytics, crash reporting or tracking SDKs; no data sold
  or shared for advertising.
- **ML Kit** (on-device text recognition and, on Android, the document
  scanner) may send Google anonymous diagnostics and usage metrics about
  the ML Kit APIs (GoogleDataTransport). Google's guidance on declaring
  it: https://developers.google.com/ml-kit/android-data-disclosure. The
  maintainer should confirm the answers below against that page before
  submitting.
- **Deletion**: Profile → Delete account deletes the account's cloud data
  (pull request #47); deleted files linger up to 30 days in bucket
  versions, DynamoDB backups 35 days, Lambda logs 30 days.

## Google Play: Data safety

**Overview questions**

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | Yes |
| Is all of the user data collected by your app encrypted in transit? | Yes |
| Do you provide a way for users to request that their data is deleted? | Yes: in the app (Profile → Delete account) and by the URL below |
| Account deletion URL (App content → Data deletion) | https://tabcam.nu01.com/app/ (sign in, open Profile, tap Delete account) |
| Can users create an account? | Yes, with Google sign-in (OAuth) |

**Data types** (collected = sent off the device; none is **shared**: AWS
and Google sign-in are service providers acting for TabCam, which Play
doesn't count as sharing). All are **optional**: the app works signed
out, and they're collected only when the user signs in. None is
processed ephemerally only.

| Category → type | Collected | Purposes | Notes |
|---|---|---|---|
| Personal info → Email address | Yes | App functionality, Account management | The account's email (identity, Premium check) and the emails a user shares captures with |
| Personal info → User IDs | Yes | App functionality, Account management | Cognito identity ID; Google account ID in the sign-in token |
| Personal info → Name | Yes (conservative) | App functionality | Shown in the app only, not stored on servers. Strictly not "collected" under Play's definition; declared to match the iOS manifest. The maintainer may answer No |
| Photos and videos → Photos, Videos | Yes | App functionality | Scans, photos and videos synced to the user's folder |
| Files and docs | Yes | App functionality | Files added to captures |
| App activity → Other user-generated content | Yes | App functionality | Text tabs, titles, artists, links |
| App info and performance → Diagnostics | Yes, if ML Kit's disclosure says so | Analytics (by Google ML Kit) | Anonymous ML Kit metrics; collected also signed out; confirm against Google's ML Kit page |

Not collected: location, financial info (Premium is paid through Stripe
via Substack, outside the app), health, messages, audio, contacts,
calendar, web browsing, device IDs, app interactions, crash logs.

## Apple: App Privacy labels

**Tracking**: No (no data used to track users across apps or websites;
no ATT prompt).

**Data linked to the user** (all for **App Functionality** only; none
used for tracking):

| Apple category → type | Notes |
|---|---|
| Contact Info → Email Address | Account email; shared-with emails |
| Contact Info → Name | Shown only; declared to match `PrivacyInfo.xcprivacy` |
| Identifiers → User ID | Cognito identity ID, Google account ID |
| User Content → Photos or Videos | Scans, photos, videos |
| User Content → Other User Content | Files, text tabs, titles, links |

**Data not linked to the user** (only if ML Kit's disclosure requires
it): Diagnostics → Other Diagnostic Data, for **Analytics** (third-party
SDK). If declared, add it to `PrivacyInfo.xcprivacy` as well (the
manifest in pull request #46 doesn't list it).

## Content rating (IARC questionnaire, Play; Apple's age rating)

- **Category**: Utility, Productivity, Communication, or Other (not a
  game, not reference/news, not social).
- Violence, fear, sexuality, nudity, profanity or crude humor, drugs,
  alcohol, tobacco, gambling, simulated gambling: **No** to all.
- **Users can interact or exchange content**: **Yes**: a user can share
  their captures with specific people by email (to edit or read only);
  there's no chat, no public feed, no profile browsing, and a link gives
  no access by itself. No user location is shared.
- **Digital purchases**: **No** (no in-app purchases; Premium is not sold
  in the app).
- **Unrestricted web access**: **No**: links open in the external
  browser, not an in-app web view.
- Expected result: **Everyone / PEGI 3 / USK 0** on Play; **4+** on the
  App Store (answer "None" throughout Apple's questionnaire; under its
  user-generated content questions, content is shared only with people
  the owner picks).

## Target audience and content (Play)

- **Target age groups**: 18 and over (optionally 13–17 as well). **Not**
  under 13: the app isn't designed for children, so it stays out of the
  Families policy. The privacy policy says it's not directed to children
  under 13.
- **Appeals to children**: No.
- **Ads**: The app contains no ads.
- **News app**: No. **Government app**: No. **Health**: No. **Financial
  features**: None.
- **App access**: some features need sign-in; provide the Google test
  account and steps (see [ios/REVIEW_NOTES.md](ios/REVIEW_NOTES.md)).

## Category

- **Google Play**: Music & Audio; tags from Play's list that fit a music tool (up to five).
- **App Store**: primary **Music**, secondary **Productivity**.
