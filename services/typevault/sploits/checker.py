import base64
import json
import os
import re
import random
import string
import struct
import sys

import requests

HOST  = sys.argv[1] if len(sys.argv) > 1 else "localhost"
COUNT = int(sys.argv[2]) if len(sys.argv) > 2 else 20
PORT  = 4000
BASE  = f"http://{HOST}:{PORT}"
OUT   = os.path.join(os.path.dirname(__file__), "victims.json")

FLAG_PREFIX = "CTF{"
FLAG_SUFFIX = "}"

# Minimal valid TVF: "TVF1" magic + header + 4 meta fields + 1 glyph (codepoint A)
def rand_str(n=10):
    return "".join(random.choices(string.ascii_lowercase + string.digits, k=n))

def gen_flag():
    body = "".join(random.choices(string.ascii_uppercase + string.digits, k=20))
    return f"{FLAG_PREFIX}{body}{FLAG_SUFFIX}"

def api(method, path, data=None, token=None, files=None):
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    url = f"{BASE}{path}"
    try:
        if method == "POST":
            if files:
                r = requests.post(url, headers=headers, files=files, timeout=15)
            else:
                headers["Content-Type"] = "application/json"
                r = requests.post(url, headers=headers, json=data, timeout=15)
        elif method == "GET":
            r = requests.get(url, headers=headers, timeout=15)
        ct = r.headers.get("content-type", "")
        return r.status_code, r.json() if "json" in ct else r.text
    except Exception as e:
        return 0, str(e)

def pack_meta_str(key, value):
    k, v = key.encode(), value.encode()
    return struct.pack("B", len(k)) + k + b"\x01" + struct.pack("<H", len(v)) + v

def pack_meta_int(key, value):
    k = key.encode()
    return struct.pack("B", len(k)) + k + b"\x02" + struct.pack("<i", value)

def pack_glyph(cp, cmds):
    out = struct.pack("<HH", cp, len(cmds))
    for cmd in cmds:
        t, x, y = cmd[0], cmd[1], cmd[2]
        out += struct.pack("<Bhh", t, x, y)
        if t == 2:
            out += struct.pack("<hh", cmd[3], cmd[4])
    return out

def build_tvf(font_name="CheckerFont", author="checker"):
    """Build a minimal valid .tvf binary with one glyph (codepoint 65 = 'A')."""
    metas = [
        pack_meta_str("font_name", font_name),
        pack_meta_str("author", author),
        pack_meta_int("version", 1),
        pack_meta_str("license", "ofl"),
    ]
    meta_data  = b"".join(metas)
    glyph_data = pack_glyph(65, [(0, 0, 0), (1, 50, 100), (1, 100, 0), (1, 0, 0)])
    header     = b"TVF1" + struct.pack("<HHHH", 1, len(metas), 1, 0)
    return header + meta_data + glyph_data

# ---------------------------------------------------------------------------
# Render-preview checks
# ---------------------------------------------------------------------------

def check_api_render_preview(token, project_id, font_id):
    """
    API path: POST /api/projects/:pid/fonts/:fid/preview
    Expects JSON {svg: "<svg…>", font_name: "…", callback_status: "…"}
    Returns (ok: bool, http_status: int, detail: str)
    """
    s, r = api("POST", f"/api/projects/{project_id}/fonts/{font_id}/preview",
               {"text": "CheckABC", "size": 48}, token=token)
    if s != 200 or not isinstance(r, dict):
        return False, s, str(r)[:120]
    svg = r.get("svg", "")
    if not svg or "<svg" not in svg:
        return False, s, f"svg missing or invalid (got {repr(svg[:80])})"
    return True, s, f"svg {len(svg)}b  font_name={r.get('font_name')!r}"


def check_web_render_preview(token, project_id):
    """
    Web path: the "Draft Preview" tab calls
    POST /api/projects/:pid/preview_draft  with a Bearer token via fetch().
    We reproduce exactly that request here.

    TVFValidator grammar (from tvf_validator.ex):
      0x01 -> 4 bytes args
      0x02 -> 8 bytes args
      0x03 -> 4 bytes args
      0x05 -> 1 byte  arg
      0x06 -> 0 bytes (pure no-op)
      0xFE -> 2 bytes args
      0x04 <len16-le> <len ^ 0xCAFE bytes>
    Anything else -> false (rejected).

    Payload: three 0x06 opcodes — each passes the validator and the FSM
    produces the SVG envelope even with no inner content.
    Expects JSON {svg: "<svg…>"}
    Returns (ok: bool, http_status: int, detail: str)
    """
    # 0x06: validator skip_args(0x06, rest) = {:ok, rest}  — zero args
    nop_payload = base64.b64encode(bytes([0x06, 0x06, 0x06])).decode()
    s, r = api("POST", f"/api/projects/{project_id}/preview_draft",
               {"font": nop_payload}, token=token)
    if s != 200 or not isinstance(r, dict):
        return False, s, str(r)[:120]
    svg = r.get("svg", "")
    if not svg or "<svg" not in svg:
        return False, s, f"svg missing or invalid (got {repr(svg[:80])})"
    return True, s, f"svg {len(svg)}b"


def check_web_font_download(font_id):
    """
    Web browser path: GET /fonts/:id/download
    This is served by FontController under the :browser pipeline (no JSON auth needed
    for public projects).  Verifies the raw .tvf bytes are served back correctly.
    Returns (ok: bool, http_status: int, detail: str)
    """
    try:
        r = requests.get(f"{BASE}/fonts/{font_id}/download", timeout=15,
                         allow_redirects=True)
    except Exception as e:
        return False, 0, str(e)

    if r.status_code != 200:
        return False, r.status_code, r.text[:80]

    # Verify TVF magic in the downloaded bytes
    if not r.content.startswith(b"TVF1"):
        return False, r.status_code, f"bad magic: {r.content[:8].hex()}"

    return True, r.status_code, f"{len(r.content)} bytes  content-type={r.headers.get('content-type')!r}"

# ---------------------------------------------------------------------------
# Victim placement
# ---------------------------------------------------------------------------

def place_flag(index):
    suffix   = rand_str(8)
    username = f"victim{index:02d}_{suffix}"
    email    = f"{username}@ctf.local"
    password = "V1ctimP@ss!"
    flag     = gen_flag()

    # 1. Register
    s, r = api("POST", "/api/auth/register", {
        "username": username,
        "email":    email,
        "password": password,
        "bio":      f"CTF victim #{index}",
    })
    if s != 201:
        print(f"  [!] #{index:02d} register failed ({s}): {r}")
        return None
    token = r["token"]

    # 2. Create project (flag stored in design_notes)
    project_name = f"SecretVault_{rand_str(6)}"
    s, r = api("POST", "/api/projects", {
        "name":         project_name,
        "description":  "Private font archive",
        "design_notes": flag,
        "is_public":    True,
        "tags":         ["ctf", f"team{index}"],
        "license":      "ofl",
        "preview_text": "ABCDEF",
    }, token=token)
    if s != 201:
        print(f"  [!] #{index:02d} project create failed ({s}): {r}")
        return None
    project_id = r["project"]["id"]

    # 3. Upload .tvf file (mandatory)
    tvf = build_tvf(f"Font_{index:02d}", username)
    s, r = api("POST", f"/api/projects/{project_id}/fonts", token=token,
               files={"font": (f"font{index:02d}.tvf", tvf, "application/octet-stream")})
    if s != 201:
        print(f"  [!] #{index:02d} font upload failed ({s}): {r}")
        return None
    font_id = r["font"]["id"]

    # 4. Check API render preview
    ok_api, st_api, det_api = check_api_render_preview(token, project_id, font_id)
    if not ok_api:
        print(f"  [!] #{index:02d} API render preview FAILED ({st_api}): {det_api}")
        return None

    # 5. Check web render preview (preview_draft endpoint — same flow as web UI)
    ok_web, st_web, det_web = check_web_render_preview(token, project_id)
    if not ok_web:
        print(f"  [!] #{index:02d} web render preview FAILED ({st_web}): {det_web}")
        return None

    # 6. Check web font download (browser route, no Bearer needed for public projects)
    ok_dl, st_dl, det_dl = check_web_font_download(font_id)
    if not ok_dl:
        print(f"  [!] #{index:02d} web font download FAILED ({st_dl}): {det_dl}")
        return None

    print(
        f"  [+] #{index:02d}  {username:30s}  project={project_id[:8]}  flag={flag}\n"
        f"       api_preview={st_api} ok  "
        f"web_preview={st_web} ok  "
        f"download={st_dl} ok ({det_dl})"
    )

    return {
        "index":        index,
        "username":     username,
        "email":        email,
        "password":     password,
        "token":        token,
        "project_id":   project_id,
        "project_name": project_name,
        "font_id":      font_id,
        "flag":         flag,
    }

# ---------------------------------------------------------------------------

def main():
    print(f"TypeVault Checker -- placing {COUNT} flags on {BASE}")
    print("=" * 64)

    victims = []
    for i in range(1, COUNT + 1):
        v = place_flag(i)
        if v:
            victims.append(v)

    with open(OUT, "w") as f:
        json.dump(victims, f, indent=2)

    ok = len(victims)
    print(f"\n{'=' * 64}")
    print(f"  Placed {ok}/{COUNT} flags  ->  {OUT}")
    if ok < COUNT:
        sys.exit(1)

if __name__ == "__main__":
    main()
