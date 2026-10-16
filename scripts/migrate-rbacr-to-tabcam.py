"""Mirrors rbacr's tabscan system as tabcam, once, for the rename: the same
roles (with what they imply and which everyone holds), the URL at
tabcam.nu01.com, and every grant that's still active, with its validity.

    python3 -I scripts/migrate-rbacr-to-tabcam.py            # dry run
    python3 -I scripts/migrate-rbacr-to-tabcam.py --apply

Vouchers stay on tabscan (codes are unique; Presence's grant tabscan
Premium): counted, not copied. Uses the root token in SSM
(/tabcam/rbacr-token), never printed; prints counts, never addresses.
Idempotent: rbacr ignores re-granting with the same validity.
"""

import argparse
import json
import subprocess
import urllib.error
import urllib.request

RBACR = "https://rbacr.nu01.com"
OLD, NEW = "tabscan", "tabcam"


def token():
    return subprocess.run(
        ["aws", "ssm", "get-parameter", "--name", "/tabcam/rbacr-token",
         "--with-decryption", "--query", "Parameter.Value", "--output", "text"],
        capture_output=True, text=True, check=True).stdout.strip()


def call(tok, method, path, body=None, ok=(200, 201, 204)):
    req = urllib.request.Request(
        RBACR + path, method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={"authorization": f"Bearer {tok}", "content-type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            data = r.read()
            return r.status, json.loads(data) if data else None
    except urllib.error.HTTPError as e:
        if e.code in ok:
            return e.code, None
        return e.code, json.loads(e.read() or b"null")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    apply = parser.parse_args().apply
    tok = token()

    status, old = call(tok, "GET", f"/api/systems/{OLD}")
    if status != 200:
        raise SystemExit(f"error: rbacr answered {status} for {OLD}")
    status, existing = call(tok, "GET", f"/api/systems/{NEW}")
    print(f"{OLD}: roles {old['roles']}; {NEW} exists: {status == 200}")

    _, grants = call(tok, "GET", f"/api/systems/{OLD}/grants")
    active = [g for g in grants["grants"] if g.get("status") in ("active", "scheduled")]
    _, vouchers = call(tok, "GET", f"/api/systems/{OLD}/vouchers")
    print(f"grants: {len(active)} active or scheduled of {len(grants['grants'])}; "
          f"vouchers left on {OLD}: {len(vouchers['vouchers'])}")
    if not apply:
        print("dry run: nothing written (--apply to mirror)")
        return

    if status != 200:
        s, _ = call(tok, "POST", "/api/systems",
                    {"id": NEW, "name": "TabCam", "roles": old["roles"]})
        assert s == 201, f"creating {NEW}: {s}"
    for role in old["roles"]:
        body = {"implies": old.get("implies", {}).get(role, []),
                "everyone": role in old.get("everyone", [])}
        s, _ = call(tok, "PUT", f"/api/systems/{NEW}/roles/{role}", body)
        assert s == 200, f"role {role}: {s}"
    patch = {"url": "https://tabcam.nu01.com/app/"}
    for k in ("description", "subscriberRole"):
        if old.get(k):
            patch[k] = old[k]
    s, _ = call(tok, "PATCH", f"/api/systems/{NEW}", patch)
    assert s == 200, f"patching {NEW}: {s}"

    done = 0
    for g in active:
        body = {"role": g["role"], "grantee": g["grantee"]}
        for k in ("startsAt", "endsAt"):
            if g.get(k):
                body[k] = g[k]
        s, _ = call(tok, "POST", f"/api/systems/{NEW}/grants", body)
        assert s in (200, 201), f"a grant of {g['role']}: {s}"
        done += 1
    print(f"applied: {NEW} mirrors {OLD}; {done} grants copied")


if __name__ == "__main__":
    main()
