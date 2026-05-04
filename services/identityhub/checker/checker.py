#!/usr/bin/env python3
import json
import os
import random
import string
import sys
import urllib.error
import urllib.parse
import urllib.request

OK             = 101
CORRUPT        = 102
MUMBLE         = 103
DOWN           = 104
CHECKER_ERROR  = 110

PORT    = int(os.getenv("SERVICE_PORT", "8768"))
TIMEOUT = float(os.getenv("CHECKER_TIMEOUT", "5.0"))

def quit_with(code: int, public: str, private: str = "") -> None:
    if private:
        print(private, file=sys.stderr)
    print(public)
    raise SystemExit(code)


def rand(n: int = 10) -> str:
    return "".join(random.choices(string.ascii_lowercase + string.digits, k=n))


def _request(method: str, url: str, body=None) -> tuple:
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"} if data else {}
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read().decode()
            try:
                return resp.status, json.loads(raw)
            except json.JSONDecodeError:
                return resp.status, None
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, None
    except (urllib.error.URLError, OSError) as e:
        quit_with(DOWN, "DOWN", f"connection error: {e}")


def _get(base: str, path: str, params: dict | None = None) -> tuple:
    url = f"{base}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    return _request("GET", url)


def _post(base: str, path: str, body: dict) -> tuple:
    return _request("POST", f"{base}{path}", body)

def check(host: str) -> None:
    base     = f"http://{host}:{PORT}"
    subject  = f"acct:{rand()}@identityhub.local"
    password = rand(16)

    status, data = _post(base, "/api/create_identity", {
        "subject": subject, "password": password, "is_public": True
    })
    if status != 201:
        quit_with(MUMBLE, "MUMBLE", f"create_identity returned {status}")
    if not data or "id" not in data or data.get("subject") != subject:
        quit_with(MUMBLE, "MUMBLE", "create_identity bad response")

    status, _ = _post(base, "/api/add_property", {
        "subject": subject, "password": password,
        "key": "http://schema.org/name", "value": rand(12), "sign": True
    })
    if status != 200:
        quit_with(MUMBLE, "MUMBLE", f"add_property returned {status}")

    status, _ = _post(base, "/api/add_link", {
        "subject": subject, "password": password,
        "rel": "http://webfinger.net/rel/profile-page",
        "href": f"https://example.com/{rand()}", "type": "text/html"
    })
    if status != 200:
        quit_with(MUMBLE, "MUMBLE", f"add_link returned {status}")

    status, _ = _post(base, "/api/add_alias", {
        "subject": subject, "password": password,
        "alias": f"https://example.com/users/{rand()}"
    })
    if status != 200:
        quit_with(MUMBLE, "MUMBLE", f"add_alias returned {status}")

    status, data = _post(base, "/api/verify_property", {
        "subject": subject, "key": "http://schema.org/name"
    })
    if status != 200 or not data or data.get("valid") is not True:
        quit_with(MUMBLE, "MUMBLE", f"verify_property failed: {status} {data}")

    status, jrd = _get(base, "/.well-known/webfinger", {"resource": subject})
    if status != 200 or not jrd:
        quit_with(MUMBLE, "MUMBLE", f"webfinger returned {status}")
    if jrd.get("subject") != subject:
        quit_with(MUMBLE, "MUMBLE", "webfinger subject mismatch")
    if not jrd.get("aliases") or not jrd.get("links"):
        quit_with(MUMBLE, "MUMBLE", "webfinger missing aliases/links")

    status, data = _get(base, "/api/public_key", {"subject": subject})
    if status != 200 or not data or "BEGIN PUBLIC KEY" not in data.get("public_key", ""):
        quit_with(MUMBLE, "MUMBLE", f"public_key failed: {status}")

    status, data = _get(base, "/api/search", {"query": subject[:15]})
    if status != 200 or not data or not data.get("results"):
        quit_with(MUMBLE, "MUMBLE", f"search failed: {status}")

    quit_with(OK, "OK", "check passed")

def put(host: str, flag: str) -> str:
    base     = f"http://{host}:{PORT}"
    username = rand(10)
    subject  = f"acct:{username}@identityhub.local"
    password = rand(16)

    status, data = _post(base, "/api/create_identity", {
        "subject": subject, "password": password, "is_public": False
    })
    if status != 201:
        quit_with(MUMBLE, "MUMBLE", f"put: create_identity returned {status}")

    status, _ = _post(base, "/api/add_property", {
        "subject": subject, "password": password,
        "key": "flag", "value": flag
    })
    if status != 200:
        quit_with(MUMBLE, "MUMBLE", f"put: add_property returned {status}")

    _post(base, "/api/add_property", {
        "subject": subject, "password": password,
        "key": "http://schema.org/name", "value": f"User {username}", "sign": True
    })
    _post(base, "/api/add_link", {
        "subject": subject, "password": password,
        "rel": "http://webfinger.net/rel/profile-page",
        "href": f"https://identityhub.local/profile/{username}", "type": "text/html"
    })

    status, _ = _get(base, "/.well-known/webfinger", {"resource": subject})
    if status != 404:
        quit_with(MUMBLE, "MUMBLE", "put: private identity exposed in webfinger")

    return f"{subject}:{password}"

def get_flag(host: str, flag_id: str, expected_flag: str) -> None:
    base = f"http://{host}:{PORT}"

    try:
        last_colon = flag_id.rfind(":")
        subject    = flag_id[:last_colon]
        password   = flag_id[last_colon + 1:]
        if not subject or not password:
            raise ValueError("empty parts")
    except Exception as e:
        quit_with(CHECKER_ERROR, "CHECKER_ERROR", f"get: bad flag_id format: {e}")

    status, _ = _post(base, "/api/sign_property", {
        "subject": subject, "password": password, "key": "flag"
    })
    if status == 404:
        quit_with(CORRUPT, "CORRUPT", f"get: identity not found: {subject}")
    if status == 403:
        quit_with(CORRUPT, "CORRUPT", "get: wrong password")
    if status != 200:
        quit_with(MUMBLE, "MUMBLE", f"get: sign_property returned {status}")

    status, data = _post(base, "/api/verify_property", {
        "subject": subject, "key": "flag"
    })
    if status == 404:
        quit_with(CORRUPT, "CORRUPT", "get: flag property not found")
    if status != 200 or not data:
        quit_with(MUMBLE, "MUMBLE", f"get: verify_property returned {status}")

    value = data.get("value", "")
    if value != expected_flag:
        quit_with(CORRUPT, "CORRUPT",
                  f"get: flag mismatch: expected={expected_flag!r} got={value!r}")

    quit_with(OK, "OK", "get passed")

def usage() -> None:
    print("usage:")
    print("  checker.py check <host>")
    print("  checker.py put   <host> <round_id> <flag> <vuln>")
    print("  checker.py get   <host> <flag_id>  <flag> <vuln>")


def main() -> None:
    random.seed()
    argv = sys.argv
    if len(argv) < 2:
        usage()
        quit_with(CHECKER_ERROR, "CHECKER_ERROR", "missing action")

    action = argv[1].lower()

    if action == "check":
        if len(argv) != 3:
            usage()
            quit_with(CHECKER_ERROR, "CHECKER_ERROR", "bad check args")
        check(argv[2])

    elif action == "put":
        if len(argv) != 6:
            usage()
            quit_with(CHECKER_ERROR, "CHECKER_ERROR", "bad put args")
        host, _round_id, flag, _vuln = argv[2], argv[3], argv[4], argv[5]
        flag_id = put(host, flag)
        print(flag_id)
        raise SystemExit(OK)

    elif action == "get":
        if len(argv) != 6:
            usage()
            quit_with(CHECKER_ERROR, "CHECKER_ERROR", "bad get args")
        host, flag_id, flag, _vuln = argv[2], argv[3], argv[4], argv[5]
        get_flag(host, flag_id, flag)

    else:
        usage()
        quit_with(CHECKER_ERROR, "CHECKER_ERROR", f"unknown action: {action}")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:
        quit_with(CHECKER_ERROR, "CHECKER_ERROR", f"unhandled exception: {exc}")
