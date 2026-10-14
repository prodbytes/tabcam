# Encryption at rest

Each [profile](profiles.md)'s captures are to be kept encrypted in the
cloud, readable only through that profile's keys: by its own devices, by
the people a capture is [shared](shared-captures.md) with, and by whoever
holds its [link](sharing.md). The server holds the keys (one KMS key wraps
them all), so cloud OCR and link previews keep working; it protects
against a leaked bucket or table and against one profile reaching another's
data, not against the service's operator. On the device, captures stay as
they are (the phone's own storage encryption covers them).

It comes in three stages; **stage 1 is done**.

## Keys (stage 1: done)

- **One KMS key**, `alias/tabscan-profile-keys` (the share API's stack,
  [share-api.yaml](../tabscan_infra/share-api.yaml)): symmetric, rotated
  yearly, kept if the stack goes, 30 days to undo deleting it. It never
  encrypts data itself: it wraps profiles' private keys. About $1 a month
  whatever the number of users.
- **Each profile has an RSA key pair** (RSA 3072), made by KMS
  (`GenerateDataKeyPairWithoutPlaintext`) at the profile's first request
  to the share API (a new profile at its first sign-in; one from before,
  at its next): the public key as it is (DER, SubjectPublicKeyInfo), the
  private key only wrapped by the KMS key, with the profile's ID as its
  encryption context. They're kept in their own table (`ProfileKeysTable`),
  written once with a conditional put (two first requests racing both get
  the first's pair) and never overwritten; deleting the profile deletes
  them, so nothing it left can be read again.
- **`GET /profile`** returns the public key (`publicKey`, base64) and
  `keyAlgorithm` (`RSA-OAEP-256`), for the profile's devices to wrap
  captures' keys with.
- **The private key never leaves the API** ([keys.py](../tabscan_api/shares/keys.py)):
  it's opened in the function with KMS (and kept in memory there for 5
  minutes) only to unwrap captures' keys:
  - **`POST /keys/{owner}/{captureId}`** (signed in): the capture's content
    key, for its owner's profile or a profile it's shared with (404 for
    anyone else, and for a capture that isn't there or isn't encrypted);
  - **`POST /public/{captureId}/credentials`** (a link's key): also the
    content key, `contentKey`, when the capture is encrypted;
  - **link previews** open the capture's sealed event for its title.

  The wrapped key is always read from the capture's own `event.json` (with
  that capture's read-only credentials), never taken from the caller, and
  it's bound to its capture (the OAEP label is `tabscan:<capture id>`): an
  editor of one capture can't have another's key unwrapped.
- The function's role may use the KMS key only with a `profile`
  encryption context. Its one library beyond boto3, `cryptography` (with
  `cffi` and `pycparser`), is pinned with hashes
  ([requirements.txt](../tabscan_api/shares/requirements.txt)) and bundled
  by [deploy-share-api.sh](../scripts/deploy-share-api.sh), which deploys
  the key and the table with the rest of the stack.

## Formats

[sealed.py](../tabscan_api/shares/sealed.py) is the reference.

- **A capture's content key**: 32 random bytes made on the device that
  creates the capture (AES-256-GCM), wrapped with the owner profile's
  public key (RSA-OAEP, SHA-256, label `tabscan:<capture id>`).
- **`event.json`**, encrypted: in the clear only what sync and the API
  need, `{"v": 1, "id", "updated", "owner", "key": {"alg": "RSA-OAEP-256",
  "wrapped"}, "sealed"}`; `sealed` is a 12-byte nonce, then the whole
  event's JSON encrypted with the content key (AAD: the capture's ID). A
  tombstone isn't sealed (it holds nothing).
- **A file** (a page): `TSE1`, the chunk size (4 bytes, big endian, 64 KiB
  by default), a 7-byte random nonce prefix, then the chunks: each
  AES-256-GCM with its 16-byte tag, nonce = prefix, chunk number (4 bytes)
  and 1 for the last chunk (else 0), AAD `tabscan:<capture id>/<file
  name>`. Read and written a chunk at a time (videos never whole in
  memory); chunks can't be dropped, reordered or moved between files.

## Next

- **Stage 2, the readers**: the cloud OCR service opens sealed files (it
  gets the content key the way the API does) and writes its results
  sealed; link previews already open sealed events.
- **Stage 3, the app**: new captures get a content key, wrapped with the
  profile's public key; cloud sync seals `event.json` and files going up
  and opens them coming down (content keys from `POST /keys/…`, kept with
  what synced); captures opened by their link and shared ones open theirs
  the same way. Captures from before are read as they are, and sealed the
  next time they go up. Apps from before encryption can't read sealed
  captures: they're updated first.
