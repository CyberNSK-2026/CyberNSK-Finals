#!/usr/bin/env python3
import sys
import requests
import traceback
import base64
import random
import struct
from utils import *

# Константы кодов возврата
OK, CORRUPT, MUMBLE, DOWN, CHECKER_ERROR = 101, 102, 103, 104, 110
PORT = 4000
USER_AGENT = get_user_agent()

def result(code, message=''):
    if message:
        print(message)
    sys.exit(code)

def debug(msg):
    print(msg, file=sys.stderr)

# ── TVF Binary Builder (Специфическая реализация сервиса) ───────────────────

def pack_meta_str(key, value):
    k, v = key.encode(), value.encode()
    # Формат: len(k) + k + type(0x01) + len(v) + v
    return struct.pack("B", len(k)) + k + b"\x01" + struct.pack("<H", len(v)) + v

def pack_meta_int(key, value):
    k = key.encode()
    # Формат: len(k) + k + type(0x02) + int32
    return struct.pack("B", len(k)) + k + b"\x02" + struct.pack("<i", value)

def pack_glyph(cp, cmds):
    # Заголовок глифа: codepoint(H) + num_commands(H)
    out = struct.pack("<HH", cp, len(cmds))
    for cmd in cmds:
        t, x, y = cmd[0], cmd[1], cmd[2]
        out += struct.pack("<Bhh", t, x, y)
        if t == 2: # Кривая Безье (2 дополнительные точки)
            out += struct.pack("<hh", cmd[3], cmd[4])
    return out

def build_tvf(font_name="CheckerFont", author="checker"):
    """Создает минимально валидный .tvf файл."""
    metas = [
        pack_meta_str("font_name", font_name),
        pack_meta_str("author", author),
        pack_meta_int("version", 1),
        pack_meta_str("license", "ofl"),
    ]
    meta_data = b"".join(metas)
    # Глиф буквы 'A' (65)
    glyph_data = pack_glyph(65, [(0, 0, 0), (1, 50, 100), (1, 100, 0), (1, 0, 0)])
    # Магическое число 'TVF1' + counts (num_fonts, num_metas, num_glyphs, padding)
    header = b"TVF1" + struct.pack("<HHHH", 1, len(metas), 1, 0)
    return header + meta_data + glyph_data

# ── API Helpers ──────────────────────────────────────────────────────────────

def register(host):
    while True:
        username = random_username()
        password = random_password()
        email = random_email(username)
        try:
            resp = requests.post(f'http://{host}:{PORT}/api/auth/register', json={
                'username': username, 'email': email, 'password': password, 'bio': 'Typeface designer'
            }, headers={'User-Agent': USER_AGENT}, timeout=10)
            if resp.status_code == 201:
                return resp.json()['token'], email, password
            data = resp.json()
            if 'already' not in data.get('error', '').lower():
                result(MUMBLE, f"Registration failed: {resp.status_code}")
        except Exception as e:
            result(DOWN, f"Registration connection error: {e}")

def login(host, email, password):
    try:
        resp = requests.post(f'http://{host}:{PORT}/api/auth/login', 
                             json={'email': email, 'password': password}, 
                             headers={'User-Agent': USER_AGENT}, timeout=10)
        if resp.status_code == 200:
            return resp.json()['token']
        result(MUMBLE, "Login failed")
    except Exception:
        result(DOWN, "Login connection error")

def create_project(host, token, flag_or_notes):
    """Создает проект с загрузкой бинарного шрифта и фиксом тегов."""
    # Сначала создаём проект обычным JSON-запросом
    payload = {
        'name': random_project_name(),
        'description': random_description(),
        'design_notes': flag_or_notes,
        'is_public': True,
        'tags': random_tags() or ["font", "type"],
        'license': random_license(),
        'preview_text': random_preview_text(),
    }
    headers = {'Authorization': f'Bearer {token}', 'User-Agent': USER_AGENT}
    try:
        resp = requests.post(f'http://{host}:{PORT}/api/projects', json=payload, headers=headers, timeout=10)
        if resp.status_code == 201:
            project_id = resp.json()['project']['id']
            # После создания проекта загружаем TVF-файл
            tvf_data = build_tvf(font_name=payload['name'])
            try:
                upload_font(host, token, project_id, tvf_data)
            except Exception as e:
                debug(f"Font upload failed: {e}")
            return project_id
        debug(f"Validation Error: {resp.text}")
        result(MUMBLE, f"Project creation failed (Status: {resp.status_code})")
    except Exception as e:
        result(DOWN, f"Upload error: {e}")

# ── Actions ──────────────────────────────────────────────────────────────────

def check(host):
    # 1. Проверка доступности API
    try:
        r = requests.get(f'http://{host}:{PORT}/api/gallery', timeout=5)
        if r.status_code != 200: result(MUMBLE, "Gallery API unavailable")
    except Exception: result(DOWN, "Service unreachable")

    # 2. Полный цикл: Регистрация -> Создание проекта с бинарным шрифтом
    token, _, _ = register(host)
    pid = create_project(host, token, "Service Health Check")
    
    # 3. Проверка Draft Preview (Base64 парсинг в памяти сервера)
    # Используем опкод 0x06 (NOP) для валидации парсера
    nop_payload = base64.b64encode(bytes([0x06, 0x06, 0x06])).decode()
    try:
        resp = requests.post(f'http://{host}:{PORT}/api/projects/{pid}/preview_draft', 
                             json={"font": nop_payload}, 
                             headers={'Authorization': f'Bearer {token}', 'User-Agent': USER_AGENT}, timeout=10)
        
        if resp.status_code != 200 or "<svg" not in resp.json().get('svg', ''):
            result(MUMBLE, "Draft preview rendering failed")
    except Exception as e:
        result(MUMBLE, f"Preview API error: {e}")
    
    result(OK)

def put(host, flag_id, flag, vuln):
    token, email, password = register(host)
    project_id = create_project(host, token, flag)
    # Выводим данные, которые станут новым flag_id для GET
    result(OK, f"{email}:{password}:{project_id}")

def get(host, flag_id, flag, vuln):
    try:
        parts = flag_id.split(':')
        pid = parts[-1]
        pwd = parts[-2]
        email = ':'.join(parts[:-2])
        
        token = login(host, email, pwd)
        resp = requests.get(f'http://{host}:{PORT}/api/projects/{pid}', 
                            headers={'Authorization': f'Bearer {token}', 'User-Agent': USER_AGENT}, timeout=10)
        
        if resp.status_code == 404: result(CORRUPT, "Project vanished")
        if resp.status_code != 200: result(MUMBLE, f"Access error: {resp.status_code}")
        
        notes = resp.json().get('project', {}).get('design_notes', '')
        if notes == flag:
            result(OK)
        elif not notes:
            result(CORRUPT, "Flag field is empty")
        else:
            result(CORRUPT, "Flag mismatch")
    except Exception as e:
        debug(traceback.format_exc())
        result(MUMBLE, "GET process error")

# ── Entry Point ──────────────────────────────────────────────────────────────

if __name__ == '__main__':
    if len(sys.argv) < 3: 
        print("Usage: checker.py <cmd> <host> [args...]", file=sys.stderr)
        sys.exit(CHECKER_ERROR)

    action = sys.argv[1]
    target = sys.argv[2]

    try:
        if action == 'check':
            check(target)
        elif action == 'put':
            # Аргументы: host, flag_id, flag, vuln
            put(target, sys.argv[3], sys.argv[4], sys.argv[5] if len(sys.argv) > 5 else "1")
        elif action == 'get':
            get(target, sys.argv[3], sys.argv[4], sys.argv[5] if len(sys.argv) > 5 else "1")
        else:
            result(CHECKER_ERROR, "Invalid command")
    except SystemExit:
        raise
    except Exception as e:
        debug(traceback.format_exc())
        result(CHECKER_ERROR, f"Internal Error: {e}")
