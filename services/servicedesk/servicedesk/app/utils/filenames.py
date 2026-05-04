from __future__ import annotations

import re


_LEADING_DOT_SLASH = re.compile(r"^\.[\\/]")
_LEADING_PARENT = re.compile(r"^\.\.[\\/]")
_CONTROL_CHARS = re.compile(r"[\x00-\x1f]")


class FilenameRejected(ValueError):
    pass


def _strip_leading_dot_segments(raw: str) -> str:
    candidate = raw
    match = _LEADING_DOT_SLASH.match(candidate)
    if match:
        candidate = candidate[match.end():]
    match = _LEADING_PARENT.match(candidate)
    if match:
        candidate = candidate[match.end():]
    return candidate


def normalise_export_name(raw: str) -> str:
    if not raw:
        raise FilenameRejected("Filename is required")
    if _CONTROL_CHARS.search(raw):
        raise FilenameRejected("Invalid characters in filename")
    candidate = raw.strip()
    if candidate.startswith(("/", "\\")):
        raise FilenameRejected("Absolute paths are not allowed")
    candidate = _strip_leading_dot_segments(candidate)
    if not candidate:
        raise FilenameRejected("Filename is required")
    return candidate
