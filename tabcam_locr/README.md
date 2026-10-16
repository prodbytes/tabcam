# tabcam_locr: cloud OCR for TabCam Premium

Transcribes scanned tab pages in AWS Lambda for **premium** users, as the app
syncs them. Free users keep on-device reading and see an upgrade offer.
Premium is a role in [rbacr](https://github.com/prodbytes/rbacr): system
`tabcam`, role `premium`.

The engines are the combination that read tabs best in the OCR bench: each
tab string line is cut out (OpenCV), read by Tesseract, PaddleOCR and
RapidOCR, and the reading closest to the others wins.

## How it works

```
app syncs a page ──► user-data bucket ──S3 event──► EventBridge (tabcam-ocr-pages)
                                                        │
                    tabcam-ocr-api ◄───────────────────┘
                      identity ─► e-mail (tabcam-accounts table)
                      e-mail ─► rbacr /api/check (tabcam, premium)
                      premium? ─► invoke tabcam-ocr (async)
                                       │
       <identity>/ocr/<event>/<page>.json ◄┘  read by the app after its sync passes
```

- **tabcam-ocr-api** (512 MB) never loads the engines. For S3 events it
  decides who gets OCR; deleted pages lose their transcription. Its
  **function URL** serves the app, with the user's ID token as
  `Authorization: Bearer`:
  - `POST /account` checks the token by its issuer: Google's (Google's
    signature, TabCam's web client) or, with `APPLE_CLIENT_ID` set,
    Apple's (Sign in with Apple: Apple's signature, the bundle ID), with a
    verified e-mail (Apple's `email_verified` is a string). An Apple token
    without `APPLE_CLIENT_ID` gets 403 `google sign-in needed`. It asks the
    identity pool for the token's identity ID (under the issuer's `Logins`
    key), and records identity → e-mail (S3 events only carry the
    identity ID). It answers
    `{email, premium, expiresAt, checked, upgradeUrl, voucherUrl}`.
  - `POST /transcribe {"eventId"}` queues the event's synced pages that have
    no transcription yet (pages from before upgrading). Premium only (402).
  - `POST /autocorrect {"eventId", "song", "text"}` checks a text tab
    against the song's tab found online: Claude, with web search and web
    fetch, answers with corrections by note id, which are checked against
    the reading ([locr/autocorrect.py](locr/autocorrect.py),
    [specs](../specs/autocorrect.md)). Premium only (402); 503 without the
    Claude API key. It can take a few minutes, so the function's timeout
    is 300 s.
- **tabcam-ocr** (3008 MB, the account's cap; 5 min) reads one page and writes
  `{page, status: ok|no-tab|error, text, staves, lines, seconds, engines,
  version, created}`.
- **Premium** comes from rbacr, asked with a root-owned API token kept in
  SSM Parameter Store (the SecureString `/tabcam/rbacr-token`). Paying subscribers of
  prodbytes.substack.com get it from rbacr's Stripe sync (the `tabcam`
  system's subscriber role is `premium`), if they subscribe with the same
  address they sign in with (Google's, or the Apple ID's; Apple's private
  relay addresses match none). Others can get it from a voucher (redeemed on rbacr's
  `/me`) or a root's grant. rbacr not answering means "not premium" (it
  fails closed). A "yes" is cached up to 5 minutes, a "no" for 1.

## Code

| Path | What |
|---|---|
| [locr/pipeline.py](locr/pipeline.py) | page → lines → staves → per-line readings → vote → text tab, with the notations off the staves (chords, lyrics) |
| [locr/engines.py](locr/engines.py) | Tesseract, PaddleOCR, RapidOCR on one line strip; RapidOCR on the page off the staves |
| [locr/handler.py](locr/handler.py) | the two Lambda handlers (`api`, `ocr`) |
| [locr/autocorrect.py](locr/autocorrect.py) | `/autocorrect`: the reading's notes, Claude's corrections, checked |
| [locr/auth.py](locr/auth.py) | ID token check (Google, Apple), Cognito identity |
| [locr/premium.py](locr/premium.py) | rbacr's premium check |
| [locr/keys.py](locr/keys.py) | the bucket's keys, strictly parsed |
| [locr/selftest.py](locr/selftest.py) | reads a made-up riff and its title back (image build, `scripts/test-image.sh`) |
| [Dockerfile](Dockerfile) | Debian trixie (Tesseract 5.5), the pinned packages, the PaddleOCR models |
| [../tabcam_infra/ocr.yaml](../tabcam_infra/ocr.yaml), [ocr-repo.yaml](../tabcam_infra/ocr-repo.yaml) | the stacks |

## Test

```bash
cd tabcam_locr
uv venv -p 3.12 .venv && uv pip install -p .venv/bin/python -r requirements-dev.txt
.venv/bin/python -m pytest -q                  # handler, premium, keys, pipeline logic
docker build --platform linux/amd64 -t tabcam-ocr:dev .   # fails if it can't read the riff
bash scripts/test-image.sh tabcam-ocr:dev     # read-only, not root, as in Lambda
```

The image build runs the self-test (`--min 0.8` of the riff's notes). The
riff is invented: tests never use published songs' tabs.

## Deploy

An administrator, once the user-data bucket exists (`tabcam-user-data`,
with EventBridge on) and the rbacr token is in SSM Parameter Store (a
standard-tier SecureString under the AWS-managed `aws/ssm` key: free, where
a Secrets Manager secret costs $0.40 a month):

```bash
aws ssm put-parameter --name /tabcam/rbacr-token --type SecureString \
  --tier Standard --value file:///dev/stdin <<< "$ROOT_OWNED_RBACR_TOKEN"   # once
aws secretsmanager create-secret --name tabcam/anthropic-api-key \
  --secret-string file:///dev/stdin <<< "$ANTHROPIC_API_KEY"        # once, for /autocorrect
bash tabcam_locr/scripts/deploy.sh
```

It deploys `tabcam-ocr-repo` (ECR, immutable tags, last 10 images kept),
builds and pushes the image, and deploys `tabcam-ocr` with the image's
digest. `TABCAM_GOOGLE_WEB_CLIENT_ID` and `TABCAM_COGNITO_IDENTITY_POOL_ID` (environment
or `.env`) set up the function URL; without them, page OCR still runs but
the URL refuses every request. With `TABCAM_APPLE_SIGN_IN=1` it also
passes `AppleClientId=com.nu01.tabcam`, so Sign in with Apple's tokens are
taken. The script prints the URL: set it as the
app's `TABCAM_OCR_URL` (`.env`, and the repository variable for deploys
and releases).

## Limits

- The account's Lambda concurrency limit (10 by default for new accounts)
  is shared; no concurrency is reserved for OCR. Raise the quota before
  many users go premium.
- About 30 s per page of six staves on Lambda (≈75 s under x86 emulation
  on a Mac), plus a cold start that loads the models.
- Reads text tabs (dash lines). Typeset staves with drawn lines aren't
  found; the app's on-device reading handles those.
- The function URL has no rate limit beyond Lambda's; every request needs a
  valid Google token for TabCam's client (or Apple token for its bundle
  ID).
