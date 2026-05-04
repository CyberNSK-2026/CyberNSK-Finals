from __future__ import annotations

import hmac
import re
import unicodedata
from urllib.parse import urljoin, urlparse



class WebhookConfigError(ValueError):
    pass

def validate_webhook_base(raw: str) -> str:
    if not raw or not isinstance(raw, str):
        raise WebhookConfigError("Base URL is required")
    stripped = raw.strip()
    if len(stripped) > 512:
        raise WebhookConfigError("Base URL too long")

    parsed = urlparse(stripped)
    if parsed.scheme not in ("http", "https"):
        if "://" not in stripped:
            raise WebhookConfigError("Base URL must start with http:// or https://")
        raise WebhookConfigError("Unsupported scheme for base URL")
    if not parsed.hostname:
        raise WebhookConfigError("Base URL must include a host")
    if parsed.username or parsed.password:
        raise WebhookConfigError("Credentials are not allowed in base URL")

    return stripped


def validate_endpoint_path(raw: str) -> str:
    if raw is None:
        return ""
    if not isinstance(raw, str):
        raise WebhookConfigError("Endpoint path must be a string")
    path = raw.strip()
    if len(path) > 1024:
        raise WebhookConfigError("Endpoint path too long")
    lowered = path.lower()
    if lowered.startswith("http://") or lowered.startswith("https://"):
        raise WebhookConfigError("Endpoint path must be relative")
    return path


def resolve_webhook_target(base: str, path: str) -> str:
    return urljoin(base, path)


def normalise_filename_fragment(fragment: str) -> str:
    if fragment is None:
        return "attachment.bin"
    normalised = unicodedata.normalize("NFC", fragment)
    safe = re.compile(r"[^A-Za-z0-9._-]+").sub("_", normalised).strip("._")
    return safe or "attachment.bin"


def constant_time_equal(a: str, b: str) -> bool:
    if a is None or b is None:
        return False
    return hmac.compare_digest(a.encode("utf-8"), b.encode("utf-8"))
