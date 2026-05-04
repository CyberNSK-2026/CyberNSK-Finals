#!/usr/bin/env python3
"""
ForcAD checker for CTF Bank.

Primary interface:
    checker.py check <host>
    checker.py put <host> <flag_id> <flag> <vuln>
    checker.py get <host> <flag_id> <flag> <vuln>

Legacy environment variables are still supported for local manual runs:
    ACTION=CHECK_SLA|PUT|GET
    HOST=<host>
    FLAG=<flag>
    FLAG_ID=<flag_id>
    VULN=<1|2|3>
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import secrets
import sys
import time
import traceback
from dataclasses import dataclass
from typing import Any, Optional

import requests


OK = 101
CORRUPT = 102
MUMBLE = 103
DOWN = 104
CHECKER_ERROR = 110

PORT = int(os.environ.get("SERVICE_PORT", "5000"))
TIMEOUT = float(os.environ.get("TIMEOUT", "10"))
MAX_BODY_SNIPPET = 200


class Verdict(Exception):
    def __init__(self, code: int, public: str = "", private: str = "") -> None:
        super().__init__(public)
        self.code = code
        self.public = public
        self.private = private


@dataclass
class User:
    user_id: str
    username: str
    password: str
    token: str


@dataclass
class Merchant:
    merchant_id: str
    api_key: str


SESSION = requests.Session()
SESSION.headers.update({"User-Agent": "ctf-bank-checker/4.0"})


def finish(verdict: Verdict) -> None:
    if verdict.public:
        print(verdict.public, file=sys.stdout)
    if verdict.private:
        print(verdict.private, file=sys.stderr)
    raise SystemExit(verdict.code)


def ensure(condition: bool, public: str, private: str = "", code: int = MUMBLE) -> None:
    if not condition:
        raise Verdict(code, public, private)


def short_text(text: str) -> str:
    return text.replace("\r", " ").replace("\n", " ")[:MAX_BODY_SNIPPET]


def response_debug(resp: requests.Response) -> str:
    return f"status={resp.status_code}; body={short_text(resp.text)}"


def base_url(host: str) -> str:
    host = host.strip()
    if host.startswith(("http://", "https://")):
        return host.rstrip("/")
    return f"http://{host}:{PORT}"


def rand_username(prefix: str = "u") -> str:
    return f"{prefix}_{secrets.token_hex(6)}"


def rand_password() -> str:
    return f"p_{secrets.token_hex(16)}"


def rand_text(prefix: str, nbytes: int = 8) -> str:
    return f"{prefix}-{secrets.token_hex(nbytes)}"


def request(
    host: str,
    method: str,
    path: str,
    *,
    token: str = "",
    headers: Optional[dict[str, str]] = None,
    **kwargs: Any,
) -> requests.Response:
    req_headers = dict(headers or {})
    if token:
        req_headers["Authorization"] = f"Bearer {token}"
    if "json" in kwargs:
        req_headers.setdefault("Content-Type", "application/json")

    try:
        return SESSION.request(
            method,
            f"{base_url(host)}{path}",
            headers=req_headers,
            timeout=TIMEOUT,
            **kwargs,
        )
    except requests.Timeout as exc:
        raise Verdict(DOWN, f"{method} {path}: timeout", repr(exc))
    except requests.ConnectionError as exc:
        raise Verdict(DOWN, f"{method} {path}: connection failed", repr(exc))
    except requests.RequestException as exc:
        raise Verdict(MUMBLE, f"{method} {path}: request failed", repr(exc))


def expect_status(
    resp: requests.Response,
    expected: int,
    public: str,
    *,
    code: int = MUMBLE,
) -> requests.Response:
    if resp.status_code != expected:
        raise Verdict(code, public, response_debug(resp))
    return resp


def read_json(resp: requests.Response, context: str) -> Any:
    try:
        return resp.json()
    except ValueError as exc:
        raise Verdict(MUMBLE, f"{context}: invalid json", f"{exc}; body={short_text(resp.text)}")


def login_user(
    host: str,
    username: str,
    password: str,
    *,
    allow_unauthorized: bool = False,
    fail_code: int = MUMBLE,
    public: str = "login failed",
) -> Optional[User]:
    resp = request(
        host,
        "POST",
        "/api/auth/login",
        json={"username": username, "password": password},
    )
    if allow_unauthorized and resp.status_code == 401:
        return None
    if resp.status_code != 200:
        raise Verdict(fail_code, public, response_debug(resp))

    data = read_json(resp, public)
    user_id = data.get("user_id")
    token = data.get("token")
    returned_username = data.get("username")

    ensure(isinstance(user_id, str) and user_id, f"{public}: missing user_id", repr(data))
    ensure(isinstance(token, str) and token, f"{public}: missing token", repr(data))
    ensure(returned_username == username, f"{public}: wrong username", repr(data))

    return User(user_id=user_id, username=username, password=password, token=token)


def make_user(host: str, prefix: str = "u") -> User:
    for _ in range(8):
        username = rand_username(prefix)
        password = rand_password()
        resp = request(
            host,
            "POST",
            "/api/auth/register",
            json={"username": username, "password": password},
        )
        if resp.status_code == 409:
            continue
        expect_status(resp, 200, "register failed")
        data = read_json(resp, "register failed")
        ensure(data.get("username") == username, "register returned wrong username", repr(data))
        ensure(isinstance(data.get("user_id"), str), "register missing user_id", repr(data))

        user = login_user(host, username, password, public="login after register failed")
        ensure(user is not None, "login after register failed")
        return user

    raise Verdict(MUMBLE, "could not allocate random user")


def get_me(host: str, token: str) -> dict[str, Any]:
    resp = request(host, "GET", "/api/me", token=token)
    expect_status(resp, 200, "/api/me failed")
    data = read_json(resp, "/api/me failed")
    ensure(isinstance(data, dict), "/api/me returned non-object", repr(data))
    return data


def update_profile(host: str, token: str, display_name: str) -> None:
    resp = request(
        host,
        "PUT",
        "/api/profile",
        token=token,
        json={"display_name": display_name},
    )
    expect_status(resp, 200, "/api/profile failed")
    data = read_json(resp, "/api/profile failed")
    ensure(data.get("ok") is True, "/api/profile did not confirm update", repr(data))


def list_users(host: str, token: str) -> list[dict[str, Any]]:
    resp = request(host, "GET", "/api/users", token=token)
    expect_status(resp, 200, "/api/users failed")
    data = read_json(resp, "/api/users failed")
    ensure(isinstance(data, list), "/api/users returned non-list", repr(data))
    return data


def user_profile(host: str, token: str, username: str) -> dict[str, Any]:
    resp = request(host, "GET", f"/api/users/{username}", token=token)
    expect_status(resp, 200, "user profile lookup failed")
    data = read_json(resp, "user profile lookup failed")
    ensure(isinstance(data, dict), "user profile returned non-object", repr(data))
    return data


def create_transfer(host: str, token: str, to: str, amount: float, comment: str) -> dict[str, Any]:
    resp = request(
        host,
        "POST",
        "/api/transfer",
        token=token,
        json={"to": to, "amount": amount, "comment": comment},
    )
    expect_status(resp, 200, "transfer failed")
    data = read_json(resp, "transfer failed")
    ensure(isinstance(data, dict), "transfer returned non-object", repr(data))
    return data


def list_transactions(
    host: str,
    token: str,
    *,
    limit: int = 50,
    sort: Optional[str] = None,
    order: Optional[str] = None,
) -> list[dict[str, Any]]:
    params: dict[str, Any] = {"limit": limit}
    if sort:
        params["sort"] = sort
    if order:
        params["order"] = order

    resp = request(host, "GET", "/api/transactions", token=token, params=params)
    expect_status(resp, 200, "/api/transactions failed")
    data = read_json(resp, "/api/transactions failed")
    ensure(isinstance(data, list), "/api/transactions returned non-list", repr(data))
    return data


def transaction_stats(
    host: str,
    token: str,
    *,
    group_by: Optional[str] = None,
    period: Optional[str] = None,
) -> list[dict[str, Any]]:
    params: dict[str, Any] = {}
    if group_by:
        params["group_by"] = group_by
    if period:
        params["period"] = period

    resp = request(host, "GET", "/api/transactions/stats", token=token, params=params)
    expect_status(resp, 200, "/api/transactions/stats failed")
    data = read_json(resp, "/api/transactions/stats failed")
    ensure(isinstance(data, list), "/api/transactions/stats returned non-list", repr(data))
    return data


def create_note(
    host: str,
    token: str,
    *,
    title: str,
    body: str,
    visibility: str,
) -> str:
    resp = request(
        host,
        "POST",
        "/api/notes",
        token=token,
        json={"title": title, "body": body, "visibility": visibility},
    )
    expect_status(resp, 200, "note create failed")
    data = read_json(resp, "note create failed")
    note_id = data.get("id")
    ensure(isinstance(note_id, str) and note_id, "note create missing id", repr(data))
    return note_id


def get_note(host: str, token: str, note_id: str) -> dict[str, Any]:
    resp = request(host, "GET", "/api/note", token=token, params={"id": note_id})
    expect_status(resp, 200, "note read failed")
    data = read_json(resp, "note read failed")
    ensure(isinstance(data, dict), "note read returned non-object", repr(data))
    return data


def list_notes(host: str, token: str) -> list[dict[str, Any]]:
    resp = request(host, "GET", "/api/notes", token=token)
    expect_status(resp, 200, "/api/notes failed")
    data = read_json(resp, "/api/notes failed")
    ensure(isinstance(data, list), "/api/notes returned non-list", repr(data))
    return data


def send_message(
    host: str,
    token: str,
    *,
    to: str,
    subject: str,
    body: str,
) -> str:
    resp = request(
        host,
        "POST",
        "/api/messages",
        token=token,
        json={"to": to, "subject": subject, "body": body},
    )
    expect_status(resp, 200, "message send failed")
    data = read_json(resp, "message send failed")
    message_id = data.get("id")
    ensure(isinstance(message_id, str) and message_id, "message send missing id", repr(data))
    return message_id


def list_messages(
    host: str,
    token: str,
    *,
    folder: str,
    limit: int = 50,
) -> list[dict[str, Any]]:
    resp = request(
        host,
        "GET",
        "/api/messages",
        token=token,
        params={"folder": folder, "limit": limit},
    )
    expect_status(resp, 200, "/api/messages failed")
    data = read_json(resp, "/api/messages failed")
    ensure(isinstance(data, list), "/api/messages returned non-list", repr(data))
    return data


def get_public_key(host: str) -> str:
    resp = request(host, "GET", "/api/public-key")
    expect_status(resp, 200, "/api/public-key failed")
    ensure(
        "BEGIN PUBLIC KEY" in resp.text or "BEGIN RSA PUBLIC KEY" in resp.text,
        "/api/public-key did not return PEM",
        short_text(resp.text),
    )
    return resp.text


def make_merchant() -> Merchant:
    return Merchant(
        merchant_id=f"m-{secrets.token_hex(6)}",
        api_key=secrets.token_hex(32),
    )


def register_merchant(host: str, merchant: Merchant, callback_url: str = "") -> dict[str, Any]:
    resp = request(
        host,
        "POST",
        "/api/merchant/register",
        json={
            "merchant_id": merchant.merchant_id,
            "api_key": merchant.api_key,
            "callback_url": callback_url,
        },
    )
    expect_status(resp, 200, "merchant register failed")
    data = read_json(resp, "merchant register failed")
    ensure(isinstance(data, dict), "merchant register returned non-object", repr(data))
    return data


def build_merchant_payment(
    merchant: Merchant,
    *,
    username: str,
    amount: float,
    description: str,
    nonce: Optional[str] = None,
    timestamp: Optional[str] = None,
) -> dict[str, Any]:
    nonce = nonce or secrets.token_hex(16)
    timestamp = timestamp or str(int(time.time()))
    sign_input = f"{merchant.merchant_id}|{nonce}|{timestamp}|{amount:.2f}".encode("ascii")
    signature = hmac.new(merchant.api_key.encode("utf-8"), sign_input, hashlib.sha256).hexdigest()
    return {
        "merchant_id": merchant.merchant_id,
        "username": username,
        "amount": amount,
        "nonce": nonce,
        "timestamp": timestamp,
        "signature": signature,
        "description": description,
    }


def merchant_pay(host: str, payload: dict[str, Any]) -> dict[str, Any]:
    resp = request(host, "POST", "/api/merchant/pay", json=payload)
    expect_status(resp, 200, "merchant payment failed")
    data = read_json(resp, "merchant payment failed")
    ensure(isinstance(data, dict), "merchant payment returned non-object", repr(data))
    return data


def find_by_id(items: list[dict[str, Any]], item_id: str) -> Optional[dict[str, Any]]:
    for item in items:
        if isinstance(item, dict) and item.get("id") == item_id:
            return item
    return None


def check_service(host: str) -> None:
    resp = request(host, "GET", "/api/health")
    expect_status(resp, 200, "/api/health failed")
    health = read_json(resp, "/api/health failed")
    ensure(health.get("status") == "ok", "health status mismatch", repr(health))
    ensure(isinstance(health.get("service"), str), "health missing service name", repr(health))
    ensure(isinstance(health.get("version"), str), "health missing version", repr(health))

    alice = make_user(host, "alice")
    bob = make_user(host, "bob")

    me = get_me(host, alice.token)
    ensure(me.get("username") == alice.username, "/api/me returned wrong username", repr(me))
    ensure(isinstance(me.get("balance"), (int, float)), "/api/me missing balance", repr(me))

    new_display = rand_text("Alice", 4)
    update_profile(host, alice.token, new_display)
    me_after = get_me(host, alice.token)
    ensure(
        me_after.get("display_name") == new_display,
        "/api/profile update not visible",
        repr(me_after),
    )

    public_body = rand_text("public-note", 10)
    public_note_id = create_note(
        host,
        bob.token,
        title=rand_text("feed", 4),
        body=public_body,
        visibility="public",
    )

    users = list_users(host, alice.token)
    usernames = {user.get("username") for user in users if isinstance(user, dict)}
    ensure(alice.username in usernames, "/api/users missing alice")
    ensure(bob.username in usernames, "/api/users missing bob")

    profile = user_profile(host, alice.token, bob.username)
    profile_user = profile.get("user")
    profile_stats = profile.get("stats")
    recent_notes = profile.get("recent_notes")

    ensure(isinstance(profile_user, dict), "user profile missing user block", repr(profile))
    ensure(profile_user.get("username") == bob.username, "user profile returned wrong user", repr(profile))
    ensure(isinstance(profile_stats, dict), "user profile missing stats", repr(profile))
    ensure(
        isinstance(profile_stats.get("transaction_count"), int),
        "user profile stats malformed",
        repr(profile),
    )
    ensure(isinstance(recent_notes, list), "user profile missing recent_notes", repr(profile))
    ensure(
        any(
            isinstance(note, dict)
            and note.get("id") == public_note_id
            and note.get("body") == public_body
            for note in recent_notes
        ),
        "public note missing from recent_notes",
        repr(profile),
    )

    transfer_comment = rand_text("sla-transfer", 8)
    transfer = create_transfer(host, alice.token, bob.username, 1.0, transfer_comment)
    tx_id = transfer.get("id")
    ensure(isinstance(tx_id, str) and tx_id, "transfer response missing id", repr(transfer))

    alice_txs = list_transactions(host, alice.token, limit=25)
    bob_txs = list_transactions(host, bob.token, limit=25)
    alice_tx = find_by_id(alice_txs, tx_id)
    bob_tx = find_by_id(bob_txs, tx_id)
    ensure(alice_tx is not None, "transfer missing from sender history")
    ensure(bob_tx is not None, "transfer missing from recipient history")
    ensure(alice_tx.get("comment") == transfer_comment, "transfer comment mismatch", repr(alice_tx))
    ensure(alice_tx.get("to_username") == bob.username, "transfer recipient mismatch", repr(alice_tx))

    stats = transaction_stats(host, alice.token, group_by="counterparty", period="week")
    ensure(
        any(isinstance(row, dict) and row.get("bucket") == bob.username for row in stats),
        "stats missing counterparty bucket",
        repr(stats),
    )

    private_body = rand_text("private-note", 12)
    note_id = create_note(
        host,
        alice.token,
        title=rand_text("memo", 4),
        body=private_body,
        visibility="private",
    )
    note = get_note(host, alice.token, note_id)
    ensure(note.get("body") == private_body, "private note body mismatch", repr(note))
    ensure(note.get("visibility") == "private", "private note visibility mismatch", repr(note))

    notes = list_notes(host, alice.token)
    ensure(
        any(isinstance(item, dict) and item.get("id") == note_id for item in notes),
        "private note missing from /api/notes",
    )

    message_body = rand_text("sla-message", 12)
    message_id = send_message(
        host,
        alice.token,
        to=bob.username,
        subject=rand_text("subject", 4),
        body=message_body,
    )
    inbox = list_messages(host, bob.token, folder="inbox", limit=50)
    sent = list_messages(host, alice.token, folder="sent", limit=50)
    inbox_msg = find_by_id(inbox, message_id)
    sent_msg = find_by_id(sent, message_id)
    ensure(inbox_msg is not None, "message missing from inbox")
    ensure(sent_msg is not None, "message missing from sent folder")
    ensure(inbox_msg.get("body") == message_body, "message body mismatch", repr(inbox_msg))
    ensure(inbox_msg.get("sender_username") == alice.username, "message sender mismatch", repr(inbox_msg))

    get_public_key(host)

    merchant = make_merchant()
    registration = register_merchant(host, merchant, "")
    ensure(
        registration.get("merchant_id") == merchant.merchant_id,
        "merchant register returned wrong merchant_id",
        repr(registration),
    )

    merchant_description = rand_text("sla-merchant", 10)
    payment_payload = build_merchant_payment(
        merchant,
        username=alice.username,
        amount=2.0,
        description=merchant_description,
    )
    payment = merchant_pay(host, payment_payload)
    transaction_id = payment.get("transaction_id")
    ensure(isinstance(transaction_id, str) and transaction_id, "merchant payment missing transaction_id", repr(payment))
    ensure(isinstance(payment.get("settlement_id"), str), "merchant payment missing settlement_id", repr(payment))
    ensure(payment.get("user_id") == alice.user_id, "merchant payment returned wrong user_id", repr(payment))
    ensure(payment.get("user_created") is False, "merchant payment should use existing user", repr(payment))

    alice_txs_after_pay = list_transactions(host, alice.token, limit=50)
    merchant_tx = find_by_id(alice_txs_after_pay, transaction_id)
    ensure(merchant_tx is not None, "merchant payment missing from history")
    ensure(merchant_tx.get("comment") == merchant_description, "merchant comment mismatch", repr(merchant_tx))

    replay = request(host, "POST", "/api/merchant/pay", json=payment_payload)
    if replay.status_code != 409:
        raise Verdict(MUMBLE, "merchant replay protection failed", response_debug(replay))


def put_flag_transaction_comment(host: str, flag: str) -> str:
    alice = make_user(host, "txa")
    bob = make_user(host, "txb")

    transfer = create_transfer(host, alice.token, bob.username, 1.0, flag)
    tx_id = transfer.get("id")
    ensure(isinstance(tx_id, str) and tx_id, "flag transfer missing id", repr(transfer))

    return json.dumps(
        {
            "alice_user": alice.username,
            "alice_pass": alice.password,
            "bob_user": bob.username,
            "bob_pass": bob.password,
            "tx_id": tx_id,
        },
        separators=(",", ":"),
        sort_keys=True,
    )


def get_flag_transaction_comment(host: str, flag_id: str, flag: str) -> None:
    try:
        data = json.loads(flag_id)
        alice_user = data["alice_user"]
        alice_pass = data["alice_pass"]
        bob_user = data["bob_user"]
        bob_pass = data["bob_pass"]
        tx_id = data["tx_id"]
    except (KeyError, TypeError, json.JSONDecodeError) as exc:
        raise Verdict(CORRUPT, "bad flag_id for store 1", repr(exc))

    for username, password in ((alice_user, alice_pass), (bob_user, bob_pass)):
        user = login_user(
            host,
            username,
            password,
            allow_unauthorized=True,
            fail_code=CORRUPT,
            public="store 1 login failed",
        )
        if user is None:
            continue

        txs = list_transactions(host, user.token, limit=200)
        tx = find_by_id(txs, tx_id)
        if tx is None:
            continue
        if tx.get("comment") == flag:
            return
        raise Verdict(
            CORRUPT,
            "flag mismatch in transaction comment",
            f"expected={flag!r} got={tx.get('comment')!r}",
        )

    raise Verdict(CORRUPT, "transaction with flag not found", f"tx_id={tx_id}")


def put_flag_private_note(host: str, flag: str) -> str:
    owner = make_user(host, "note")
    note_id = create_note(
        host,
        owner.token,
        title=rand_text("memo", 4),
        body=flag,
        visibility="private",
    )
    return json.dumps(
        {
            "username": owner.username,
            "password": owner.password,
            "note_id": note_id,
        },
        separators=(",", ":"),
        sort_keys=True,
    )


def get_flag_private_note(host: str, flag_id: str, flag: str) -> None:
    try:
        data = json.loads(flag_id)
        username = data["username"]
        password = data["password"]
        note_id = data["note_id"]
    except (KeyError, TypeError, json.JSONDecodeError) as exc:
        raise Verdict(CORRUPT, "bad flag_id for store 2", repr(exc))

    user = login_user(
        host,
        username,
        password,
        allow_unauthorized=True,
        fail_code=CORRUPT,
        public="store 2 login failed",
    )
    if user is None:
        raise Verdict(CORRUPT, "store 2 owner is gone")

    resp = request(host, "GET", "/api/note", token=user.token, params={"id": note_id})
    if resp.status_code in (403, 404):
        raise Verdict(CORRUPT, "private note is missing", response_debug(resp))
    expect_status(resp, 200, "private note read failed")

    note = read_json(resp, "private note read failed")
    if note.get("body") != flag:
        raise Verdict(
            CORRUPT,
            "flag mismatch in note body",
            f"expected={flag!r} got={note.get('body')!r}",
        )


def put_flag_message(host: str, flag: str) -> str:
    sender = make_user(host, "msgs")
    recipient = make_user(host, "msgr")
    message_id = send_message(
        host,
        sender.token,
        to=recipient.username,
        subject=rand_text("note", 4),
        body=flag,
    )
    return json.dumps(
        {
            "username": recipient.username,
            "password": recipient.password,
            "message_id": message_id,
        },
        separators=(",", ":"),
        sort_keys=True,
    )


def get_flag_message(host: str, flag_id: str, flag: str) -> None:
    try:
        data = json.loads(flag_id)
        username = data["username"]
        password = data["password"]
        message_id = data["message_id"]
    except (KeyError, TypeError, json.JSONDecodeError) as exc:
        raise Verdict(CORRUPT, "bad flag_id for store 3", repr(exc))

    user = login_user(
        host,
        username,
        password,
        allow_unauthorized=True,
        fail_code=CORRUPT,
        public="store 3 login failed",
    )
    if user is None:
        raise Verdict(CORRUPT, "store 3 recipient is gone")

    messages = list_messages(host, user.token, folder="inbox", limit=200)
    message = find_by_id(messages, message_id)
    if message is None:
        raise Verdict(CORRUPT, "message with flag not found", f"message_id={message_id}")
    if message.get("body") != flag:
        raise Verdict(
            CORRUPT,
            "flag mismatch in message body",
            f"expected={flag!r} got={message.get('body')!r}",
        )


PUT_HANDLERS = {
    1: put_flag_transaction_comment,
    2: put_flag_private_note,
    3: put_flag_message,
}

GET_HANDLERS = {
    1: get_flag_transaction_comment,
    2: get_flag_private_note,
    3: get_flag_message,
}


def parse_vuln(raw: str) -> int:
    try:
        vuln = int(raw)
    except ValueError as exc:
        raise Verdict(CHECKER_ERROR, "vuln must be an integer", repr(exc))
    if vuln not in PUT_HANDLERS:
        raise Verdict(CHECKER_ERROR, f"unsupported vuln: {vuln}")
    return vuln


def parse_invocation(argv: list[str]) -> tuple[str, str, str, str, int]:
    if len(argv) > 1:
        action = argv[1].lower()
        if action == "check":
            if len(argv) != 3:
                raise Verdict(CHECKER_ERROR, "usage: checker.py check <host>")
            return action, argv[2], "", "", 0
        if action in {"put", "get"}:
            if len(argv) != 6:
                raise Verdict(CHECKER_ERROR, f"usage: checker.py {action} <host> <flag_id> <flag> <vuln>")
            host = argv[2]
            flag_id = argv[3]
            flag = argv[4]
            vuln = parse_vuln(argv[5])
            return action, host, flag_id, flag, vuln
        raise Verdict(CHECKER_ERROR, f"unknown action: {argv[1]}")

    action = os.environ.get("ACTION", "CHECK_SLA").strip().upper()
    host = os.environ.get("HOST", "localhost")

    if action in {"CHECK", "CHECK_SLA"}:
        return "check", host, "", "", 0
    if action == "PUT":
        flag = os.environ.get("FLAG", "")
        ensure(bool(flag), "PUT requires FLAG", code=CHECKER_ERROR)
        return "put", host, os.environ.get("FLAG_ID", ""), flag, parse_vuln(os.environ.get("VULN", "1"))
    if action == "GET":
        flag = os.environ.get("FLAG", "")
        flag_id = os.environ.get("FLAG_ID", "")
        ensure(bool(flag), "GET requires FLAG", code=CHECKER_ERROR)
        ensure(bool(flag_id), "GET requires FLAG_ID", code=CHECKER_ERROR)
        return "get", host, flag_id, flag, parse_vuln(os.environ.get("VULN", "1"))

    raise Verdict(CHECKER_ERROR, f"unknown ACTION={action}")


def main() -> None:
    action, host, flag_id, flag, vuln = parse_invocation(sys.argv)

    if action == "check":
        check_service(host)
        raise Verdict(OK)
    if action == "put":
        planted_flag_id = PUT_HANDLERS[vuln](host, flag)
        raise Verdict(OK, planted_flag_id)
    if action == "get":
        GET_HANDLERS[vuln](host, flag_id, flag)
        raise Verdict(OK)

    raise Verdict(CHECKER_ERROR, f"unreachable action: {action}")


if __name__ == "__main__":
    try:
        main()
    except Verdict as verdict:
        finish(verdict)
    except SystemExit:
        raise
    except Exception:
        finish(Verdict(CHECKER_ERROR, "checker exception", traceback.format_exc()))
