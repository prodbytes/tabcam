# tabscan_locr: cloud OCR for TabScan Premium

Transcribes scanned tab pages in AWS Lambda for **premium** users, as the app
syncs them. Free users keep on-device reading and see an upgrade offer.
Premium is a role in [rbacr](https://github.com/prodbytes/rbacr): system
`tabscan`, role `premium`.

The engines are the combination that read tabs best in the OCR bench: each
tab string line is cut out (OpenCV), read by Tesseract, PaddleOCR and
RapidOCR, and the reading closest to the others wins.

## How it works

```
app syncs a page ──► user-data bucket ──S3 event──► EventBridge (tabscan-ocr-pages)
                                                        │
                    tabscan-ocr-api ◄───────────────────┘
                      identity ─► e-mail (tabscan-accounts table)
                      e-mail ─► rbacr /api/check (tabscan, premium)
                      premium? ─► invoke tabscan-ocr (async)
                                       │
       <identity>/ocr/<event>/<page>.json ◄┘  read by the app after its sync passes
```

- **tabscan-ocr-api** (512 MB) never loads the engines. For S3 events it
  decides who gets OCR; deleted pages lose their transcription. Its
  **function URL** serves the app, with the user's Google ID token as
  `Authorization: Bearer`:
  - `POST /account` checks the token (Google's signature, TabScan's web
    client, a verified e-mail), asks the identity pool for the token's
    identity ID, and records identity → e-mail (S3 events only carry the
    identity ID). It answers
    `{email, premium, expiresAt, checked, upgradeUrl, voucherUrl}`.
  - `POST /transcribe {"eventId"}` queues the event's synced pages that have
    no transcription yet (pages from before upgrading). Premium only (402).
- **tabscan-ocr** (3008 MB, the account's cap; 5 min) reads one page and writes
  `{page, status: ok|no-tab|error, text, staves, lines, seconds, engines,
  version, created}`.
- **Premium** comes from rbacr, asked with a root-owned API token kept in
  Secrets Manager (`tabscan/rbacr-token`). Paying subscribers of
  prodbytes.substack.com get it from rbacr's Stripe sync (the `tabscan`
  system's subscriber role is `premium`), if they subscribe with the same
  Google address. Others can get it from a voucher (redeemed on rbacr's
  `/me`) or a root's grant. rbacr not answering means "not premium" (it
  fails closed). A "yes" is cached up to 5 minutes, a "no" for 1.

## Code

| Path | What |
|---|---|
| [locr/pipeline.py](locr/pipeline.py) | page → lines → staves → per-line readings → vote → text tab |
| [locr/engines.py](locr/engines.py) | Tesseract, PaddleOCR, RapidOCR on one line strip |
| [locr/handler.py](locr/handler.py) | the two Lambda handlers (`api`, `ocr`) |
| [locr/auth.py](locr/auth.py) | Google ID token check, Cognito identity |
| [locr/premium.py](locr/premium.py) | rbacr's premium check |
| [locr/keys.py](locr/keys.py) | the bucket's keys, strictly parsed |
| [locr/selftest.py](locr/selftest.py) | reads a made-up riff back (image build, `scripts/test-image.sh`) |
| [Dockerfile](Dockerfile) | Debian trixie (Tesseract 5.5), the pinned packages, the PaddleOCR models |
| [../tabscan_infra/ocr.yaml](../tabscan_infra/ocr.yaml), [ocr-repo.yaml](../tabscan_infra/ocr-repo.yaml) | the stacks |

## Test

```bash
cd tabscan_locr
uv venv -p 3.12 .venv && uv pip install -p .venv/bin/python -r requirements-dev.txt
.venv/bin/python -m pytest -q                  # handler, premium, keys, pipeline logic
docker build --platform linux/amd64 -t tabscan-ocr:dev .   # fails if it can't read the riff
bash scripts/test-image.sh tabscan-ocr:dev     # read-only, not root, as in Lambda
```

The image build runs the self-test (`--min 0.8` of the riff's notes). The
riff is invented: tests never use published songs' tabs.

## Deploy

An administrator, once the user-data bucket exists (`tabscan-user-data`,
with EventBridge on) and the rbacr token is in Secrets Manager:

```bash
aws secretsmanager create-secret --name tabscan/rbacr-token \
  --secret-string file:///dev/stdin <<< "$ROOT_OWNED_RBACR_TOKEN"   # once
bash tabscan_locr/scripts/deploy.sh
```

It deploys `tabscan-ocr-repo` (ECR, immutable tags, last 10 images kept),
builds and pushes the image, and deploys `tabscan-ocr` with the image's
digest. `TABSCANNER_GOOGLE_WEB_CLIENT_ID` and `TABSCANNER_COGNITO_IDENTITY_POOL_ID` (environment
or `.env`) set up the function URL; without them, page OCR still runs but
the URL refuses every request. The script prints the URL: set it as the
app's `TABSCANNER_OCR_URL` (`.env`, and the repository variable for deploys
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
  valid Google token for TabScan's client.
