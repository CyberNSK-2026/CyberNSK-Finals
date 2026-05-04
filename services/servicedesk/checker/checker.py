#!/usr/bin/env python3
"""
ForcAD checker for ServiceDesk.

Interface:
  checker.py check <host>
  checker.py put   <host> <round_id> <flag> <vuln>
  checker.py get   <host> <flag_id>  <flag> <vuln>

Legacy env-based local runs are also supported:
  ACTION=CHECK_SLA|PUT|GET
  HOST=<host>
  FLAG=<flag>
  FLAG_ID=<flag_id>
  VULN=<1..7>
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import mimetypes
import os
import secrets
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any


OK = 101
CORRUPT = 102
MUMBLE = 103
DOWN = 104
CHECKER_ERROR = 110

PORT = int(os.getenv("SERVICE_PORT", "7070"))
TIMEOUT = float(os.getenv("CHECKER_TIMEOUT", os.getenv("TIMEOUT", "8.0")))
CHECKER_SECRET = os.getenv("CHECKER_SECRET", "servicedesk-checker-secret")
MAX_SNIPPET = 240

VULNS = {
    "1": "message_body",
    "2": "ticket_description",
    "3": "artifact_content",
    "4": "share_vendor_case_id",
    "5": "automation_secret",
    "6": "export_device_serial",
    "7": "contact_phone",
}

TICKET_PREFIXES = (
    "case",
    "incident",
    "request",
    "report",
    "task",
    "issue",
)

TICKET_NOTES = (
    "Customer asked for status update.",
    "Need additional review from support queue.",
    "Please check the latest activity on this case.",
    "Follow-up required before closing the request.",
    "Investigate the recent issue reported by the user.",
)

MESSAGE_NOTES = (
    "Customer confirmed the issue is reproducible.",
    "Additional context was attached to the case.",
    "Awaiting response from the customer.",
    "Support requested another verification step.",
    "Recent activity was added to the ticket.",
)

ATTACHMENT_PREFIXES = (
    "document",
    "note",
    "capture",
    "log",
    "record",
)

ATTACHMENT_NOTES = (
    "customer upload",
    "supporting document",
    "requested attachment",
    "extra materials",
)

PRIORITIES = ("low", "medium", "high")


class Verdict(Exception):
    def __init__(self, code: int, public: str, private: str = "") -> None:
        super().__init__(public)
        self.code = code
        self.public = public
        self.private = private


@dataclass
class HttpResponse:
    status_code: int
    body: bytes
    headers: dict[str, str]

    @property
    def text(self) -> str:
        return self.body.decode("utf-8", errors="replace")


@dataclass
class UserSession:
    user_id: str
    username: str
    email: str
    password: str
    token: str


@dataclass
class TicketInfo:
    ticket_id: str
    case_number: str


def quit_with(code: int, public: str, private: str = "") -> None:
    if private:
        print(private, file=sys.stderr)
    if public:
        print(public)
    raise SystemExit(code)


def ensure(condition: bool, public: str, private: str = "", code: int = MUMBLE) -> None:
    if not condition:
        raise Verdict(code, public, private)


def short(text: str) -> str:
    return text.replace("\r", " ").replace("\n", " ")[:MAX_SNIPPET]


def response_debug(resp: HttpResponse) -> str:
    return f"status={resp.status_code}; body={short(resp.text)}"


def normalize_base(host: str) -> str:
    host = host.strip()
    if host.startswith(("http://", "https://")):
        return host.rstrip("/")
    return f"http://{host}:{PORT}"


def rand_slug(prefix: str, nbytes: int = 6) -> str:
    return f"{prefix}_{secrets.token_hex(nbytes)}"


def rand_ticket_title() -> str:
    return rand_slug(secrets.choice(TICKET_PREFIXES))


def rand_ticket_note() -> str:
    return secrets.choice(TICKET_NOTES)


def rand_attachment_name() -> str:
    return f"{rand_slug(secrets.choice(ATTACHMENT_PREFIXES))}.txt"


def rand_attachment_note() -> str:
    return secrets.choice(ATTACHMENT_NOTES)


def rand_message_note() -> str:
    return secrets.choice(MESSAGE_NOTES)


def rand_priority() -> str:
    return secrets.choice(PRIORITIES)


def rand_phone() -> str:
    return f"+79{secrets.randbelow(10**9):09d}"


def b64u(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def b64u_decode(data: str) -> bytes:
    return base64.urlsafe_b64decode(data + "=" * ((4 - len(data) % 4) % 4))


def sign_payload(raw: bytes) -> str:
    return hmac.new(CHECKER_SECRET.encode("utf-8"), raw, hashlib.sha256).hexdigest()


def encode_flag_id(data: dict[str, Any]) -> str:
    raw = json.dumps(data, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return f"{b64u(raw)}.{sign_payload(raw)}"


def decode_flag_id(token: str) -> dict[str, Any]:
    try:
        payload, sig = token.split(".", 1)
        raw = b64u_decode(payload)
    except Exception as exc:
        raise Verdict(CHECKER_ERROR, "CHECKER_ERROR", f"bad flag_id format: {exc}") from exc

    if not hmac.compare_digest(sig, sign_payload(raw)):
        raise Verdict(CHECKER_ERROR, "CHECKER_ERROR", "bad flag_id signature")

    try:
        data = json.loads(raw.decode("utf-8"))
    except Exception as exc:
        raise Verdict(CHECKER_ERROR, "CHECKER_ERROR", f"bad flag_id json: {exc}") from exc

    if not isinstance(data, dict):
        raise Verdict(CHECKER_ERROR, "CHECKER_ERROR", "flag_id must decode to object")
    return data


def encode_multipart(
    fields: dict[str, str],
    files: list[tuple[str, str, bytes, str]],
) -> tuple[bytes, str]:
    boundary = f"----WebKitFormBoundary{secrets.token_hex(16)}"
    chunks: list[bytes] = []

    for name, value in fields.items():
        chunks.extend(
            [
                f"--{boundary}\r\n".encode("utf-8"),
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode("utf-8"),
                value.encode("utf-8"),
                b"\r\n",
            ]
        )

    for field_name, filename, content, content_type in files:
        chunks.extend(
            [
                f"--{boundary}\r\n".encode("utf-8"),
                (
                    f'Content-Disposition: form-data; name="{field_name}"; '
                    f'filename="{filename}"\r\n'
                ).encode("utf-8"),
                f"Content-Type: {content_type}\r\n\r\n".encode("utf-8"),
                content,
                b"\r\n",
            ]
        )

    chunks.append(f"--{boundary}--\r\n".encode("utf-8"))
    return b"".join(chunks), boundary


class ServiceDeskClient:
    def __init__(self, host: str) -> None:
        self.base = normalize_base(host)
        self.user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"

    def request(
        self,
        method: str,
        path: str,
        *,
        token: str = "",
        headers: dict[str, str] | None = None,
        body: bytes | None = None,
        content_type: str | None = None,
    ) -> HttpResponse:
        url = path if path.startswith(("http://", "https://")) else f"{self.base}{path}"
        req_headers = {"User-Agent": self.user_agent}
        if token:
            req_headers["Authorization"] = f"Bearer {token}"
        if content_type:
            req_headers["Content-Type"] = content_type
        if headers:
            req_headers.update(headers)

        req = urllib.request.Request(url=url, data=body, headers=req_headers, method=method.upper())
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                return HttpResponse(
                    status_code=resp.getcode(),
                    body=resp.read(),
                    headers=dict(resp.headers.items()),
                )
        except urllib.error.HTTPError as exc:
            return HttpResponse(
                status_code=exc.code,
                body=exc.read(),
                headers=dict(exc.headers.items()),
            )
        except (urllib.error.URLError, socket.timeout, TimeoutError, OSError) as exc:
            raise Verdict(DOWN, f"{method} {path}: connection failed", repr(exc)) from exc

    def request_json(
        self,
        method: str,
        path: str,
        *,
        token: str = "",
        payload: Any | None = None,
    ) -> HttpResponse:
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        return self.request(
            method,
            path,
            token=token,
            body=body,
            content_type="application/json" if payload is not None else None,
        )

    def request_form(
        self,
        method: str,
        path: str,
        *,
        token: str = "",
        form: dict[str, str],
    ) -> HttpResponse:
        body = urllib.parse.urlencode(form).encode("utf-8")
        return self.request(
            method,
            path,
            token=token,
            body=body,
            content_type="application/x-www-form-urlencoded",
        )

    def request_multipart(
        self,
        method: str,
        path: str,
        *,
        token: str = "",
        fields: dict[str, str],
        files: list[tuple[str, str, bytes, str]],
    ) -> HttpResponse:
        body, boundary = encode_multipart(fields, files)
        return self.request(
            method,
            path,
            token=token,
            body=body,
            content_type=f"multipart/form-data; boundary={boundary}",
        )

    def parse_json(self, resp: HttpResponse, context: str) -> Any:
        try:
            return json.loads(resp.body.decode("utf-8"))
        except Exception as exc:
            raise Verdict(MUMBLE, f"{context}: invalid json", f"{exc}; {response_debug(resp)}") from exc

    def expect_status(
        self,
        resp: HttpResponse,
        expected: int,
        public: str,
        *,
        code: int = MUMBLE,
    ) -> HttpResponse:
        if resp.status_code != expected:
            raise Verdict(code, public, response_debug(resp))
        return resp

    def register_random(self, prefix: str = "user") -> UserSession:
        for _ in range(8):
            username = rand_slug(prefix)
            email = f"{username}@example.com"
            password = rand_slug("pw", 10)
            resp = self.request_json(
                "POST",
                "/api/auth/register",
                payload={
                    "username": username,
                    "email": email,
                    "password": password,
                },
            )
            if resp.status_code == 400 and "already taken" in resp.text.lower():
                continue
            self.expect_status(resp, 200, "register failed")
            data = self.parse_json(resp, "register failed")
            ensure(data.get("user_id"), "register failed: missing user_id", repr(data))
            ensure(data.get("access_token"), "register failed: missing access_token", repr(data))
            return UserSession(
                user_id=str(data["user_id"]),
                username=username,
                email=email,
                password=password,
                token=str(data["access_token"]),
            )

        raise Verdict(MUMBLE, "register failed", "could not allocate random username")

    def login(self, username: str, password: str, *, public: str = "login failed", code: int = MUMBLE) -> UserSession:
        resp = self.request_form(
            "POST",
            "/api/auth/login",
            form={"username": username, "password": password},
        )
        if resp.status_code == 403:
            raise Verdict(code, public, response_debug(resp))
        self.expect_status(resp, 200, public, code=code)
        data = self.parse_json(resp, public)
        ensure(data.get("access_token"), f"{public}: missing access_token", repr(data), code=code)
        ensure(data.get("user_id"), f"{public}: missing user_id", repr(data), code=code)
        return UserSession(
            user_id=str(data["user_id"]),
            username=username,
            email="",
            password=password,
            token=str(data["access_token"]),
        )

    def get_me(self, token: str, *, code: int = MUMBLE) -> dict[str, Any]:
        resp = self.request("GET", "/api/users/me", token=token)
        self.expect_status(resp, 200, "/api/users/me failed", code=code)
        data = self.parse_json(resp, "/api/users/me failed")
        ensure(isinstance(data, dict), "/api/users/me returned non-object", repr(data), code=code)
        return data

    def patch_me(self, token: str, payload: dict[str, Any], *, code: int = MUMBLE) -> dict[str, Any]:
        resp = self.request_json("PATCH", "/api/users/me", token=token, payload=payload)
        self.expect_status(resp, 200, "PATCH /api/users/me failed", code=code)
        data = self.parse_json(resp, "PATCH /api/users/me failed")
        ensure(isinstance(data, dict), "PATCH /api/users/me returned non-object", repr(data), code=code)
        return data

    def list_users(self, token: str, *, code: int = MUMBLE) -> list[dict[str, Any]]:
        resp = self.request("GET", "/api/users", token=token)
        self.expect_status(resp, 200, "/api/users failed", code=code)
        data = self.parse_json(resp, "/api/users failed")
        ensure(isinstance(data, list), "/api/users returned non-list", repr(data), code=code)
        return data

    def create_ticket(
        self,
        token: str,
        *,
        title: str,
        description: str = "",
        priority: str = "medium",
        report_template: str | None = None,
        vendor_case_id: str = "",
        device_serial: str = "",
        automation_secret: str = "",
    ) -> TicketInfo:
        payload = {
            "title": title,
            "description": description,
            "priority": priority,
            "vendor_case_id": vendor_case_id,
            "device_serial": device_serial,
            "automation_secret": automation_secret,
        }
        if report_template is not None:
            payload["report_template"] = report_template

        resp = self.request_json("POST", "/api/tickets", token=token, payload=payload)
        self.expect_status(resp, 200, "create ticket failed")
        data = self.parse_json(resp, "create ticket failed")
        ensure(data.get("id"), "create ticket failed: missing id", repr(data))
        ensure(data.get("case_number"), "create ticket failed: missing case_number", repr(data))
        return TicketInfo(ticket_id=str(data["id"]), case_number=str(data["case_number"]))

    def list_tickets(self, token: str, *, code: int = MUMBLE) -> list[dict[str, Any]]:
        resp = self.request("GET", "/api/tickets", token=token)
        self.expect_status(resp, 200, "/api/tickets failed", code=code)
        data = self.parse_json(resp, "/api/tickets failed")
        ensure(isinstance(data, list), "/api/tickets returned non-list", repr(data), code=code)
        return data

    def get_ticket(self, token: str, ticket_id: str, *, code: int = MUMBLE) -> dict[str, Any]:
        resp = self.request("GET", f"/api/tickets/{ticket_id}", token=token)
        if resp.status_code == 404:
            raise Verdict(CORRUPT, "ticket missing", response_debug(resp))
        self.expect_status(resp, 200, "GET /api/tickets/{id} failed", code=code)
        data = self.parse_json(resp, "GET /api/tickets/{id} failed")
        ensure(isinstance(data, dict), "ticket payload is not object", repr(data), code=code)
        return data

    def add_message(self, token: str, ticket_id: str, body_text: str) -> dict[str, Any]:
        resp = self.request_json(
            "POST",
            f"/api/tickets/{ticket_id}/messages",
            token=token,
            payload={"body": body_text},
        )
        self.expect_status(resp, 200, "create message failed")
        data = self.parse_json(resp, "create message failed")
        ensure(data.get("id"), "create message failed: missing id", repr(data))
        return data

    def list_messages(self, token: str, ticket_id: str, *, code: int = MUMBLE) -> list[dict[str, Any]]:
        resp = self.request("GET", f"/api/tickets/{ticket_id}/messages", token=token)
        if resp.status_code == 404:
            raise Verdict(CORRUPT, "ticket messages missing", response_debug(resp))
        self.expect_status(resp, 200, "list messages failed", code=code)
        data = self.parse_json(resp, "list messages failed")
        ensure(isinstance(data, list), "messages payload is not list", repr(data), code=code)
        return data

    def upload_artifact(
        self,
        token: str,
        ticket_id: str,
        *,
        filename: str,
        content: bytes,
        description: str,
        content_type: str = "application/octet-stream",
    ) -> dict[str, Any]:
        resp = self.request_multipart(
            "POST",
            f"/api/tickets/{ticket_id}/artifacts",
            token=token,
            fields={"description": description},
            files=[("file", filename, content, content_type)],
        )
        self.expect_status(resp, 200, "upload artifact failed")
        data = self.parse_json(resp, "upload artifact failed")
        ensure(data.get("id"), "upload artifact failed: missing id", repr(data))
        return data

    def list_artifacts(self, token: str, ticket_id: str, *, code: int = MUMBLE) -> list[dict[str, Any]]:
        resp = self.request("GET", f"/api/tickets/{ticket_id}/artifacts", token=token)
        if resp.status_code == 404:
            raise Verdict(CORRUPT, "artifacts missing", response_debug(resp))
        self.expect_status(resp, 200, "list artifacts failed", code=code)
        data = self.parse_json(resp, "list artifacts failed")
        ensure(isinstance(data, list), "artifacts payload is not list", repr(data), code=code)
        return data

    def download_artifact(self, token: str, ticket_id: str, artifact_ref: str, *, code: int = MUMBLE) -> bytes:
        resp = self.request("GET", f"/api/tickets/{ticket_id}/artifacts/{artifact_ref}/download", token=token)
        if resp.status_code == 404:
            raise Verdict(CORRUPT, "artifact download missing", response_debug(resp))
        self.expect_status(resp, 200, "artifact download failed", code=code)
        return resp.body

    def safe_download_artifact(self, token: str, artifact_id: str, *, code: int = MUMBLE) -> bytes:
        resp = self.request("GET", f"/api/files/artifact/{artifact_id}", token=token)
        if resp.status_code == 404:
            raise Verdict(CORRUPT, "safe artifact download missing", response_debug(resp))
        self.expect_status(resp, 200, "safe artifact download failed", code=code)
        return resp.body

    def create_report(self, token: str, ticket_id: str, template: str | None = None, *, code: int = MUMBLE) -> dict[str, Any]:
        payload: dict[str, Any] = {"ticket_id": ticket_id}
        if template is not None:
            payload["custom_template"] = template
        resp = self.request_json("POST", "/api/reports", token=token, payload=payload)
        if resp.status_code == 404:
            raise Verdict(CORRUPT, "report target ticket missing", response_debug(resp))
        self.expect_status(resp, 200, "create report failed", code=code)
        data = self.parse_json(resp, "create report failed")
        ensure(isinstance(data, dict), "report payload is not object", repr(data), code=code)
        return data

    def create_export(self, token: str, ticket_id: str, *, code: int = MUMBLE) -> dict[str, Any]:
        resp = self.request_json("POST", "/api/files/exports", token=token, payload={"ticket_id": ticket_id})
        if resp.status_code == 404:
            raise Verdict(CORRUPT, "export target ticket missing", response_debug(resp))
        self.expect_status(resp, 200, "create export failed", code=code)
        data = self.parse_json(resp, "create export failed")
        ensure(isinstance(data, dict), "export payload is not object", repr(data), code=code)
        return data

    def download_by_path(self, token: str, path: str, *, code: int = MUMBLE) -> HttpResponse:
        resp = self.request("GET", path, token=token)
        if resp.status_code == 404:
            raise Verdict(CORRUPT, "download path missing", response_debug(resp))
        self.expect_status(resp, 200, "download path failed", code=code)
        return resp

    def create_share(self, token: str, ticket_id: str, *, code: int = MUMBLE) -> dict[str, Any]:
        resp = self.request_json("POST", "/api/share", token=token, payload={"ticket_id": ticket_id})
        if resp.status_code == 404:
            raise Verdict(CORRUPT, "share target ticket missing", response_debug(resp))
        self.expect_status(resp, 200, "create share failed", code=code)
        data = self.parse_json(resp, "create share failed")
        ensure(isinstance(data, dict), "share payload is not object", repr(data), code=code)
        return data

    def view_share(self, share_path: str, *, code: int = MUMBLE) -> dict[str, Any]:
        resp = self.request("GET", share_path)
        if resp.status_code == 404:
            raise Verdict(CORRUPT, "share missing", response_debug(resp))
        self.expect_status(resp, 200, "view share failed", code=code)
        data = self.parse_json(resp, "view share failed")
        ensure(isinstance(data, dict), "share view is not object", repr(data), code=code)
        return data

    def list_notifications(self, token: str, *, include_own: bool = False, code: int = MUMBLE) -> dict[str, Any]:
        query = urllib.parse.urlencode({"limit": "20", "include_own": "true" if include_own else "false"})
        resp = self.request("GET", f"/api/notifications?{query}", token=token)
        self.expect_status(resp, 200, "/api/notifications failed", code=code)
        data = self.parse_json(resp, "/api/notifications failed")
        ensure(isinstance(data, dict), "notifications payload is not object", repr(data), code=code)
        return data

    def create_integration(self, token: str, payload: dict[str, Any], *, code: int = MUMBLE) -> dict[str, Any]:
        resp = self.request_json("POST", "/api/integrations", token=token, payload=payload)
        self.expect_status(resp, 200, "create integration failed", code=code)
        data = self.parse_json(resp, "create integration failed")
        ensure(isinstance(data, dict), "integration payload is not object", repr(data), code=code)
        return data

    def list_integrations(self, token: str, *, code: int = MUMBLE) -> list[dict[str, Any]]:
        resp = self.request("GET", "/api/integrations", token=token)
        self.expect_status(resp, 200, "list integrations failed", code=code)
        data = self.parse_json(resp, "list integrations failed")
        ensure(isinstance(data, list), "integrations payload is not list", repr(data), code=code)
        return data

    def patch_integration(self, token: str, integration_id: str, payload: dict[str, Any], *, code: int = MUMBLE) -> dict[str, Any]:
        resp = self.request_json("PATCH", f"/api/integrations/{integration_id}", token=token, payload=payload)
        if resp.status_code == 404:
            raise Verdict(CORRUPT, "integration missing", response_debug(resp))
        self.expect_status(resp, 200, "patch integration failed", code=code)
        data = self.parse_json(resp, "patch integration failed")
        ensure(isinstance(data, dict), "patch integration payload is not object", repr(data), code=code)
        return data

    def trigger_integration(self, token: str, integration_id: str, *, code: int = MUMBLE) -> dict[str, Any]:
        resp = self.request("POST", f"/api/integrations/{integration_id}/trigger", token=token)
        if resp.status_code == 404:
            raise Verdict(CORRUPT, "integration missing on trigger", response_debug(resp))
        self.expect_status(resp, 200, "trigger integration failed", code=code)
        data = self.parse_json(resp, "trigger integration failed")
        ensure(isinstance(data, dict), "trigger integration payload is not object", repr(data), code=code)
        return data


def make_user_and_client(host: str) -> tuple[ServiceDeskClient, UserSession]:
    client = ServiceDeskClient(host)
    return client, client.register_random("sd")


def seed_ticket_activity(client: ServiceDeskClient, token: str, ticket_id: str) -> None:
    client.add_message(token, ticket_id, rand_message_note())
    artifact_name = rand_attachment_name()
    artifact_content = f"attachment-{secrets.token_hex(8)}".encode("utf-8")
    client.upload_artifact(
        token,
        ticket_id,
        filename=artifact_name,
        content=artifact_content,
        description=rand_attachment_note(),
        content_type=mimetypes.guess_type(artifact_name)[0] or "text/plain",
    )


def create_populated_ticket(
    client: ServiceDeskClient,
    token: str,
    *,
    flag_field: str | None = None,
    flag: str = "",
) -> TicketInfo:
    payload = {
        "title": rand_ticket_title(),
        "description": rand_ticket_note(),
        "priority": rand_priority(),
        "report_template": "Case {{ ticket.case_number }} {{ user.username }}",
        "vendor_case_id": rand_slug("vendor", 10),
        "device_serial": rand_slug("unit", 10),
        "automation_secret": rand_slug("token", 10),
    }
    if flag_field:
        payload[flag_field] = flag
    ticket = client.create_ticket(token, **payload)
    seed_ticket_activity(client, token, ticket.ticket_id)
    return ticket


def check(host: str) -> None:
    client, user = make_user_and_client(host)

    health = client.request("GET", "/health")
    client.expect_status(health, 200, "/health failed", code=MUMBLE)
    health_data = client.parse_json(health, "/health failed")
    ensure(health_data.get("ok") is True, "/health did not report ok", repr(health_data))

    me = client.get_me(user.token)
    ensure(me.get("username") == user.username, "/api/users/me username mismatch", repr(me))

    phone = rand_phone()
    updated = client.patch_me(
        user.token,
        {
            "contact_phone": phone,
            "workspace": "portal",
            "queue_scope": "personal",
        },
    )
    ensure(updated.get("contact_phone") == phone, "profile update did not persist phone", repr(updated))

    directory = client.list_users(user.token)
    ensure(any(item.get("username") == user.username and item.get("contact_phone") == phone for item in directory),
           "directory does not show updated user phone")

    title = rand_ticket_title()
    description = rand_ticket_note()
    vendor_case_id = rand_slug("vendor", 10)
    device_serial = rand_slug("unit", 10)
    automation_secret = rand_slug("token", 10)
    ticket = client.create_ticket(
        user.token,
        title=title,
        description=description,
        priority="high",
        report_template="Case {{ ticket.case_number }} {{ user.username }}",
        vendor_case_id=vendor_case_id,
        device_serial=device_serial,
        automation_secret=automation_secret,
    )

    tickets = client.list_tickets(user.token)
    ensure(any(item.get("id") == ticket.ticket_id for item in tickets), "new ticket missing from list")

    ticket_view = client.get_ticket(user.token, ticket.ticket_id)
    ensure(ticket_view.get("title") == title, "ticket title mismatch", repr(ticket_view))
    ensure(ticket_view.get("device_serial") == device_serial, "ticket device_serial mismatch", repr(ticket_view))

    message_body = rand_slug("update", 12)
    message = client.add_message(user.token, ticket.ticket_id, message_body)
    messages = client.list_messages(user.token, ticket.ticket_id)
    ensure(any(item.get("id") == message.get("id") and item.get("body") == message_body for item in messages),
           "message not visible after creation")

    artifact_name = rand_attachment_name()
    artifact_content = f"artifact-{secrets.token_hex(8)}".encode("utf-8")
    artifact = client.upload_artifact(
        user.token,
        ticket.ticket_id,
        filename=artifact_name,
        content=artifact_content,
        description=rand_attachment_note(),
        content_type=mimetypes.guess_type(artifact_name)[0] or "text/plain",
    )
    artifacts = client.list_artifacts(user.token, ticket.ticket_id)
    ensure(any(item.get("id") == artifact.get("id") for item in artifacts), "artifact not visible after upload")
    direct_blob = client.download_artifact(user.token, ticket.ticket_id, str(artifact["id"]))
    safe_blob = client.safe_download_artifact(user.token, str(artifact["id"]))
    ensure(direct_blob == artifact_content, "ticket artifact download mismatch")
    ensure(safe_blob == artifact_content, "safe artifact download mismatch")

    report = client.create_report(
        user.token,
        ticket.ticket_id,
        template="{{ ticket.case_number }}|{{ user.username }}|{{ runtime.brand }}",
    )
    report_content = str(report.get("content", ""))
    ensure(ticket.case_number in report_content and user.username in report_content,
           "report rendering produced unexpected content", repr(report))

    exported = client.create_export(user.token, ticket.ticket_id)
    export_resp = client.download_by_path(user.token, str(exported.get("download_path", "")))
    export_text = export_resp.text
    ensure(title in export_text and device_serial in export_text, "export download missing ticket data")

    share = client.create_share(user.token, ticket.ticket_id)
    share_view = client.view_share(str(share.get("share_path", "")))
    share_ticket = share_view.get("ticket") or {}
    share_messages = share_view.get("messages") or []
    ensure(share_ticket.get("title") == title, "share view title mismatch", repr(share_view))
    ensure(any(item.get("body") == message_body for item in share_messages), "share view missing message")

    notifications = client.list_notifications(user.token, include_own=True)
    items = notifications.get("items") or []
    ensure(any(item.get("ticket_id") == ticket.ticket_id for item in items), "notifications missing ticket events")

    integration = client.create_integration(
        user.token,
        {
            "name": rand_slug("hook"),
            "ticket_id": ticket.ticket_id,
            "webhook_url": "http://dispatchboard:8081/dispatch/invalid/receipts",
        },
    )
    integration_id = str(integration.get("id", ""))
    ensure(integration_id, "integration id missing", repr(integration))

    renamed = rand_slug("hookrenamed")
    patched = client.patch_integration(user.token, integration_id, {"name": renamed})
    ensure(patched.get("name") == renamed, "integration rename did not persist", repr(patched))

    integrations = client.list_integrations(user.token)
    ensure(any(item.get("id") == integration_id and item.get("name") == renamed for item in integrations),
           "integration missing from list after patch")

    trigger = client.trigger_integration(user.token, integration_id)
    ensure(trigger.get("status_code") == 403, "integration trigger did not reach dispatchboard", repr(trigger))
    ensure(trigger.get("ok") is False, "integration trigger unexpectedly succeeded", repr(trigger))

    quit_with(OK, "OK", "check passed")


def put_vuln_1(client: ServiceDeskClient, user: UserSession, flag: str) -> dict[str, Any]:
    ticket = create_populated_ticket(client, user.token)
    message = client.add_message(user.token, ticket.ticket_id, flag)
    return {
        "username": user.username,
        "password": user.password,
        "ticket_id": ticket.ticket_id,
        "message_id": str(message.get("id", "")),
    }


def get_vuln_1(client: ServiceDeskClient, meta: dict[str, Any], flag: str) -> None:
    messages = client.list_messages(meta["token"], meta["ticket_id"], code=CORRUPT)
    for item in messages:
        if str(item.get("id")) == meta["message_id"]:
            if item.get("body") != flag:
                raise Verdict(CORRUPT, "flag corrupted", repr(item))
            return
    raise Verdict(CORRUPT, "message missing", repr(messages))


def put_vuln_2(client: ServiceDeskClient, user: UserSession, flag: str) -> dict[str, Any]:
    ticket = create_populated_ticket(client, user.token, flag_field="description", flag=flag)
    return {"username": user.username, "password": user.password, "ticket_id": ticket.ticket_id}


def get_vuln_2(client: ServiceDeskClient, meta: dict[str, Any], flag: str) -> None:
    ticket = client.get_ticket(meta["token"], meta["ticket_id"], code=CORRUPT)
    if ticket.get("description") != flag:
        raise Verdict(CORRUPT, "flag corrupted", repr(ticket))


def put_vuln_3(client: ServiceDeskClient, user: UserSession, flag: str) -> dict[str, Any]:
    ticket = create_populated_ticket(client, user.token)
    filename = f"{rand_slug(secrets.choice(ATTACHMENT_PREFIXES))}.bin"
    artifact = client.upload_artifact(
        user.token,
        ticket.ticket_id,
        filename=filename,
        content=flag.encode("utf-8"),
        description=rand_attachment_note(),
        content_type="application/octet-stream",
    )
    return {
        "username": user.username,
        "password": user.password,
        "ticket_id": ticket.ticket_id,
        "artifact_id": str(artifact.get("id", "")),
    }


def get_vuln_3(client: ServiceDeskClient, meta: dict[str, Any], flag: str) -> None:
    blob = client.safe_download_artifact(meta["token"], meta["artifact_id"], code=CORRUPT)
    if blob.decode("utf-8", errors="replace") != flag:
        raise Verdict(CORRUPT, "artifact content mismatch", short(blob.decode("utf-8", errors="replace")))


def put_vuln_4(client: ServiceDeskClient, user: UserSession, flag: str) -> dict[str, Any]:
    ticket = create_populated_ticket(client, user.token, flag_field="vendor_case_id", flag=flag)
    share = client.create_share(user.token, ticket.ticket_id)
    return {
        "username": user.username,
        "password": user.password,
        "share_path": str(share.get("share_path", "")),
    }


def get_vuln_4(client: ServiceDeskClient, meta: dict[str, Any], flag: str) -> None:
    share_view = client.view_share(meta["share_path"], code=CORRUPT)
    ticket = share_view.get("ticket") or {}
    if ticket.get("vendor_case_id") != flag:
        raise Verdict(CORRUPT, "share flag mismatch", repr(ticket))


def put_vuln_5(client: ServiceDeskClient, user: UserSession, flag: str) -> dict[str, Any]:
    ticket = create_populated_ticket(client, user.token, flag_field="automation_secret", flag=flag)
    return {"username": user.username, "password": user.password, "ticket_id": ticket.ticket_id}


def get_vuln_5(client: ServiceDeskClient, meta: dict[str, Any], flag: str) -> None:
    report = client.create_report(
        meta["token"],
        meta["ticket_id"],
        template="{{ ticket.automation_secret }}",
        code=CORRUPT,
    )
    if str(report.get("content", "")).strip() != flag:
        raise Verdict(CORRUPT, "automation_secret mismatch", repr(report))


def put_vuln_6(client: ServiceDeskClient, user: UserSession, flag: str) -> dict[str, Any]:
    ticket = create_populated_ticket(client, user.token, flag_field="device_serial", flag=flag)
    return {"username": user.username, "password": user.password, "ticket_id": ticket.ticket_id}


def get_vuln_6(client: ServiceDeskClient, meta: dict[str, Any], flag: str) -> None:
    exported = client.create_export(meta["token"], meta["ticket_id"], code=CORRUPT)
    resp = client.download_by_path(meta["token"], str(exported.get("download_path", "")), code=CORRUPT)
    expected_line = f"Device Serial: {flag}"
    if expected_line not in resp.text:
        raise Verdict(CORRUPT, "device serial missing from export", short(resp.text))


def put_vuln_7(client: ServiceDeskClient, user: UserSession, flag: str) -> dict[str, Any]:
    updated = client.patch_me(user.token, {"contact_phone": flag})
    ensure(updated.get("contact_phone") == flag, "contact_phone update failed", repr(updated))
    create_populated_ticket(client, user.token)
    return {"username": user.username, "password": user.password}


def get_vuln_7(client: ServiceDeskClient, meta: dict[str, Any], flag: str) -> None:
    me = client.get_me(meta["token"], code=CORRUPT)
    if me.get("contact_phone") != flag:
        raise Verdict(CORRUPT, "contact phone mismatch", repr(me))


PUTTERS = {
    "1": put_vuln_1,
    "2": put_vuln_2,
    "3": put_vuln_3,
    "4": put_vuln_4,
    "5": put_vuln_5,
    "6": put_vuln_6,
    "7": put_vuln_7,
}

GETTERS = {
    "1": get_vuln_1,
    "2": get_vuln_2,
    "3": get_vuln_3,
    "4": get_vuln_4,
    "5": get_vuln_5,
    "6": get_vuln_6,
    "7": get_vuln_7,
}


def put(host: str, round_id: str, flag: str, vuln: str) -> None:
    vuln = normalize_vuln(vuln)
    client, user = make_user_and_client(host)
    meta = PUTTERS[vuln](client, user, flag)
    data = {
        "vuln": vuln,
        "user": meta.pop("username"),
        "password": meta.pop("password"),
        "meta": meta,
        "round_id": round_id,
    }
    quit_with(OK, encode_flag_id(data), "put completed")


def get(host: str, flag_id: str, flag: str, vuln: str) -> None:
    vuln = normalize_vuln(vuln)
    data = decode_flag_id(flag_id)
    if str(data.get("vuln")) != vuln:
        raise Verdict(CHECKER_ERROR, "CHECKER_ERROR", "flag_id vuln mismatch")

    username = str(data.get("user", ""))
    password = str(data.get("password", ""))
    meta = data.get("meta", {})
    ensure(username and password and isinstance(meta, dict), "CHECKER_ERROR", repr(data), code=CHECKER_ERROR)

    client = ServiceDeskClient(host)
    user = client.login(username, password, public="login for get failed", code=CORRUPT)
    meta["token"] = user.token
    GETTERS[vuln](client, meta, flag)
    quit_with(OK, "OK", "get completed")


def normalize_vuln(vuln: str | None) -> str:
    value = str(vuln or "1").strip()
    if value not in VULNS:
        raise Verdict(CHECKER_ERROR, "CHECKER_ERROR", f"unsupported vuln slot: {value}")
    return value


def usage() -> None:
    print("usage:")
    print("  checker.py check <host>")
    print("  checker.py put   <host> <round_id> <flag> <vuln>")
    print("  checker.py get   <host> <flag_id>  <flag> <vuln>")


def run_from_env() -> None:
    action = os.getenv("ACTION", "").strip().upper()
    host = os.getenv("HOST", "").strip()
    flag = os.getenv("FLAG", "")
    flag_id = os.getenv("FLAG_ID", "")
    vuln = os.getenv("VULN", "1")

    if action == "CHECK_SLA":
        check(host)
        return
    if action == "PUT":
        put(host, os.getenv("ROUND_ID", ""), flag, vuln)
        return
    if action == "GET":
        get(host, flag_id, flag, vuln)
        return
    raise Verdict(CHECKER_ERROR, "CHECKER_ERROR", f"unsupported ACTION={action!r}")


def main() -> None:
    try:
        if len(sys.argv) >= 2:
            action = sys.argv[1].lower()
            if action == "check" and len(sys.argv) == 3:
                check(sys.argv[2])
                return
            if action == "put" and len(sys.argv) == 6:
                put(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
                return
            if action == "get" and len(sys.argv) == 6:
                get(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
                return
            if action in {"check", "put", "get"}:
                usage()
                raise Verdict(CHECKER_ERROR, "CHECKER_ERROR", "bad argument count")
        elif os.getenv("ACTION"):
            run_from_env()
            return
        else:
            usage()
            raise Verdict(CHECKER_ERROR, "CHECKER_ERROR", "no action provided")
    except Verdict as verdict:
        quit_with(verdict.code, verdict.public, verdict.private)


if __name__ == "__main__":
    try:
        main()
    except Verdict as verdict:
        quit_with(verdict.code, verdict.public, verdict.private)
    except SystemExit:
        raise
    except Exception as exc:
        quit_with(CHECKER_ERROR, "CHECKER_ERROR", repr(exc))
