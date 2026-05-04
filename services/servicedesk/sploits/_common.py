import json
import random
import string
import sys

import requests


def random_handle(prefix: str = "red") -> str:
    suffix = "".join(random.choices(string.ascii_lowercase + string.digits, k=8))
    return f"{prefix}_{suffix}"


def register(base_url: str, username: str, email: str, password: str) -> str:
    r = requests.post(
        f"{base_url}/api/auth/register",
        json={"username": username, "email": email, "password": password},
        timeout=10,
    )
    r.raise_for_status()
    return r.json()["access_token"]


def login(base_url: str, username: str, password: str) -> str:
    r = requests.post(
        f"{base_url}/api/auth/login",
        data={"username": username, "password": password},
        timeout=10,
    )
    r.raise_for_status()
    return r.json()["access_token"]


def register_or_login(base_url: str, prefix: str = "red") -> tuple[str, str]:
    username = random_handle(prefix)
    password = "pass12345"
    token = register(base_url, username, f"{username}@example.com", password)
    return username, token


def auth_headers(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def create_ticket(
    base_url: str,
    token: str,
    title: str = "case",
    description: str = "",
    vendor_case_id: str = "",
    device_serial: str = "",
    automation_secret: str = "",
    priority: str = "medium",
) -> dict:
    r = requests.post(
        f"{base_url}/api/tickets",
        headers=auth_headers(token),
        json={
            "title": title,
            "description": description,
            "priority": priority,
            "vendor_case_id": vendor_case_id,
            "device_serial": device_serial,
            "automation_secret": automation_secret,
        },
        timeout=10,
    )
    r.raise_for_status()
    return r.json()


def add_message(base_url: str, token: str, ticket_id: str, body: str) -> dict:
    r = requests.post(
        f"{base_url}/api/tickets/{ticket_id}/messages",
        headers=auth_headers(token),
        json={"body": body},
        timeout=10,
    )
    r.raise_for_status()
    return r.json()


def dump(obj):
    print(json.dumps(obj, indent=2, ensure_ascii=False, default=str))


def ok(msg: str):
    print(f"[+] {msg}")


def info(msg: str):
    print(f"[*] {msg}")


def fail(msg: str):
    print(f"[-] {msg}", file=sys.stderr)
    sys.exit(1)
