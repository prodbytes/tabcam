# Caching users' files (CloudFront and the device)

Users' files are read through the site's CloudFront distribution and kept
on the device, both as each object's own `Cache-Control` says. Writes,
listings and deletes still go straight to S3 ([cloud sync](cloud-sync.md)).

## Cache-Control on every object

Set when an object is written, and kept by S3:

| Objects | Written by | `Cache-Control` |
|---|---|---|
| A page's file (`<page id>.<ext>`: photos, scans, videos, recordings, PDFs) | the app (`S3Bucket.cacheControlOf`) | `public, max-age=31536000, immutable`: written once (a changed page is a new page), so kept a year as it is |
| `event.json` (any `.json` the app writes) | the app | `no-cache`: rewritten in place, so every reader checks its `ETag` first (a 304 when unchanged) |
| `ocr/<event>/<page>.json` | the cloud OCR service ([tabcam_locr/locr/handler.py](../tabcam_locr/locr/handler.py)) | `no-cache`: a new reading rewrites it |

Objects from before have none: CloudFront doesn't keep them (its default
TTL is 0), and the device keeps them but revalidates each time.

## Through CloudFront, for signed URLs only

- **The path**: both sites' distributions (tabcam.nu01.com and
  rc.tabcam.nu01.com, [tabcam_infra/site.yaml](../tabcam_infra/site.yaml))
  serve the user-data bucket at its keys' own paths. Every folder is a
  Cognito identity ID (`us-east-1:<uuid>`), so the behavior is
  `/us-east-1:*`, with the bucket as the origin through the site's Origin
  Access Control. The web app reads from its own site (same origin, no
  CORS); the Android and iOS apps from `TABCAM_CDN_URL`. Local builds read
  S3 directly.
- **Signed URLs only**: the behavior trusts the share API's key group
  (`tabcam-user-data`, [share-api.yaml](../tabcam_infra/share-api.yaml)).
  The share API ([tabcam_api/shares/cdn.py](../tabcam_api/shares/cdn.py))
  signs a custom policy for one folder prefix, valid for an hour, and
  hands it out with the folder's credentials: the profile's own folder
  (`POST /profile/credentials`), a capture shared with the user
  (`POST /shared/{owner}/{captureId}/credentials`) and a link's capture
  (`POST /public/{captureId}/credentials`), as `cdn: {prefix, expiration,
  hosts: {host: query}}`. A policy names one exact host (a wildcard would
  let `https://site/<another folder>/.../<prefix>` match), so the grant
  has one per site. The private key is the SSM SecureString
  `/tabcam/cdn-signing-key` ([scripts/make-cdn-key.sh](../scripts/make-cdn-key.sh)).
- **Who can read**: only the bucket policy's named distributions may read
  objects (`CdnDistributionArns`, [user-data.yaml](../tabcam_infra/user-data.yaml)),
  not any of the account's: the GitHub deploy roles can make
  distributions, and must never reach users' events.
- **Cached as the objects say**: the cache policy keeps an object for its
  `max-age` (`MinTTL` 0, `DefaultTTL` 0, `MaxTTL` a year), keyed by its
  path alone. The signature is checked, then left out of the key, so
  everyone allowed to read an object shares CloudFront's copy.
- **Deleting an account** invalidates its folder (`/<identity>/*`) on both
  distributions (`CDN_DISTRIBUTIONS`), after the app has emptied it.

## On the device

`HttpCache` ([lib/cloud/http_cache.dart](../tabcam_app/lib/cloud/http_cache.dart))
is a private cache for the GETs `S3Bucket` sends to CloudFront. It's keyed
by the object's key, since the signed URL's query changes every hour:

- A copy is **fresh** while its age is under its `max-age`. Its age is its
  `Age` from CloudFront plus the time since it was stored. A fresh copy is
  used without asking. A copy with `no-cache`, or without a `max-age`, is
  never fresh: it's **revalidated** with `If-None-Match` (its `ETag`), or
  else `If-Modified-Since`, and a 304 keeps it. `no-store` is never kept.
- Streams (videos) are kept as they pass when their length is known and
  at most 64 MB. Longer ones are streamed through, unkept.
- **Where**: on Android and iOS, files in the app's cache folder
  (`user-data/<sha256 of the key>.body` and `.json`), which the system may
  empty when space runs low. On the web, IndexedDB (`tabcam-http-cache`),
  or memory when the browser refuses it. Over 512 MB, the least recently
  used go first.
- **Cleared** when the user signs out, or another account signs in.
- **Falls back**: when a key isn't under a grant, a grant is about to
  expire, the key would need URL encoding, or CloudFront answers anything
  but 200 or 304, the app reads S3 directly, as before.

## Known limitations

- A file deleted from a capture stays in CloudFront's cache until it's
  evicted, at most a year. Only the owner and the people the capture is
  shared with (or its link's holders) can read it, with a signature
  that's under an hour old.
- A share revoked, or a link removed, still reads for up to an hour, until
  its grant expires. Its S3 credentials last the same.
- Pages synced to a phone are also in its library, so a cached page is
  kept twice there, at most 512 MB of cache. The web keeps captures only
  in memory, so there the cache saves downloading them again at each
  launch.
