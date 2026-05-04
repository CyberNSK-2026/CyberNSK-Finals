import secrets
import time

DISPATCH_TOKEN_HEADER = "X-ServiceDesk-Dispatch-Token"
SIGNATURE_HEADER = "X-ServiceDesk-Signature"

_current_minute: int | None = None
_current_token: str | None = None


def get_dispatch_token() -> str:
    global _current_minute, _current_token

    minute = int(time.time() // 60)
    if _current_minute != minute or not _current_token:
        _current_minute = minute
        _current_token = secrets.token_urlsafe(18)
    return _current_token
