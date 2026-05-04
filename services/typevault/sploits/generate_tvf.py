#!/usr/bin/env python3
"""
TVF (TypeVault Font) binary file generator.

Format:
  [4]  magic "TVF1"
  [2]  version        u16 LE
  [2]  meta_count     u16 LE
  [2]  glyph_count    u16 LE
  [2]  reserved       u16 LE (0)

  For each metadata entry:
    [1]  key_len        u8
    [*]  key            UTF-8
    [1]  val_type       0x01=String, 0x02=Int
    If String:  [2] val_len u16 LE + [*] val UTF-8
    If Int:     [4] value   i32 LE

  For each glyph:
    [2]  codepoint      u16 LE
    [2]  num_cmds       u16 LE
    For each cmd:
      [1]  cmd_type     0=MoveTo 1=LineTo 2=CurveTo
      [2]  x            i16 LE
      [2]  y            i16 LE
      If CurveTo: [2] cx i16 LE + [2] cy i16 LE
"""

import struct
import sys
import os


def pack_meta_str(key: str, value: str) -> bytes:
    k = key.encode()
    v = value.encode()
    return struct.pack("B", len(k)) + k + struct.pack("B", 0x01) + struct.pack("<H", len(v)) + v


def pack_meta_int(key: str, value: int) -> bytes:
    k = key.encode()
    return struct.pack("B", len(k)) + k + struct.pack("B", 0x02) + struct.pack("<i", value)


def pack_glyph(codepoint: int, cmds: list) -> bytes:
    out = struct.pack("<HH", codepoint, len(cmds))
    for cmd in cmds:
        t = cmd[0]
        x, y = cmd[1], cmd[2]
        out += struct.pack("<Bhh", t, x, y)
        if t == 2:  # CurveTo — extra cx, cy
            out += struct.pack("<hh", cmd[3], cmd[4])
    return out


def build_tvf(font_name: str, author: str, version: int = 1,
              license_: str = "ofl",
              callback_url: str = None,
              glyphs: list = None) -> bytes:
    """Build a minimal valid TVF binary."""

    meta_entries = []
    meta_entries.append(pack_meta_str("font_name", font_name))
    meta_entries.append(pack_meta_str("author", author))
    meta_entries.append(pack_meta_int("version", version))
    meta_entries.append(pack_meta_str("license", license_))
    if callback_url:
        meta_entries.append(pack_meta_str("preview_callback_url", callback_url))

    meta_data = b"".join(meta_entries)
    meta_count = len(meta_entries)

    glyph_data = b""
    if glyphs is None:
        # Default: simple glyph for 'A' (codepoint 65) with a triangle
        glyphs = [
            (65, [        # 'A'
                (0, 0,   0),    # MoveTo  (0, 0)
                (1, 50,  100),  # LineTo  (50, 100)
                (1, 100, 0),    # LineTo  (100, 0)
                (1, 80,  0),    # LineTo  (80, 0)
                (1, 50,  60),   # LineTo  (50, 60)
                (1, 20,  0),    # LineTo  (20, 0)
                (1, 0,   0),    # LineTo  (0, 0)
            ]),
            (66, [        # 'B'
                (0, 0,   0),
                (1, 0,   100),
                (1, 60,  100),
                (2, 90,  100, 90, 75),  # CurveTo
                (2, 90,  50,  60, 50),
                (2, 90,  25,  90, 0),
                (1, 0,   0),
            ]),
            (67, [        # 'C'
                (0, 90,  80),
                (2, 50,  100, 0,  100),  # CurveTo
                (2, 0,   50,  0,  0),
                (2, 50,  0,   90, 20),
            ]),
        ]

    glyph_count = 0
    for glyph in glyphs:
        codepoint, cmds = glyph
        glyph_data += pack_glyph(codepoint, cmds)
        glyph_count += 1

    header = b"TVF1"
    header += struct.pack("<HHHH", version, meta_count, glyph_count, 0)

    return header + meta_data + glyph_data


def main():
    os.makedirs("sample_fonts", exist_ok=True)

    # 1. Simple font — no callback
    data = build_tvf(
        font_name="Grotesk Display",
        author="TypeVault Demo",
        version=1,
        license_="ofl",
    )
    path = "sample_fonts/grotesk_display.tvf"
    with open(path, "wb") as f:
        f.write(data)
    print(f"[+] {path}  ({len(data)} bytes)")

    # 2. Font with preview callback (for testing VULN-3 SSRF)
    data2 = build_tvf(
        font_name="Serif Nova",
        author="CTF Tester",
        version=2,
        license_="apache",
        callback_url="https://example.com/hook",
    )
    path2 = "sample_fonts/serif_nova.tvf"
    with open(path2, "wb") as f:
        f.write(data2)
    print(f"[+] {path2}  ({len(data2)} bytes)")

    # 3. Larger font — full Latin alphabet A-Z
    latin_glyphs = []
    for i, cp in enumerate(range(65, 91)):  # A-Z
        size = 80
        cmds = [
            (0, 0, 0),
            (1, size // 2, size),
            (1, size, 0),
            (1, int(size * 0.8), 0),
            (1, size // 2, int(size * 0.6)),
            (1, int(size * 0.2), 0),
            (1, 0, 0),
        ]
        latin_glyphs.append((cp, cmds))

    data3 = build_tvf(
        font_name="Latin Mono",
        author="TypeVault Demo",
        version=1,
        license_="ofl",
        glyphs=latin_glyphs,
    )
    path3 = "sample_fonts/latin_mono.tvf"
    with open(path3, "wb") as f:
        f.write(data3)
    print(f"[+] {path3}  ({len(data3)} bytes)")

    print("\nDone! Upload via:")
    print("  curl -X POST http://localhost:4000/api/projects/<id>/fonts \\")
    print("       -H 'Authorization: Bearer <token>' \\")
    print("       -F 'file=@sample_fonts/grotesk_display.tvf'")


if __name__ == "__main__":
    main()
