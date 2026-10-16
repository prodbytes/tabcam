"""Reading the user-data bucket through the sites' CloudFront distributions.

The sites (tabcam_infra/site.yaml) serve the bucket's keys at the same paths
(`/<identity>/events/...`), for signed URLs only: a custom policy for one
folder prefix, signed by the key whose public half is in the share API's
CloudFront key group (tabcam_infra/share-api.yaml). The API hands one out
with each set of folder credentials: the same prefix, the same hour.

A policy names one exact host (a wildcard there would also match
`https://site/<another folder>/.../<prefix>`), so a grant carries a query
string per site; the app appends its own site's to every GET under the
prefix. The cache key leaves the query out, so everyone allowed to read an
object shares CloudFront's copy.
"""

import base64
import json
import os
import time

# As long as the folder credentials it comes with (STS's DurationSeconds).
LIFETIME = 3600


def _url_safe(data):
    """CloudFront's base64: + = / become - _ ~."""
    return base64.b64encode(data).decode().translate(str.maketrans("+=/", "-_~"))


class Signer:
    def __init__(self, key_pair_id, private_key_pem, hosts):
        from cryptography.hazmat.primitives import serialization

        self.key_pair_id = key_pair_id
        self.hosts = [h for h in hosts if h]
        self._key = serialization.load_pem_private_key(private_key_pem, password=None)

    def _sign(self, host, prefix, expires):
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.asymmetric import padding

        policy = json.dumps(
            {
                "Statement": [
                    {
                        "Resource": f"https://{host}/{prefix}*",
                        "Condition": {"DateLessThan": {"AWS:EpochTime": expires}},
                    }
                ]
            },
            separators=(",", ":"),
        ).encode()
        # CloudFront checks signed URLs' signatures as RSA-SHA1.
        signature = self._key.sign(policy, padding.PKCS1v15(), hashes.SHA1())
        return (
            f"Policy={_url_safe(policy)}&Signature={_url_safe(signature)}"
            f"&Key-Pair-Id={self.key_pair_id}"
        )

    def grant(self, prefix, now=None):
        """GETs of every key under [prefix] (a folder's, ending in /) for
        the next hour, on each site."""
        if not prefix.endswith("/") or "*" in prefix or "?" in prefix:
            raise ValueError(f"not a folder prefix: {prefix!r}")
        expires = int(now if now is not None else time.time()) + LIFETIME
        return {
            "prefix": prefix,
            "expiration": expires,
            "hosts": {h: self._sign(h, prefix, expires) for h in self.hosts},
        }


def load(ssm):
    """The signer, when the stack has set it up (the key pair's ID, the
    private key's SecureString parameter and the sites); otherwise None."""
    key_pair_id = os.environ.get("CDN_KEY_PAIR_ID")
    parameter = os.environ.get("CDN_SIGNING_KEY_PARAMETER")
    hosts = (os.environ.get("CDN_HOSTS") or "").split(",")
    if not key_pair_id or not parameter or not any(hosts):
        return None
    pem = ssm.get_parameter(Name=parameter, WithDecryption=True)["Parameter"]["Value"]
    return Signer(key_pair_id, pem.encode(), hosts)


def invalidate(cloudfront, prefix, now=None):
    """Drops CloudFront's copies of everything under [prefix] on each site
    (a deleted account's folder); returns the distributions asked."""
    ids = [d for d in (os.environ.get("CDN_DISTRIBUTIONS") or "").split(",") if d]
    for distribution in ids:
        cloudfront.create_invalidation(
            DistributionId=distribution,
            InvalidationBatch={
                "Paths": {"Quantity": 1, "Items": [f"/{prefix}*"]},
                "CallerReference": f"{prefix}{int(now if now is not None else time.time())}",
            },
        )
    return ids
