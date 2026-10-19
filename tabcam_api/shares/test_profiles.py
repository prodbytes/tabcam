"""Profiles: IDs, find-or-create, linking, roles. With the share API's
in-memory stand-ins (test_index.py)."""

import io
import json
import os
import random
import unittest
import unittest.mock

import profiles
from test_index import (APPLE, GOOGLE, OWNER, S3, Cognito, FakeRbacr, Sts,
                        KeyTable, Table, index, seed, store)


class IdsTest(unittest.TestCase):
    def test_ids_are_two_different_adjectives_and_an_animal(self):
        adjectives, animals = profiles.words()
        self.assertGreater(len(adjectives), 1000)
        self.assertGreater(len(animals), 1000)
        rng = random.Random(7)
        for _ in range(500):
            pid = profiles.generate(rng)
            a, b, animal = pid.split("_")
            self.assertNotEqual(a, b)
            self.assertIn(animal, animals)
            self.assertTrue(profiles.valid(pid), pid)
        self.assertFalse(profiles.valid("huge_huge_darter"))
        self.assertFalse(profiles.valid("huge_wavy"))
        self.assertFalse(profiles.valid("Huge_wavy_darter"))

    def test_link_codes_are_normalized(self):
        self.assertEqual(profiles.normalize_code(" abcd-efgh "), "ABCDEFGH")


class Api(unittest.TestCase):
    def setUp(self):
        self.clients = {"table": Table(), "links": KeyTable("keyHash", {"byOwner": "owner"}), "cognito": Cognito(), "sts": Sts(),
                        "accounts": None, "store": store(),
                        "rbacr": FakeRbacr({"julio@example.com": ["free", "premium"],
                                            "admin@example.com": ["admin", "free"]}),
                        "s3": S3()}

    def call(self, route, sub, email, body=None, iss=GOOGLE, path=None):
        prefix = "/apple" if iss == APPLE else ""
        method, _, p = route.partition(" ")
        event = {
            "routeKey": f"{method} {prefix}{p}",
            "headers": {"authorization": f"Bearer {sub}"},
            "requestContext": {"authorizer": {"jwt": {"claims": {
                "iss": iss, "sub": sub, "email": email, "email_verified": "true"}}}},
            "pathParameters": path,
            "body": json.dumps(body) if body is not None else None,
        }
        r = index.handler(event, None, self.clients)
        return r["statusCode"], json.loads(r["body"])

    def profile(self, sub, email, iss=GOOGLE):
        status, body = self.call("GET /profile", sub, email, iss=iss)
        self.assertEqual(status, 200, body)
        return body


class FindOrCreateTest(Api):
    def test_a_first_sign_in_gets_a_profile_it_keeps(self):
        first = self.profile("g1", "julio@example.com")
        self.assertTrue(profiles.valid(first["profileId"]))
        self.assertEqual([(a["email"], a["provider"], a["owner"], a["you"]) for a in first["accounts"]],
                         [("julio@example.com", "google", True, True)])
        self.assertEqual(self.profile("g1", "julio@example.com")["profileId"], first["profileId"])
        self.assertNotEqual(self.profile("g2", "olga@example.com")["profileId"], first["profileId"])

    def test_a_sign_in_with_the_same_verified_address_joins_its_profile(self):
        google = self.profile("g1", "julio@example.com")
        apple = self.profile("a1", "julio@example.com", iss=APPLE)
        self.assertEqual(apple["profileId"], google["profileId"])
        self.assertEqual(sorted((a["provider"], a["owner"]) for a in apple["accounts"]),
                         [("apple", False), ("google", True)])

    def test_a_taken_id_is_skipped(self):
        st = self.clients["store"]
        taken = profiles.generate(random.Random(1))
        st.save_profile({"id": taken})
        p = profiles.Profiles(st, rng=random.Random(1))
        self.assertNotEqual(p.of(f"{GOOGLE}#g1", "x@example.com", "google")["id"], taken)

    def test_a_lost_race_takes_the_winners_profile(self):
        st = self.clients["store"]
        p = profiles.Profiles(st)
        winner = p.of(f"{GOOGLE}#g1", "x@example.com", "google")
        real_link_of = st.link_of
        calls = []

        def link_of(subject):
            calls.append(subject)
            return None if len(calls) == 1 else real_link_of(subject)
        st.link_of = link_of  # the first look missed the winner's link
        st.by_email = lambda email: []
        self.assertEqual(p.of(f"{GOOGLE}#g1", "x@example.com", "google")["id"], winner["id"])

    def test_roles_are_the_union_of_every_linked_address(self):
        self.assertEqual(self.profile("g1", "admin@example.com")["roles"], ["admin", "free"])
        status, code = self.call("POST /profile/link-code", "g1", "admin@example.com")
        status, joined = self.call("POST /profile/link", "g2", "julio@example.com",
                                   body={"code": code["code"]})
        self.assertEqual(status, 200, joined)
        self.assertEqual(joined["roles"], ["admin", "free", "premium"])
        self.assertTrue(joined["premium"])
        self.assertTrue(self.profile("g1", "admin@example.com")["premium"])


class LinkTest(Api):
    def code(self, sub, email):
        status, body = self.call("POST /profile/link-code", sub, email)
        self.assertEqual(status, 200, body)
        self.assertRegex(body["code"], r"^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$")
        return body["code"]

    def test_a_code_links_another_sign_in_once(self):
        owner = self.profile("g1", "julio@example.com")
        code = self.code("g1", "julio@example.com")
        self.profile("g2", "olga@example.com")  # its own profile, empty
        status, body = self.call("POST /profile/link", "g2", "olga@example.com",
                                 body={"code": code.lower().replace("-", " ")})
        self.assertEqual(status, 200, body)
        self.assertEqual(body["profileId"], owner["profileId"])
        self.assertEqual(len(body["accounts"]), 2)
        # The joiner's old profile is gone; the code is used up.
        self.assertEqual(len(self.clients["store"].profiles.items), 1)
        status, _ = self.call("POST /profile/link", "g3", "ana@example.com", body={"code": code})
        self.assertEqual(status, 404)

    def test_bad_and_expired_codes_are_refused(self):
        self.profile("g1", "julio@example.com")
        code = self.code("g1", "julio@example.com")
        status, body = self.call("POST /profile/link", "g2", "olga@example.com", body={"code": "AAAA-AAAA"})
        self.assertEqual((status, body["message"]), (404, "That code is wrong, already used or expired"))
        self.clients["store"].now = lambda: 1_800_000_000 + 601
        status, _ = self.call("POST /profile/link", "g2", "olga@example.com", body={"code": code})
        self.assertEqual(status, 404)

    def test_an_owner_with_data_or_links_can_not_join(self):
        self.profile("g1", "julio@example.com")
        code = self.code("g1", "julio@example.com")
        # Olga's profile has captures in the cloud.
        status, creds = self.call("POST /profile/credentials", "g2", "olga@example.com")
        self.clients["s3"].keys.append(f"{creds['identityId']}/events/x/event.json")
        status, body = self.call("POST /profile/link", "g2", "olga@example.com", body={"code": code})
        self.assertEqual(status, 409, body)
        # Refused: the code still works for someone else.
        status, _ = self.call("POST /profile/link", "g3", "ana@example.com", body={"code": code})
        self.assertEqual(status, 200)

    def test_an_account_in_its_own_profile_already(self):
        self.profile("g1", "julio@example.com")
        code = self.code("g1", "julio@example.com")
        status, _ = self.call("POST /profile/link", "g1", "julio@example.com", body={"code": code})
        self.assertEqual(status, 409)

    def test_unlinking(self):
        self.profile("g1", "julio@example.com")
        code = self.code("g1", "julio@example.com")
        _, body = self.call("POST /profile/link", "g2", "olga@example.com", body={"code": code})
        owner = next(a for a in body["accounts"] if a["owner"])
        olga = next(a for a in body["accounts"] if not a["owner"])
        status, _ = self.call("POST /profile/unlink", "g2", "olga@example.com", body={"id": owner["id"]})
        self.assertEqual(status, 409)
        status, after = self.call("POST /profile/unlink", "g1", "julio@example.com", body={"id": olga["id"]})
        self.assertEqual(status, 200)
        self.assertEqual(len(after["accounts"]), 1)
        # Olga gets a profile of her own at her next sign-in.
        self.assertNotEqual(self.profile("g2", "olga@example.com")["profileId"], after["profileId"])


class FolderTest(Api):
    def test_every_linked_sign_in_gets_the_profiles_folder(self):
        _, one = self.call("POST /profile/credentials", "g1", "julio@example.com")
        self.assertEqual(one["token"], f"openid-{one['profileId']}")
        _, again = self.call("POST /profile/credentials", "g1", "julio@example.com")
        self.assertEqual(again["identityId"], one["identityId"])
        _, apple = self.call("POST /profile/credentials", "a1", "julio@example.com", iss=APPLE)
        self.assertEqual(apple["identityId"], one["identityId"])

    def test_shares_reach_every_address_of_the_profile(self):
        seed(self.clients, GOOGLE, "owner-token", "owner@example.com", "brave_calm_otter", OWNER)
        self.call("PUT /shares/{captureId}", "owner-token", "owner@example.com",
                  path={"captureId": "abc"}, body={"email": "riff@privaterelay.appleid.com"})
        # Ana signed in with Apple (a relay address), then linked Google.
        self.profile("a1", "riff@privaterelay.appleid.com", iss=APPLE)
        _, code = self.call("POST /profile/link-code", "a1", "riff@privaterelay.appleid.com", iss=APPLE)
        self.call("POST /profile/link", "g9", "ana@example.com", body={"code": code["code"]})
        status, body = self.call("GET /shared", "g9", "ana@example.com")
        self.assertEqual([s["captureId"] for s in body["shared"]], ["abc"])
        status, creds = self.call("POST /shared/{owner}/{captureId}/credentials", "g9", "ana@example.com",
                                  path={"owner": OWNER, "captureId": "abc"})
        self.assertEqual(status, 200, creds)

    def test_only_the_owner_deletes_the_profile(self):
        self.profile("g1", "julio@example.com")
        _, code = self.call("POST /profile/link-code", "g1", "julio@example.com")
        self.call("POST /profile/link", "g2", "olga@example.com", body={"code": code["code"]})
        status, _ = self.call("DELETE /account", "g2", "olga@example.com")
        self.assertEqual(status, 409)
        status, _ = self.call("DELETE /account", "g1", "julio@example.com")
        self.assertEqual(status, 200)
        st = self.clients["store"]
        self.assertEqual((st.profiles.items, st.subjects.items), ({}, {}))
        self.assertEqual(len(self.clients["cognito"].deleted), 1)


class RbacrTest(unittest.TestCase):
    def test_roles_are_asked_cached_and_fail_closed(self):
        asked = []

        def opener(req, timeout):
            asked.append(json.loads(req.data)["email"])
            if "broken" in asked[-1]:
                raise OSError("down")
            return io.BytesIO(json.dumps({"globalRoles": ["root"], "roles": {
                "tabcam": ["free", "premium"], "presence": ["admin"]}}).encode())
        r = profiles.Rbacr(url="https://rbacr.example", token="t", opener=opener, clock=lambda: 0)
        self.assertEqual(r.union(["a@example.com", "a@example.com"]), (["free", "premium"], ["root"]))
        self.assertEqual(asked, ["a@example.com"])
        self.assertEqual(r.roles("broken@example.com"), (frozenset(), frozenset()))

    def test_token_is_read_once_from_the_ssm_parameter(self):
        calls = []

        class Ssm:
            def get_parameter(self, **kw):
                calls.append(kw)
                return {"Parameter": {"Value": "from-ssm\n"}}
        heard = []

        def opener(req, timeout):
            heard.append(req.get_header("Authorization"))
            return io.BytesIO(b'{"roles": {}}')
        with unittest.mock.patch.dict(os.environ, {"RBACR_TOKEN_PARAMETER": "/tabcam/rbacr-token"}):
            r = profiles.Rbacr(url="https://rbacr.example", opener=opener, clock=lambda: 0, ssm=Ssm())
            r.roles("a@example.com")
            r.roles("b@example.com")
        self.assertEqual(calls, [{"Name": "/tabcam/rbacr-token", "WithDecryption": True}])
        self.assertEqual(heard, ["Bearer from-ssm"] * 2)



class SignInTimeTest(unittest.TestCase):
    def test_the_sign_in_time_is_saved_at_most_hourly(self):
        from test_index import KeyTable
        clock = [1_800_000_000]
        st = profiles.Store(
            KeyTable("id", {"byIdentity": "identityId"}),
            KeyTable("subject", {"byProfile": "profileId", "byEmail": "email"}),
            KeyTable("code"), now=lambda: clock[0], keys=KeyTable("profileId"))
        p = profiles.Profiles(st)
        first = p.of("g1", "ana@example.com", "google")
        writes = []
        save = st.save_profile
        st.save_profile = lambda profile: (writes.append(dict(profile)), save(profile))
        clock[0] += 60
        p.of("g1", "ana@example.com", "google")
        self.assertEqual(writes, [])  # a minute later: nothing to write
        clock[0] += 3600
        p.of("g1", "ana@example.com", "google")
        self.assertEqual(len(writes), 1)  # an hour later: the time
        self.assertEqual(int(writes[0]["lastSignInAt"]), clock[0])
        p.of("g1", "ana@new.example.com", "google")
        self.assertEqual(len(writes), 2)  # the address changed: at once
        self.assertEqual(first["id"], writes[1]["id"])

if __name__ == "__main__":
    unittest.main()
