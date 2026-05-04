#!/usr/bin/env python3
"""
ForcAD / Hackerdom-style checker for CheckD (gateway).

Env:
  CHECKD_PORT   — TCP порт публичного nginx (по умолчанию 8081).
  CHECKD_SCHEME — http или https (по умолчанию http).

Статусы: нарушение контракта API / схемы при ожидаемом успехе → ``CORRUPT``;
ошибка входных данных чекера (``vuln``, битое состояние) → ``MUMBLE``.
``DOWN`` — сеть/5xx (через ``check_response`` / исключения в ``_req``).

Запуск:
  python3 checker.py check <host>
  python3 checker.py put  <host> <flag_id> <flag> <vuln>
  python3 checker.py get  <host> <flag_id> <flag> <vuln>
  python3 checker.py info <host>

Уязвимости (``vuln`` = 1..4), флаг кладётся в:
  1 — тело user-файла (чтение через ``/api/files/get``).
  2 — скрытый публичный чеклист (``is_hidden``, ``is_public``), флаг в ``description`` вопроса.
  3 — публичный чеклист, нейтральный вопрос (см. ``names.flag_prompt_question``), ответ — флаг; PDF.
  4 — приватный чеклист (``is_public: false``), тот же паттерн; PDF.

``check`` — smoke без флагов (включая SSO и PDF без разбора текста).
"""

from __future__ import annotations

import base64
import json
import os
import sys
import warnings
from typing import Any, Optional

# До import requests/urllib3: варнинг вылетает на импорте urllib3 (LibreSSL на macOS).
warnings.filterwarnings(
    "ignore",
    message="urllib3 v2 only supports OpenSSL 1.1.1+",
    module="urllib3",
)

import requests
from checklib import BaseChecker, Status, rnd_password, rnd_string
from checklib.checker import CheckFinished
from checklib.utils import cquit

from names import (
    flag_prompt_question,
    random_checklist_description,
    random_checklist_title,
    random_display_user,
    random_email,
    random_filename,
    slot_question_labels,
    smoke_pair_labels,
)
from pdf_text import flag_visible_in_pdf_relaxed
from sso_crypto import load_rsa_public_key, verify_token_verfer_style


def _service_port() -> int:
    raw = os.environ.get("SERVICE_PORT", os.environ.get("CHECKD_PORT", "8081")).strip()
    return int(raw) if raw.isdigit() else 8081


def _service_scheme() -> str:
    s = (os.environ.get("CHECKD_SCHEME") or "http").strip().lower()
    return s if s in ("http", "https") else "http"


def _b64json(obj: Any) -> str:
    return base64.standard_b64encode(json.dumps(obj, separators=(",", ":")).encode()).decode()


def _from_b64json(s: str) -> Any:
    pad = "=" * (-len(s) % 4)
    return json.loads(base64.standard_b64decode(s + pad).decode())


def _norm_stored_filename(name: str) -> str:
    t = str(name).strip()
    if len(t) >= 2 and t[0] == t[-1] == "'":
        t = t[1:-1].replace("''", "'")
    return t


def _user_id_from_session_token(token: str) -> int:
    part0 = token.split(".", 1)[0]
    pad = "=" * (-len(part0) % 4)
    payload = json.loads(base64.standard_b64decode(part0 + pad).decode())
    uid = payload.get("userID")
    if not isinstance(uid, int) or uid <= 0:
        raise ValueError("no userID in session payload")
    return uid


def _parse_vuln(vuln: str) -> int:
    try:
        n = int(str(vuln).strip())
    except ValueError as e:
        raise ValueError("vuln not int") from e
    if n < 1 or n > 4:
        raise ValueError("vuln out of range")
    return n


class CheckDChecker(BaseChecker):
    vulns = 4
    timeout = 15

    def __init__(self, host: str):
        super().__init__(host)
        self._port = _service_port()
        self._scheme = _service_scheme()
        self._base = f"{self._scheme}://{host}:{self._port}".rstrip("/")
        self._http_timeout = (7, 130)

    def _url(self, path: str) -> str:
        if not path.startswith("/"):
            path = "/" + path
        return f"{self._base}{path}"

    def _req(
        self,
        method: str,
        path: str,
        *,
        token: Optional[str] = None,
        json_body: Any = None,
        params: Optional[dict[str, str]] = None,
    ) -> requests.Response:
        headers: dict[str, str] = {}
        if token is not None:
            headers["Authorization"] = f"Custom {token}"
        try:
            r = requests.request(
                method,
                self._url(path),
                headers=headers,
                json=json_body,
                params=params,
                timeout=self._http_timeout,
            )
        except requests.exceptions.ConnectionError as e:
            self.cquit(Status.DOWN, "connection error", str(e))
        except requests.exceptions.Timeout as e:
            self.cquit(Status.DOWN, "timeout", str(e))
        return r

    def _auth_token_from_register(self, user: str, email: str, password: str) -> str:
        r = self._req("POST", "/api/auth/register", json_body={"user": user, "email": email, "pass": password})
        self.check_response(r, "register http")
        data = self.get_json(r, "register json")
        if not data.get("ok"):
            self.cquit(Status.MUMBLE, "register failed", str(data.get("error")))
        tok = data.get("token")
        if not tok:
            self.cquit(Status.CORRUPT, "register no token", "ok but missing token breaks contract")
        return str(tok)

    def _auth_token_from_login(self, email: str, password: str) -> str:
        r = self._req("POST", "/api/auth/login", json_body={"email": email, "pass": password})
        self.check_response(r, "login http")
        data = self.get_json(r, "login json")
        if not data.get("ok"):
            self.cquit(Status.MUMBLE, "login failed", str(data.get("error")))
        tok = data.get("token")
        if not tok:
            self.cquit(Status.CORRUPT, "login no token", "ok but missing token breaks contract")
        return str(tok)

    def _health(self) -> None:
        r = self._req("GET", "/health")
        self.check_response(r, "health")
        if "ok" not in r.text.lower():
            self.cquit(Status.CORRUPT, "health body", r.text[:200])

    def _check_session(self, token: str) -> None:
        r = self._req("GET", "/api/auth/check_session", token=token)
        self.check_response(r, "check_session")
        data = self.get_json(r, "check_session json")
        if not data.get("ok") or not data.get("session_valid"):
            self.cquit(Status.MUMBLE, "session not valid", str(data))

    def _fetch_rsa_public_key(self):
        r = self._req("GET", "/keys/public.key")
        self.check_response(r, "public.key")
        raw = r.content
        if len(raw) < 32:
            self.cquit(Status.CORRUPT, "public.key too short", str(len(raw)))
        try:
            return load_rsa_public_key(raw)
        except Exception as e:
            self.cquit(Status.CORRUPT, "public.key parse", str(e))

    def _verify_sso_token_signature(self, sso_token: str, pub) -> None:
        parts = sso_token.split(".")
        if len(parts) != 2:
            self.cquit(Status.CORRUPT, "sso token format", "expected exactly one dot")
        payload_b64, sig_b64 = parts[0], parts[1]
        message = f"sso-token={payload_b64}"
        if not verify_token_verfer_style(message, sig_b64, pub):
            self.cquit(Status.CORRUPT, "sso signature invalid", "local verify failed")

    def _sso_create_token(self, session_token: str) -> str:
        r = self._req("GET", "/api/sso/create-token", token=session_token)
        self.check_response(r, "sso create-token")
        data = self.get_json(r, "sso create-token json")
        if not data.get("ok"):
            self.cquit(Status.MUMBLE, "sso create-token not ok", str(data.get("error")))
        tok = data.get("token")
        if not tok:
            self.cquit(Status.CORRUPT, "sso no token", "ok but missing token breaks contract")
        return str(tok)

    def _create_checklist(self, token: str, body: dict[str, Any]) -> int:
        r = self._req("POST", "/api/user/checklists", token=token, json_body=body)
        self.check_response(r, "create checklist")
        data = self.get_json(r, "create checklist json")
        if not data.get("ok"):
            self.cquit(Status.MUMBLE, "create checklist failed", str(data.get("error")))
        cid = data.get("checklist_id")
        if not isinstance(cid, int):
            self.cquit(Status.CORRUPT, "no checklist_id", "")
        return cid

    def _get_checklist_questions(self, token: str, cid: int) -> dict[str, dict[str, Any]]:
        r = self._req("GET", "/api/checklists/get", token=token, params={"id": str(cid)})
        self.check_response(r, "get checklist")
        env = self.get_json(r, "get checklist json")
        if not env.get("ok") or not env.get("checklist"):
            self.cquit(Status.MUMBLE, "get checklist envelope", "")
        qs = env["checklist"].get("questions") or []
        return {str(q["q_name"]): q for q in qs}

    def _complete_checklist(self, token: str, cid: int, answers: list[dict[str, Any]]) -> None:
        r = self._req(
            "POST",
            "/api/checklists/complete",
            token=token,
            json_body={"checklist_id": cid, "answers": answers},
        )
        self.check_response(r, "complete checklist")
        done = self.get_json(r, "complete json")
        if not done.get("ok"):
            self.cquit(Status.MUMBLE, "complete failed", str(done.get("error")))

    def _answer_id_after_complete(self, token: str, cid: int) -> int:
        uid = _user_id_from_session_token(token)
        r = self._req("GET", "/api/checklists/export-list", token=token, params={"page": "1"})
        self.check_response(r, "export-list")
        el = self.get_json(r, "export-list json")
        if not el.get("ok"):
            self.cquit(Status.MUMBLE, "export-list not ok", "")
        for row in el.get("answers") or []:
            try:
                if int(row["checklist"]["checklist_id"]) == int(cid) and int(row["user"]["user_id"]) == int(uid):
                    return int(row["id"])
            except (KeyError, TypeError, ValueError):
                continue
        self.cquit(Status.MUMBLE, "answer row not found", f"cid={cid} uid={uid}")

    def _download_pdf_for_answer(self, token: str, answer_id: int) -> bytes:
        r = self._req("POST", "/api/checklists/print-export", token=token, json_body={"answer_id": answer_id})
        self.check_response(r, "print-export")
        pr = self.get_json(r, "print-export json")
        if not pr.get("ok") or not pr.get("path"):
            self.cquit(Status.MUMBLE, "print-export failed", str(pr.get("error")))
        pdf_path = str(pr["path"])
        if not pdf_path.startswith("/"):
            self.cquit(Status.CORRUPT, "bad pdf path", pdf_path)
        r = self._req("GET", pdf_path)
        self.check_response(r, "download pdf")
        raw = r.content
        if len(raw) < 5 or not raw.startswith(b"%PDF"):
            self.cquit(Status.CORRUPT, "invalid pdf", f"len={len(raw)}")
        return raw

    def _find_file_id(self, token: str, logical_name: str) -> int:
        r = self._req("GET", "/api/files/list", token=token)
        self.check_response(r, "files list")
        lj = self.get_json(r, "files list json")
        for it in lj.get("files") or []:
            if _norm_stored_filename(str(it.get("name") or "")) == logical_name:
                return int(it["id"])
        self.cquit(Status.MUMBLE, "file not in list", logical_name)

    def _checklist_smoke_and_pdf(self, token: str) -> None:
        (qg, tg, dg), (qn, tn, dn) = smoke_pair_labels()
        body = {
            "name": random_checklist_title(),
            "description": random_checklist_description(),
            "is_public": True,
            "is_hidden": False,
            "questions": [
                {"q_name": qg, "title": tg, "description": dg, "q_type": "bool", "q_values": None},
                {"q_name": qn, "title": tn, "description": dn, "q_type": "text", "q_values": None},
            ],
        }
        cid = self._create_checklist(token, body)
        by_name = self._get_checklist_questions(token, cid)
        marker = rnd_string(12)
        answers = [
            {"question_id": by_name[qg]["id"], "answers": ["yes"]},
            {"question_id": by_name[qn]["id"], "answers": [f"note-{marker}"]},
        ]
        self._complete_checklist(token, cid, answers)
        aid = self._answer_id_after_complete(token, cid)
        raw = self._download_pdf_for_answer(token, aid)
        if len(raw) < 5 or not raw.startswith(b"%PDF"):
            self.cquit(Status.CORRUPT, "invalid pdf smoke", f"len={len(raw)}")

    def _files_roundtrip(self, token: str) -> None:
        name = random_filename("txt")
        blob = rnd_string(32).encode()
        b64 = base64.standard_b64encode(blob).decode()
        r = self._req("POST", "/api/files/new", token=token, json_body={"filename": name, "filedata": b64})
        self.check_response(r, "files new")
        j = self.get_json(r, "files new json")
        if not j.get("ok"):
            self.cquit(Status.MUMBLE, "files new failed", str(j.get("error")))
        fid = self._find_file_id(token, name)
        r = self._req("GET", "/api/files/get", token=token, params={"id": str(fid)})
        self.check_response(r, "files get")
        gj = self.get_json(r, "files get json")
        if not gj.get("ok") or not gj.get("filedata"):
            self.cquit(Status.MUMBLE, "files get failed", str(gj.get("error")))
        got = base64.standard_b64decode(str(gj["filedata"]))
        if got != blob:
            self.cquit(Status.CORRUPT, "file bytes mismatch", "")

    def check(self) -> None:
        self._health()
        user = random_display_user()
        email = random_email()
        password = rnd_password(16)

        _ = self._auth_token_from_register(user, email, password)
        token = self._auth_token_from_login(email, password)
        self._check_session(token)
        pub = self._fetch_rsa_public_key()
        sso_token = self._sso_create_token(token)
        self._verify_sso_token_signature(sso_token, pub)
        self._checklist_smoke_and_pdf(token)
        self._files_roundtrip(token)
        self.cquit(Status.OK, "OK", "full path ok")

    def _put_v1_file(self, email: str, password: str, token: str, flag: str) -> dict[str, Any]:
        fname = random_filename("dat")
        b64 = base64.standard_b64encode(flag.encode()).decode()
        r = self._req("POST", "/api/files/new", token=token, json_body={"filename": fname, "filedata": b64})
        self.check_response(r, "put v1 files new")
        j = self.get_json(r, "put v1 json")
        if not j.get("ok"):
            self.cquit(Status.MUMBLE, "put v1 upload failed", str(j.get("error")))
        fid = self._find_file_id(token, fname)
        return {"v": 1, "email": email, "password": password, "file_id": fid}

    def _put_v2_hidden_public_question(self, email: str, password: str, token: str, flag: str) -> dict[str, Any]:
        q_slot, q_title = slot_question_labels()
        body = {
            "name": random_checklist_title(),
            "description": random_checklist_description(),
            "is_public": True,
            "is_hidden": True,
            "questions": [
                {
                    "q_name": q_slot,
                    "title": q_title,
                    "description": flag,
                    "q_type": "text",
                    "q_values": None,
                },
            ],
        }
        cid = self._create_checklist(token, body)
        return {"v": 2, "email": email, "password": password, "checklist_id": cid, "slot_q": q_slot}

    def _put_v3_public_answer(self, email: str, password: str, token: str, flag: str) -> dict[str, Any]:
        fq, ft, fd = flag_prompt_question()
        body = {
            "name": random_checklist_title(),
            "description": random_checklist_description(),
            "is_public": True,
            "is_hidden": False,
            "questions": [
                {
                    "q_name": fq,
                    "title": ft,
                    "description": fd,
                    "q_type": "text",
                    "q_values": None,
                },
            ],
        }
        cid = self._create_checklist(token, body)
        by_name = self._get_checklist_questions(token, cid)
        self._complete_checklist(
            token,
            cid,
            [{"question_id": by_name[fq]["id"], "answers": [flag]}],
        )
        aid = self._answer_id_after_complete(token, cid)
        return {"v": 3, "email": email, "password": password, "checklist_id": cid, "answer_id": aid}

    def _put_v4_private_answer(self, email: str, password: str, token: str, flag: str) -> dict[str, Any]:
        fq, ft, fd = flag_prompt_question()
        body = {
            "name": random_checklist_title(),
            "description": random_checklist_description(),
            "is_public": False,
            "is_hidden": False,
            "questions": [
                {
                    "q_name": fq,
                    "title": ft,
                    "description": fd,
                    "q_type": "text",
                    "q_values": None,
                },
            ],
        }
        cid = self._create_checklist(token, body)
        by_name = self._get_checklist_questions(token, cid)
        self._complete_checklist(
            token,
            cid,
            [{"question_id": by_name[fq]["id"], "answers": [flag]}],
        )
        aid = self._answer_id_after_complete(token, cid)
        return {"v": 4, "email": email, "password": password, "checklist_id": cid, "answer_id": aid}

    def put(self, flag_id: str, flag: str, vuln: str) -> None:
        _ = flag_id
        self._health()
        try:
            vn = _parse_vuln(vuln)
        except ValueError as e:
            self.cquit(Status.MUMBLE, "bad vuln", str(e))

        user = random_display_user()
        email = random_email()
        password = rnd_password(16)
        self._auth_token_from_register(user, email, password)
        token = self._auth_token_from_login(email, password)

        if vn == 1:
            st = self._put_v1_file(email, password, token, flag)
        elif vn == 2:
            st = self._put_v2_hidden_public_question(email, password, token, flag)
        elif vn == 3:
            st = self._put_v3_public_answer(email, password, token, flag)
        elif vn == 4:
            st = self._put_v4_private_answer(email, password, token, flag)
        else:
            self.cquit(Status.CORRUPT, "vuln", str(vn))

        out = _b64json(st)
        self.cquit(Status.OK, out, out)

    def _get_v1_file(self, st: dict[str, Any], flag: str) -> None:
        email = str(st["email"])
        password = str(st["password"])
        fid = int(st["file_id"])
        token = self._auth_token_from_login(email, password)
        r = self._req("GET", "/api/files/get", token=token, params={"id": str(fid)})
        self.check_response(r, "get v1 files")
        gj = self.get_json(r, "get v1 json")
        if not gj.get("ok") or not gj.get("filedata"):
            self.cquit(Status.CORRUPT, "missing file", str(gj.get("error")))
        got = base64.standard_b64decode(str(gj["filedata"])).decode(errors="replace")
        if got != flag:
            self.cquit(Status.CORRUPT, "flag mismatch file", "")

    def _get_v2_question_body(self, st: dict[str, Any], flag: str) -> None:
        email = str(st["email"])
        password = str(st["password"])
        cid = int(st["checklist_id"])
        token = self._auth_token_from_login(email, password)
        by_name = self._get_checklist_questions(token, cid)
        slot_q = str(st.get("slot_q") or "slot")
        q = by_name.get(slot_q)
        if not q:
            self.cquit(Status.CORRUPT, "question slot missing", slot_q)
        desc = str(q.get("description") or "")
        if flag not in desc:
            self.cquit(Status.CORRUPT, "flag not in question description", desc[:200])

    def _get_v3_or_v4_pdf(self, st: dict[str, Any], flag: str) -> None:
        email = str(st["email"])
        password = str(st["password"])
        aid = int(st["answer_id"])
        token = self._auth_token_from_login(email, password)
        raw = self._download_pdf_for_answer(token, aid)
        if not flag_visible_in_pdf_relaxed(raw, flag):
            self.cquit(Status.CORRUPT, "flag not in pdf", f"answer_id={aid}")

    def get(self, flag_id: str, flag: str, vuln: str) -> None:
        _ = vuln
        self._health()
        try:
            st = _from_b64json(flag_id)
        except Exception as e:
            self.cquit(Status.MUMBLE, "bad state", str(e))

        v = int(st.get("v", 1))
        if v == 1:
            self._get_v1_file(st, flag)
        elif v == 2:
            self._get_v2_question_body(st, flag)
        elif v == 3:
            self._get_v3_or_v4_pdf(st, flag)
        elif v == 4:
            self._get_v3_or_v4_pdf(st, flag)
        else:
            self.cquit(Status.MUMBLE, "unknown v in state", str(v))

        self.cquit(Status.OK, "OK", "flag ok")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("usage: checker.py <action> <host> [args...]", file=sys.stderr)
        sys.exit(110)

    chk = CheckDChecker(sys.argv[2])
    try:
        chk.action(sys.argv[1], *sys.argv[3:])
    except CheckFinished:
        cquit(Status(chk.status), chk.public, chk.private)
