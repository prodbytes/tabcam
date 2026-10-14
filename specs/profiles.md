# Profiles

What a TabScan user's data belongs to, as in Presence: a **profile**, not a
sign-in. The ways its owner signs in (Google, Apple; several accounts) are
linked to it, and each reaches the same captures. The profile's **roles**
are every linked account's rbacr roles together.

## The profile ID

- Two different adjectives and an animal, lowercase, joined by `_`:
  `huge_wavy_darter`.
- The words are Presence's lists
  ([adjectives.txt](../tabscan_api/shares/adjectives.txt), 1053;
  [animals.txt](../tabscan_api/shares/animals.txt), 1031): a-z only, each
  unique, no insults. About 1.1 billion IDs.
- Made by the share API only, with a cryptographic random source
  (`secrets.SystemRandom`), on a conditional write; a taken ID is skipped
  (10 tries). An ID is a name, not a secret: what protects a profile is
  that only its linked sign-ins' tokens reach it.

## Sign-ins and profiles

- A sign-in is its **subject**: `<issuer>#<sub>` of its ID token
  (`https://accounts.google.com#…`, `https://appleid.apple.com#…`), never
  the email, which can change hands. Only verified addresses are used.
- **First sign-in**: the first request the share API sees from a subject
  finds its profile, or makes one:
  1. linked already: that profile (its last sign-in noted; the owner's
     address kept current);
  2. else a profile with another sign-in of the same **verified address**
     (Google and Apple with the same email, say): joined, automatically;
  3. else a new profile, owned by this sign-in.

  Two first requests racing: the first link wins, the other takes it.
- **Linking another account** (Profile → **Linked accounts**):
  1. **Get a link code** on a signed-in device: 8 characters from
     `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (40 bits), shown `ABCD-EFGH`, good
     for 10 minutes and once; kept only as its SHA-256.
  2. Sign in with the other account (any device), Linked accounts, enter
     the code, **Link this account**: it joins that profile, and from then
     reaches its captures.

  Refused (409), leaving the code usable: the account owns a profile that
  has other accounts linked ("unlink them first") or captures in the cloud
  (nothing is moved between folders). An account that's linked but not an
  owner may move. The joiner's empty profile is deleted. Wrong, used or
  expired codes are 404; tries are limited to 1 a second (5 at once).
- **Unlinking**: any account but the owner, by anyone in the profile
  (409 for the owner). An account unlinked gets a profile of its own at
  its next request.
- **Deleting** (Profile → Delete account) deletes the whole profile: only
  its owner may (409 otherwise; the app shows the owner-only note instead
  of the button).

## Roles

- rbacr's `POST /api/roles` for each linked account's address (a root's
  token, `tabscan/rbacr-token`), cached a minute, failing closed (no
  roles): the profile's roles are the union of the `tabscan` system's
  roles (`free`, `premium`, `admin`; rbacr's answer already includes the
  implied ones), and `globalRoles` too. **Premium** if any linked account
  is premium.
- The cloud OCR service decides Premium the same way: the profile of the
  request's sign-in, any of its addresses premium
  ([cloud OCR](cloud-ocr.md#who-is-premium)).

## Storage

- Each profile has its key pair, for [encryption at rest](encryption.md):
  made at its first request, deleted with it.

- The profile's folder is its **Cognito developer identity** in the main
  pool (developer provider `login.tabscan.profiles`, the profile ID as the
  user identifier): `POST /profile/credentials` gets an OpenID token for
  it (`GetOpenIdTokenForDeveloperIdentity`, 1 hour) and the app exchanges
  it with `GetCredentialsForIdentity` (`Logins:
  {"cognito-identity.amazonaws.com": token}`), so every linked sign-in
  gets credentials for the same `<identity>/` folder
  ([cloud sync](cloud-sync.md#folders)).
- Sharing works by profile: the owner of a capture is the profile's
  identity, and a grant to any of the profile's addresses reaches every
  linked account ([shared captures](shared-captures.md)).
- On the device, when the same user's folder changes (joining a profile,
  or the move to profiles), their own captures move with them: sync
  remembers whose state it is, and gives the old folder's unshared
  captures to the new one, which they upload to. Another user's captures
  on the device stay theirs.

## API

On the share API ([shared captures](shared-captures.md#how-it-works)),
each route also under `/apple` for Apple's tokens:

| Route | What |
|---|---|
| `GET /profile` | `{profileId, accounts: [{id, email, provider, owner, you}], roles, globalRoles, premium}`; `id` is a hash of the subject |
| `POST /profile/link-code` | `{code, expiresAt}` |
| `POST /profile/link` `{code}` | joins its profile; the profile |
| `POST /profile/unlink` `{id}` | the profile after, or `{unlinked: true}` for oneself |
| `POST /profile/credentials` | `{profileId, identityId, token}` |

Tables (`tabscan-share-api`): **profiles** (`id`; `ownerSubject`,
`ownerEmail`, `identityId`, `createdAt`, `lastSignInAt`; index
`byIdentity`), **subjects** (`subject`; `profileId`, `email`,
`provider`, `linkedAt`; indexes `byProfile`, `byEmail`), **link codes**
(`code` = SHA-256; `profileId`, `createdBy`, `expiresAt` with TTL). The
first two are retained and have point-in-time recovery.

## In the app

- Profile tab, signed in: **Profile: huge_wavy_darter** (selectable),
  **Roles: admin, free, premium**, and **Linked accounts (n)**, which opens
  a sheet: the accounts (Google or Apple, its address, *Owner*, *This
  account*; **Unlink** but for the owner), **Get a link code** (the code,
  how to use it, Copy), and the code field with **Link this account**.
  Errors: a wrong code, can't link (data or links of its own), too many
  tries. Texts in English, Spanish and Portuguese.
- The profile is asked for at each sign-in and when the Profile tab
  opens. Linking or unlinking this account clears the credentials, syncs
  again and checks Premium again.
- Builds without the share API (local web builds) have no profiles: each
  sign-in is its own folder, as before.

## Verified

- Share API (unittest, in-memory DynamoDB, Cognito and rbacr): IDs (format,
  word lists, two different adjectives), a first sign-in's profile kept,
  the same verified address joining, a taken ID skipped, a lost race,
  roles as the union, link codes (format, single use, expiry, wrong,
  normalized), owners with data or links refused, unlinking (not the
  owner), every linked sign-in getting the same folder, shares reaching
  every address, deleting by the owner only; rbacr asked, cached, failing
  closed; the earlier sharing tests on profiles.
- Cloud OCR (pytest): a profile premium through any address, its folder
  recorded; no folder yet, nothing queued; the token's subject.
- App: profile credentials (the share API's token, then Cognito); the
  profile at sign-in and gone at sign-out; linking clears the
  credentials and checks Premium; a moved folder takes the user's
  captures, another user's stay; the Profile tab and the sheet (code,
  wrong code, unlink); a non-owner can't delete.

## Known limitations

- No data is merged between profiles: an account with captures in the
  cloud can't join another profile.
- Profiles aren't deleted when their last account is unlinked from them by
  someone else; an unused profile only costs a row.
- Folders from before profiles (each sign-in's own identity) stay in the
  bucket until deleted by hand.
