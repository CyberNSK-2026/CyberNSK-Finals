import argparse
import sys

from _common import (
    add_message,
    auth_headers,
    create_ticket,
    dump,
    info,
    ok,
    register,
)

import requests


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://localhost:8080")
    ap.add_argument("--user", default="victim_a")
    ap.add_argument("--email", default="victim_a@example.com")
    ap.add_argument("--password", default="victimpass")
    args = ap.parse_args()

    try:
        token = register(args.base, args.user, args.email, args.password)
        ok(f"registered victim {args.user}")
    except requests.HTTPError:
        info("already exists, logging in")
        r = requests.post(
            f"{args.base}/api/auth/login",
            data={"username": args.user, "password": args.password},
            timeout=10,
        )
        r.raise_for_status()
        token = r.json()["access_token"]

    phone = "FLAG_VULN7_contact_phone_xyz"
    r = requests.patch(
        f"{args.base}/api/users/me",
        headers=auth_headers(token),
        json={"contact_phone": phone},
        timeout=10,
    )
    r.raise_for_status()
    ok(f"set victim contact_phone = {phone}")

    ticket = create_ticket(
        args.base,
        token,
        title=f"victim case for {args.user}",
        description="FLAG_VULN2_description_abc",
        vendor_case_id="FLAG_VULN4_vendor_case_id_def",
        device_serial="FLAG_VULN6_device_serial_ghi",
        automation_secret="FLAG_VULN5_automation_secret_jkl",
        priority="high",
    )
    ok(f"created victim ticket {ticket['id']} / {ticket['case_number']}")

    msg = add_message(args.base, token, ticket["id"], "FLAG_VULN1_message_body_mno")
    ok(f"posted message {msg['id']} with flag for vuln 1")

    artifact_flag = b"FLAG_VULN3_artifact_content_pqr\n"
    files = {"file": ("evidence.log", artifact_flag, "text/plain")}
    data = {"description": "victim-uploaded log"}
    r = requests.post(
        f"{args.base}/api/tickets/{ticket['id']}/artifacts",
        headers=auth_headers(token),
        files=files,
        data=data,
        timeout=10,
    )
    r.raise_for_status()
    artifact = r.json()
    ok(f"uploaded artifact id={artifact['id']} public_ref={artifact['public_ref']}")

    info("victim state seeded. Flags placed:")
    dump({
        "vuln1_message_body":  "FLAG_VULN1_message_body_mno",
        "vuln2_description":   "FLAG_VULN2_description_abc",
        "vuln3_artifact":      artifact_flag.decode().strip(),
        "vuln4_vendor_case_id": "FLAG_VULN4_vendor_case_id_def",
        "vuln5_automation":    "FLAG_VULN5_automation_secret_jkl",
        "vuln6_device_serial": "FLAG_VULN6_device_serial_ghi",
        "vuln7_contact_phone": phone,
        "ticket_id":           ticket["id"],
        "case_number":         ticket["case_number"],
        "victim_user":         args.user,
        "artifact_public_ref": artifact["public_ref"],
    })


if __name__ == "__main__":
    sys.exit(main())
