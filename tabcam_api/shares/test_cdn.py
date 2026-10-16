"""CloudFront signed URLs (cdn.py), and the API handing them out."""

import base64
import json
import os
import unittest
from unittest import mock

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

import cdn
import test_index

KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
PEM = KEY.private_bytes(
    serialization.Encoding.PEM,
    serialization.PrivateFormat.PKCS8,
    serialization.NoEncryption(),
)
HOSTS = ["tabcam.nu01.com", "rc.tabcam.nu01.com"]
OWNER = test_index.OWNER


def _decode(value):
    return base64.b64decode(value.translate(str.maketrans("-_~", "+=/")))


def _parts(query):
    return dict(p.split("=", 1) for p in query.split("&"))


class SignerTest(unittest.TestCase):
    def setUp(self):
        self.signer = cdn.Signer("K2ABCDEF", PEM, HOSTS)

    def test_a_grant_signs_one_folder_for_an_hour_on_each_site(self):
        grant = self.signer.grant(f"{OWNER}/", now=1_000)
        self.assertEqual(grant["prefix"], f"{OWNER}/")
        self.assertEqual(grant["expiration"], 1_000 + 3600)
        self.assertEqual(sorted(grant["hosts"]), sorted(HOSTS))
        for host, query in grant["hosts"].items():
            parts = _parts(query)
            self.assertEqual(parts["Key-Pair-Id"], "K2ABCDEF")
            policy = _decode(parts["Policy"])
            statement = json.loads(policy)["Statement"]
            # One exact host: a wildcard there would match other folders.
            self.assertEqual(statement, [{
                "Resource": f"https://{host}/{OWNER}/*",
                "Condition": {"DateLessThan": {"AWS:EpochTime": 4_600}},
            }])
            KEY.public_key().verify(_decode(parts["Signature"]), policy,
                                    padding.PKCS1v15(), hashes.SHA1())
            self.assertNotRegex(parts["Policy"] + parts["Signature"], r"[+/=]")

    def test_only_folder_prefixes_are_signed(self):
        for prefix in [OWNER, f"{OWNER}/*", f"{OWNER}/?x/", ""]:
            with self.assertRaises(ValueError):
                self.signer.grant(prefix)

    def test_no_signer_without_its_settings(self):
        with mock.patch.dict(os.environ, {"CDN_KEY_PAIR_ID": "", "CDN_HOSTS": ""}):
            self.assertIsNone(cdn.load(ssm=None))

    def test_the_signer_reads_its_key_from_ssm(self):
        class Ssm:
            def get_parameter(self, Name, WithDecryption):
                assert Name == "/tabcam/cdn-signing-key" and WithDecryption
                return {"Parameter": {"Value": PEM.decode()}}

        env = {"CDN_KEY_PAIR_ID": "K2ABCDEF", "CDN_SIGNING_KEY_PARAMETER": "/tabcam/cdn-signing-key",
               "CDN_HOSTS": ",".join(HOSTS)}
        with mock.patch.dict(os.environ, env):
            signer = cdn.load(Ssm())
        self.assertEqual(signer.hosts, HOSTS)

    def test_invalidating_a_folder_asks_each_site(self):
        calls = []

        class CloudFront:
            def create_invalidation(self, **kwargs):
                calls.append(kwargs)

        with mock.patch.dict(os.environ, {"CDN_DISTRIBUTIONS": "E1,E2"}):
            self.assertEqual(cdn.invalidate(CloudFront(), f"{OWNER}/", now=7), ["E1", "E2"])
        self.assertEqual([c["DistributionId"] for c in calls], ["E1", "E2"])
        self.assertEqual(calls[0]["InvalidationBatch"]["Paths"],
                         {"Quantity": 1, "Items": [f"/{OWNER}/*"]})


class CloudFront:
    def __init__(self):
        self.paths = []

    def create_invalidation(self, DistributionId, InvalidationBatch):
        self.paths += [(DistributionId, p) for p in InvalidationBatch["Paths"]["Items"]]


class ApiTest(test_index.ShareApiTest):
    """The share API's routes, with a signer and CloudFront."""

    def setUp(self):
        super().setUp()
        self.clients["cdn"] = lambda: cdn.Signer("K2ABCDEF", PEM, HOSTS)
        self.clients["cloudfront"] = CloudFront()

    def test_the_profiles_credentials_come_with_its_folders_grant(self):
        status, body = self.call("POST /profile/credentials", "julio@example.com")
        self.assertEqual(status, 200)
        self.assertEqual(body["prefix"], f"{OWNER}/")
        self.assertEqual(body["cdn"]["prefix"], f"{OWNER}/")
        self.assertEqual(sorted(body["cdn"]["hosts"]), sorted(HOSTS))

    def test_shared_and_linked_credentials_come_with_the_captures_grant(self):
        self.grant("ana@example.com")
        status, creds = self.call("POST /shared/{owner}/{captureId}/credentials",
                                  "ana@example.com", token="ana",
                                  path={"owner": OWNER, "captureId": "abc"})
        self.assertEqual(status, 200)
        self.assertEqual(creds["cdn"]["prefix"], f"{OWNER}/events/abc/")
        self.publish()
        status, creds = self.open_link()
        self.assertEqual(status, 200)
        self.assertEqual(creds["cdn"]["prefix"], f"{OWNER}/events/abc/")

    def test_deleting_the_account_drops_its_folder_from_cloudfront(self):
        with mock.patch.dict(os.environ, {"CDN_DISTRIBUTIONS": "E1,E2"}):
            status, _ = self.call("DELETE /account", "julio@example.com")
        self.assertEqual(status, 200)
        self.assertEqual(self.clients["cloudfront"].paths,
                         [("E1", f"/{OWNER}/*"), ("E2", f"/{OWNER}/*")])

    def test_without_a_signer_credentials_still_come(self):
        def broken():
            raise RuntimeError("no parameter")

        self.clients["cdn"] = broken
        status, body = self.call("POST /profile/credentials", "julio@example.com")
        self.assertEqual(status, 200)
        self.assertNotIn("cdn", body)


if __name__ == "__main__":
    unittest.main()
