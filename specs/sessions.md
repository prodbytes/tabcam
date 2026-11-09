# Sign-in sessions

Signed in, the user stays signed in: through reloads, restarts and long
breaks, until they sign out or leave TabCam unused for a **week**. The
provider's ID token (Google's, Apple's, the email user pool's) lasts only
an hour, and the app can't always renew it quietly (Google on the web
needs the browser's FedCM to cooperate, which a background tab, Safari or
Firefox often don't; Apple can't renew at all), so TabCam keeps a session
of its own, in the share API
([sessions.py](../tabcam_api/shares/sessions.py)).

## How it works

- **Starting**: once a provider signs the user in, the app sends that
  provider's ID token to `POST /session` (under `/apple` or `/email` for
  theirs, behind the same authorizers as every route). The share API
  links the sign-in to its [profile](profiles.md) if it isn't yet and
  answers with a **refresh token** and TabCam's first **ID token**.
- **The refresh token**: 256 random bits (`tcs1.…`), kept on the device
  and, by the API, only as its SHA-256 (table `SessionsTable`). Each use
  moves its end to **7 days later**, never past **90 days** after the
  sign-in (`expiresAt`, also DynamoDB's TTL). It isn't rotated, so two
  tabs of the web app share one session. A tab never overwrites or clears
  a newer session another tab kept on the device; refused, it takes that
  one instead of signing out.
- **TabCam's ID tokens**: JWTs (RS256) signed by a KMS key
  (`alias/tabcam-sessions`, RSA 2048; the private key never leaves KMS),
  for an hour, issued by the API's own `/session` (`SessionIssuer`), for
  the audience `tabcam-app`. They name the sign-in that started the
  session: `sub` and `idp` (its provider's subject and issuer, as the
  profiles know it), `idp_aud` (the provider token's audience, which
  revoking Apple's tokens needs) and the sign-in's verified `email` (the
  link's, so a changed address follows).
- **Checking them**: the discovery document and the public key are public
  routes (`GET /session/.well-known/openid-configuration` and
  `…/jwks.json`, cached an hour). The share API's routes take TabCam's
  tokens under `/tabcam` (a JWT authorizer of their own, and the function
  checks the audience and that `idp` is one of the providers), and the
  cloud OCR service checks them like the providers' (`SESSION_ISSUER`,
  [cloud OCR](cloud-ocr.md)), with the profile's folder and addresses.
- **Renewing**: `POST /session/refresh` with `{refreshToken}` (no
  authorizer; the stage's throttling, as every route) gives a new ID
  token. The app renews five minutes before each expires, timed by the
  token's own lifetime (`exp - iat`) from when it arrived, so a device
  clock that's off doesn't matter (and never sooner than 30 seconds);
  also when it comes back to the front, and when a token is read already
  about to expire (a throttled tab's timer may be late), at most every 20
  seconds. A kept session whose token expired is renewed at launch before
  anything uses it. Offline, or any answer but a refusal (a 404 or 5xx:
  a deploy gone wrong), it tries again a minute later and keeps the
  session.
- **Ending**: **Sign out** sends `POST /session/end`, forgets the session
  on the device and signs out of the provider. The API ends a sign-in's
  sessions when its account is deleted or another sign-in of the profile
  unlinks it (unlinking itself, it stays signed in, with a profile of its
  own); and a sign-in no longer linked to a profile can't refresh. A
  refused renewal (401) signs the user out here, "You were signed out (a week
  without using TabCam, or your sign-in ended elsewhere): sign in
  again.", unless the provider still has them signed in, in which case a
  new session starts quietly. At launch, an Apple sign-in the user
  stopped using with TabCam (Settings → Apple ID) ends the session too,
  on the device and at the API.

## In the app

`SessionAuthService`
([session_auth_service.dart](../tabcam_app/lib/auth/session_auth_service.dart))
wraps the providers' sign-in (Google, Apple, email, or several), in builds
with the share API:

- Its user is the session's (restored at launch from the device at once,
  even with an expired ID token, which is renewed straight away), or else
  the provider's; its ID token is TabCam's, or the provider's until a
  session starts. A provider losing its own token (Apple's expiring,
  Google's quiet renewal failing) leaves the user signed in, and its
  errors don't show while the session lasts.
- With a session restored, the providers don't look for a sign-in of
  their own at launch (`skipQuietSignIn`: on the web, Google's FedCM
  prompt would show for nothing).
- Another account signing in replaces the session (the old one is
  ended).
- Kept on the device (`SessionKeeper`): `session.json` in the app's
  private Application Support folder on Android and iOS, the browser's
  `localStorage` (`tabcam.signed-in`) on the web: who (ID, email, name,
  photo URL, provider), the refresh token and the last ID token.
- Requests with TabCam's token go to the share API under `/tabcam`
  (`ShareApi`); `AuthProvider.ofToken` names its `idp`.
- Without sessions at the API (a 404, or offline), the provider's token
  is used as before, and a session is tried again with the provider's
  next token or when the app comes back to the front. Builds without the
  share API (local web builds) have no sessions.

## Upgrading

Someone signed in before sessions existed stays signed in: at the next
launch the provider's still valid token (or the email refresh token)
starts a session, with no prompt.

## Security

- The refresh token is the only long-lived secret, on the device as the
  email sign-in's refresh token is (the app's private folder, or the
  browser's `localStorage`, which a script injected into the site could
  read, as it can the tokens already kept there). The API keeps only its hash,
  and it can't be guessed (256 bits; the refresh route is throttled).
- A TabCam token can't start another session (so 90 days is a real
  limit), and the API takes one only with its own audience and a known
  provider in `idp`.
- The function may only `kms:Sign` and `kms:GetPublicKey` with the
  session key, and read and write the sessions table.
- The cloud OCR service takes a session's token only where it takes the
  provider that started it (an Apple-started one without
  `APPLE_CLIENT_ID` gets "google sign-in needed", as Apple's own).
- API Gateway reads the issuer's discovery document when it makes the
  `/tabcam` authorizer, and this API serves it, so the first deploy goes
  in two steps (the stack's `SessionAuthorizer` parameter):
  `scripts/deploy-share-api.sh` deploys without the authorizer and its
  routes while the document doesn't answer yet, uploads the code, then
  deploys again with them; later deploys, in one step.
- `scripts/deploy-share-api.sh` checks, after deploying, the discovery
  document and keys, that `/tabcam/…` and an unknown refresh token are
  refused, and that a real TabCam token (signed by the session key, for a
  made-up sign-in) passes the authorizer (`POST /tabcam/session`, which
  refuses it with 400 and writes nothing).

## Costs

The sessions table (on demand, an item per signed-in device, removed by
TTL), the KMS key (about $1 a month) and a signature per renewal (about
one an hour per active user): all small, for everyone, as sign-in is.

## Tests

`tabcam_api/shares/test_sessions.py` (a real RSA key behind a stand-in for
KMS; tokens checked against the published JWKS): a session's token
reaches the same profile; a week unused ends it, use keeps it a week
longer, 90 days ends it anyway; sign-out, unlinking and deleting the
account end it, unlinking itself doesn't; wrong refresh tokens, other audiences, unknown or
TabCam's own `idp`, and tampered tokens are refused; an Apple session
keeps the audience for revoking. `tabcam_locr/tests/test_auth.py`: the OCR
service takes session tokens as the sign-in that started them, and
refuses them when anything is off or sessions aren't set up.
`tabcam_app/test/session_sign_in_test.dart`: a sign-in starts a session,
used and kept; the provider losing its token leaves the user signed in;
a kept session comes back at launch with an expired token and is renewed,
with no provider prompt; renewal five minutes early, and a minute later
offline or on a 404; a device clock an hour ahead renews once an hour,
with no loop; a refused renewal signs out with its message, takes
another tab's newer session, or starts a new session when the provider
still has the user; renewing leaves another tab's newer session alone; sign-out ends it
everywhere; without sessions the provider's token is used; another
account replaces it; an Apple ID no longer used ends it; deleting the
account asks Apple for the session's user; tokens go under `/tabcam`.
