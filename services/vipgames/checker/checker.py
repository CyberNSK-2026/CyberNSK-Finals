#!/usr/bin/env python3
import base64
import http.cookiejar
import hashlib
import hmac
import json
import os
import random
import string
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any, Callable, Dict, Optional

OK = 101
CORRUPT = 102
MUMBLE = 103
DOWN = 104
CHECKER_ERROR = 110

TIMEOUT = float(os.getenv("CHECKER_TIMEOUT", "4.0"))
CHECKER_SECRET = os.getenv("CHECKER_SECRET", "vipgames-change-me")
SERVICE_PORT = 8642

VULN_KEYS = {
    "1": "achievements",
    "2": "puzzle",
    "3": "petfarm",
    "4": "alchemy",
    "5": "cards",
    "achievements": "achievements",
    "puzzle": "puzzle",
    "petfarm": "petfarm",
    "alchemy": "alchemy",
    "cards": "cards",
}


@dataclass
class HttpResponse:
    status_code: int
    text: str


def quit_with(code: int, public: str, private: str = "") -> None:
    if private:
        print(private, file=sys.stderr)
    print(public)
    raise SystemExit(code)


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


def rand_token(n: int = 8) -> str:
    alphabet = string.ascii_lowercase + string.digits
    return "".join(random.choice(alphabet) for _ in range(n))


def hmac_hex(payload: bytes) -> str:
    return hmac.new(CHECKER_SECRET.encode(), payload, hashlib.sha256).hexdigest()


def b64u(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def b64u_dec(data: str) -> bytes:
    pad = "=" * ((4 - len(data) % 4) % 4)
    return base64.urlsafe_b64decode(data + pad)


def encode_flag_id(obj: Dict[str, Any]) -> str:
    raw = json.dumps(obj, separators=(",", ":"), sort_keys=True).encode()
    return f"{b64u(raw)}.{hmac_hex(raw)}"


def decode_flag_id(token: str) -> Dict[str, Any]:
    try:
        payload_b64, sig = token.split(".", 1)
        raw = b64u_dec(payload_b64)
    except Exception as exc:
        raise ValueError(f"bad flag id format: {exc}") from exc
    good_sig = hmac_hex(raw)
    if not hmac.compare_digest(sig, good_sig):
        raise ValueError("bad flag id signature")
    obj = json.loads(raw.decode())
    if not isinstance(obj, dict):
        raise ValueError("bad flag id body")
    return obj


@dataclass
class Checker:
    base_url: str
    opener: urllib.request.OpenerDirector

    @classmethod
    def create(cls, host: str) -> "Checker":
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        return cls(base_url=normalize_host(host), opener=opener)

    def _request(
        self,
        method: str,
        path: str,
        json_body: Optional[Dict[str, Any]] = None,
    ) -> "HttpResponse":
        url = self.base_url + path
        headers = {"User-Agent": "vipgames-checker/1.0"}
        data: Optional[bytes] = None
        if json_body is not None:
            data = json.dumps(json_body).encode()
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url=url, method=method.upper(), data=data, headers=headers)
        try:
            with self.opener.open(req, timeout=TIMEOUT) as resp:
                body = resp.read().decode("utf-8", errors="replace")
                return HttpResponse(status_code=resp.getcode(), text=body)
        except urllib.error.HTTPError as exc:
            try:
                body = exc.read().decode("utf-8", errors="replace")
            except Exception:
                body = ""
            return HttpResponse(status_code=exc.code, text=body)
        except Exception as exc:
            quit_with(DOWN, "DOWN", f"network error for {url}: {exc}")
        raise AssertionError("unreachable")

    def _json(self, resp: "HttpResponse") -> Dict[str, Any]:
        try:
            obj = json.loads(resp.text)
            if not isinstance(obj, dict):
                quit_with(MUMBLE, "MUMBLE", "json response is not an object")
            return obj
        except Exception as exc:
            quit_with(MUMBLE, "MUMBLE", f"invalid json: {exc}; body={resp.text[:400]}")
        raise AssertionError("unreachable")

    def _ensure(self, cond: bool, message: str) -> None:
        if not cond:
            quit_with(MUMBLE, "MUMBLE", message)

    def register_and_login(self, username: str, password: str) -> None:
        reg = self._request(
            "POST",
            "/api/auth/register",
            json_body={"username": username, "password": password},
        )
        if reg.status_code not in (200, 201, 409):
            quit_with(MUMBLE, "MUMBLE", f"register status={reg.status_code}")

        login = self._request(
            "POST",
            "/api/auth/login",
            json_body={"username": username, "password": password},
        )
        self._ensure(login.status_code == 200, f"login status={login.status_code}")

    def check(self) -> None:
        index = self._request("GET", "/")
        self._ensure(index.status_code == 200, f"index status={index.status_code}")

        username = f"chk_{rand_token(10)}"
        password = f"pw_{rand_token(18)}"
        self.register_and_login(username, password)

        profile = self._request("GET", "/api/profile/me")
        self._ensure(profile.status_code == 200, f"profile status={profile.status_code}")

        for page in ("/portal", "/games/puzzle", "/games/petfarm", "/games/alchemy", "/games/cards", "/achievements"):
            resp = self._request("GET", page)
            self._ensure(resp.status_code == 200, f"page {page} status={resp.status_code}")

        for game in ("puzzle", "petfarm", "alchemy", "cards"):
            resp = self._request("GET", f"/api/games/{game}")
            self._ensure(resp.status_code == 200, f"game page {game} status={resp.status_code}")

        sanity_cases = [
            (self.put_achievements, self.get_achievements, f"SANITY_ACH_{rand_token(12).upper()}"),
            (self.put_puzzle, self.get_puzzle, f"SANITY_PUZ_{rand_token(12).upper()}"),
            (self.put_petfarm, self.get_petfarm, f"SANITY_PET_{rand_token(12).upper()}"),
            (self.put_alchemy, self.get_alchemy, f"SANITY_ALC_{rand_token(12).upper()}"),
            (self.put_cards, self.get_cards, f"SANITY_CAR_{rand_token(12).upper()}"),
        ]
        for putter, getter, marker in sanity_cases:
            meta = putter(marker)
            got = getter(meta)
            self._ensure(got == marker, f"sanity mismatch: expected={marker} got={got}")

    def put(self, flag: str, vuln: str, round_id: str, slot: str) -> str:
        username = deterministic_username(self.base_url, vuln, round_id, slot)
        password = deterministic_password(self.base_url, vuln, round_id, slot)
        self.register_and_login(username, password)

        putters: Dict[str, Callable[[str], Dict[str, Any]]] = {
            "achievements": self.put_achievements,
            "puzzle": self.put_puzzle,
            "petfarm": self.put_petfarm,
            "alchemy": self.put_alchemy,
            "cards": self.put_cards,
        }
        meta = putters[vuln](flag)
        data = {
            "v": vuln,
            "u": username,
            "m": meta,
            "r": round_id,
            "s": slot,
            "t": int(time.time()),
        }
        return encode_flag_id(data)

    def get(self, flag_id: str, flag: str, vuln: str) -> None:
        data = decode_flag_id(flag_id)
        if data.get("v") != vuln:
            quit_with(CORRUPT, "CORRUPT", "vuln mismatch in flag_id")
        username = str(data.get("u", ""))
        round_id = str(data.get("r", ""))
        slot = str(data.get("s", ""))
        password = str(data.get("p") or deterministic_password(self.base_url, vuln, round_id, slot))
        meta = data.get("m", {})
        if not username or not password or not round_id or not slot or not isinstance(meta, dict):
            quit_with(CORRUPT, "CORRUPT", "invalid flag_id fields")

        self.register_and_login(username, password)

        getters: Dict[str, Callable[[Dict[str, Any]], str]] = {
            "achievements": self.get_achievements,
            "puzzle": self.get_puzzle,
            "petfarm": self.get_petfarm,
            "alchemy": self.get_alchemy,
            "cards": self.get_cards,
        }
        got = getters[vuln](meta)
        if got != flag:
            quit_with(CORRUPT, "CORRUPT", f"flag mismatch: expected={flag} got={got}")

    def put_achievements(self, flag: str) -> Dict[str, Any]:
        j = self._request(
            "POST",
            "/api/achievements/journal",
            json_body={"title": "chronicle", "note": flag},
        )
        self._ensure(j.status_code in (200, 201), f"journal status={j.status_code}")
        j_obj = self._json(j)
        entry_id = j_obj.get("id")
        self._ensure(entry_id is not None, "missing journal id")

        u = self._request(
            "POST",
            "/api/achievements/unlock",
            json_body={"code": "ARCHIVIST", "sourceEntryId": entry_id},
        )
        self._ensure(u.status_code in (200, 201), f"unlock status={u.status_code}")
        obj = self._json(u)
        aid = obj.get("achievementId")
        self._ensure(aid is not None, "missing achievementId")
        return {"aid": aid, "code": "ARCHIVIST"}

    def get_achievements(self, meta: Dict[str, Any]) -> str:
        aid = meta.get("aid")
        if aid is not None:
            resp = self._request("GET", f"/api/achievements/board/me/details?achievementId={aid}")
        else:
            code = str(meta.get("code", "ARCHIVIST"))
            resp = self._request("GET", f"/api/achievements/board/me/details?code={code}")
        self._ensure(resp.status_code == 200, f"achievement details status={resp.status_code}")
        obj = self._json(resp)
        note = obj.get("secretNote")
        if not isinstance(note, str):
            quit_with(CORRUPT, "CORRUPT", "missing secretNote in achievement details")
        return note

    def put_puzzle(self, flag: str) -> Dict[str, Any]:
        c = self._request("POST", "/api/games/puzzle/boards", json_body={"title": f"board-{rand_token(6)}"})
        self._ensure(c.status_code in (200, 201), f"create puzzle board status={c.status_code}")
        cid = self._json(c).get("id")
        self._ensure(cid is not None, "missing puzzle id")

        s = self._request(
            "POST",
            f"/api/games/puzzle/{cid}/save-stego",
            json_body={"payload": flag, "mode": "checker"},
        )
        self._ensure(s.status_code in (200, 201), f"save stego status={s.status_code}")
        return {"pid": cid}

    def get_puzzle(self, meta: Dict[str, Any]) -> str:
        pid = meta.get("pid")
        self._ensure(pid is not None, "missing puzzle id")
        r = self._request("GET", f"/api/games/puzzle/{pid}/preview?mode=solved")
        self._ensure(r.status_code == 200, f"puzzle preview status={r.status_code}")
        obj = self._json(r)
        payload = obj.get("hiddenPayload")
        if not isinstance(payload, str):
            quit_with(CORRUPT, "CORRUPT", "missing hiddenPayload in puzzle preview")
        return payload

    def put_petfarm(self, flag: str) -> Dict[str, Any]:
        p = self._request(
            "POST",
            "/api/games/petfarm/pets",
            json_body={"name": f"pet-{rand_token(5)}", "tag": flag},
        )
        self._ensure(p.status_code in (200, 201), f"create pet status={p.status_code}")
        pid = self._json(p).get("id")
        self._ensure(pid is not None, "missing pet id")
        return {"pet": pid}

    def get_petfarm(self, meta: Dict[str, Any]) -> str:
        pid = meta.get("pet")
        self._ensure(pid is not None, "missing pet id")
        r = self._request("GET", f"/api/games/petfarm/pets/{pid}")
        self._ensure(r.status_code == 200, f"pet get status={r.status_code}")
        obj = self._json(r)
        tag = obj.get("tag")
        if not isinstance(tag, str):
            quit_with(CORRUPT, "CORRUPT", "missing pet tag")
        return tag

    def put_alchemy(self, flag: str) -> Dict[str, Any]:
        c = self._request("POST", "/api/games/alchemy/runs", json_body={"recipe": "moon_salt"})
        self._ensure(c.status_code in (200, 201), f"create run status={c.status_code}")
        rid = self._json(c).get("id")
        self._ensure(rid is not None, "missing run id")

        f = self._request(
            "POST",
            f"/api/games/alchemy/runs/{rid}/finalize",
            json_body={"artifactNote": flag},
        )
        self._ensure(f.status_code in (200, 201), f"finalize status={f.status_code}")
        return {"rid": rid}

    def get_alchemy(self, meta: Dict[str, Any]) -> str:
        rid = meta.get("rid")
        self._ensure(rid is not None, "missing run id")
        r = self._request("GET", f"/api/games/alchemy/runs/{rid}/artifact")
        self._ensure(r.status_code == 200, f"artifact status={r.status_code}")
        obj = self._json(r)
        note = obj.get("artifactNote")
        if not isinstance(note, str):
            quit_with(CORRUPT, "CORRUPT", "missing artifactNote")
        return note

    def put_cards(self, flag: str) -> Dict[str, Any]:
        c = self._request(
            "POST",
            "/api/games/cards",
            json_body={"customName": flag, "power": random.randint(10, 99)},
        )
        self._ensure(c.status_code in (200, 201), f"create card status={c.status_code}")
        cid = self._json(c).get("id")
        self._ensure(cid is not None, "missing card id")
        return {"cid": cid}

    def get_cards(self, meta: Dict[str, Any]) -> str:
        cid = meta.get("cid")
        self._ensure(cid is not None, "missing card id")
        r = self._request("GET", f"/api/games/cards/{cid}")
        self._ensure(r.status_code == 200, f"card get status={r.status_code}")
        obj = self._json(r)
        name = obj.get("customName")
        if not isinstance(name, str):
            quit_with(CORRUPT, "CORRUPT", "missing card customName")
        return name


def deterministic_username(host: str, vuln: str, round_id: str, slot: str) -> str:
    seed = f"{host}|{vuln}|{round_id}|{slot}".encode()
    digest = hashlib.sha256(seed).hexdigest()[:16]
    return f"u_{vuln[:3]}_{digest}"


def deterministic_password(host: str, vuln: str, round_id: str, slot: str) -> str:
    seed = f"pw|{host}|{vuln}|{round_id}|{slot}".encode()
    digest = hashlib.sha256(seed).hexdigest()
    return f"P_{digest[:28]}"


def parse_vuln(raw: str) -> str:
    key = raw.strip().lower()
    if key not in VULN_KEYS:
        quit_with(CHECKER_ERROR, "CHECKER_ERROR", f"unknown vuln: {raw}")
    return VULN_KEYS[key]


def self_test() -> None:
    sample = {"v": "cards", "u": "u_abc", "m": {"cid": 42}, "r": "11", "s": "4"}
    token = encode_flag_id(sample)
    out = decode_flag_id(token)
    if out != sample:
        quit_with(CHECKER_ERROR, "CHECKER_ERROR", "flag_id roundtrip failed")
    _ = parse_vuln("0")
    _ = parse_vuln("cards")
    print("self-test ok")


def usage() -> None:
    print("usage:")
    print("  checker.py check <host>")
    print("  checker.py put <host> <id> <flag> <vuln>")
    print("  checker.py get <host> <flag_id> <flag> <vuln>")
    print("  checker.py smoke <host>")
    print("  checker.py self-test")


def main() -> None:
    random.seed()
    argv = sys.argv
    if len(argv) < 2:
        usage()
        quit_with(CHECKER_ERROR, "CHECKER_ERROR", "missing action")
    action = argv[1].lower()

    if action == "self-test":
        self_test()
        return

    if action == "smoke":
        if len(argv) != 3:
            usage()
            quit_with(CHECKER_ERROR, "CHECKER_ERROR", "bad smoke args")
        host = argv[2]
        vuln_order = ["achievements", "puzzle", "petfarm", "alchemy", "cards"]
        for vuln in vuln_order:
            flag = f"SMOKE_{vuln}_{rand_token(10)}"
            chk = Checker.create(host)
            flag_id = chk.put(flag=flag, vuln=vuln, round_id="smoke", slot=vuln)
            chk = Checker.create(host)
            chk.get(flag_id=flag_id, flag=flag, vuln=vuln)
        quit_with(OK, "OK", "smoke passed")

    if action == "check":
        if len(argv) != 3:
            usage()
            quit_with(CHECKER_ERROR, "CHECKER_ERROR", "bad check args")
        host = argv[2]
        chk = Checker.create(host)
        chk.check()
        quit_with(OK, "OK", "check passed")

    if action == "put":
        if len(argv) != 6:
            usage()
            quit_with(CHECKER_ERROR, "CHECKER_ERROR", "bad put args")
        host, round_id, flag, vuln_raw = argv[2], argv[3], argv[4], argv[5]
        vuln = parse_vuln(vuln_raw)
        chk = Checker.create(host)
        flag_id = chk.put(flag=flag, vuln=vuln, round_id=round_id, slot=vuln_raw)
        print(flag_id)
        raise SystemExit(OK)

    if action == "get":
        if len(argv) != 6:
            usage()
            quit_with(CHECKER_ERROR, "CHECKER_ERROR", "bad get args")
        host, flag_id, flag, vuln_raw = argv[2], argv[3], argv[4], argv[5]
        vuln = parse_vuln(vuln_raw)
        chk = Checker.create(host)
        chk.get(flag_id=flag_id, flag=flag, vuln=vuln)
        quit_with(OK, "OK", "get passed")

    usage()
    quit_with(CHECKER_ERROR, "CHECKER_ERROR", f"unknown action: {action}")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:
        quit_with(CHECKER_ERROR, "CHECKER_ERROR", f"unhandled exception: {exc}")
