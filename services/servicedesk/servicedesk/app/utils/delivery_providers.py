from __future__ import annotations

from dataclasses import dataclass
from urllib.parse import urlparse

from config import settings
from utils.security import resolve_webhook_target


@dataclass(frozen=True)
class DeliveryProvider:
    key: str
    label: str
    summary: str
    target_setting: str | None = None


PROVIDERS: dict[str, DeliveryProvider] = {
    "discord": DeliveryProvider(
        key="discord",
        label="Discord",
        summary="Discord-style embed notifications",
        target_setting="discord_webhook_url",
    ),
    "slack": DeliveryProvider(
        key="slack",
        label="Slack",
        summary="Slack blocks notifications",
        target_setting="slack_webhook_url",
    ),
    "teams": DeliveryProvider(
        key="teams",
        label="Microsoft Teams",
        summary="Teams MessageCard notifications",
        target_setting="teams_webhook_url",
    ),
    "generic_webhook": DeliveryProvider(
        key="generic_webhook",
        label="Generic Webhook",
        summary="Generic JSON event delivery",
        target_setting="generic_webhook_url",
    ),
}


DEFAULT_PROVIDER = "discord"
FALLBACK_PROVIDER = "generic_webhook"


def normalise_provider(raw: str | None, *, default: str = DEFAULT_PROVIDER) -> str:
    value = (raw or "").strip().lower()
    if not value:
        return default
    if value not in PROVIDERS:
        raise ValueError("Unsupported delivery provider")
    return value


def provider_label(provider: str | None) -> str:
    key = normalise_provider(provider, default=FALLBACK_PROVIDER)
    return PROVIDERS[key].label


def provider_summary(provider: str | None) -> str:
    key = normalise_provider(provider, default=FALLBACK_PROVIDER)
    return PROVIDERS[key].summary


def provider_default_target(provider: str | None) -> str:
    key = normalise_provider(provider, default=DEFAULT_PROVIDER)
    target_setting = PROVIDERS[key].target_setting
    target = (getattr(settings, target_setting, None) or "").strip() if target_setting else ""
    if not target:
        raise ValueError("Notification system is not configured")

    parsed = urlparse(target)
    if not parsed.scheme or not parsed.hostname:
        raise ValueError("Notification system target is invalid")
    return target


def infer_provider_from_target(base_url: str | None, endpoint_path: str | None) -> str:
    parsed = urlparse((base_url or "").strip())
    host = (parsed.hostname or "").lower()
    path = f"{parsed.path or ''}{endpoint_path or ''}".lower()

    if "discord" in host or "/discord" in path:
        return "discord"
    if "slack" in host or "/slack" in path:
        return "slack"
    if "office.com" in host or "teams" in host or "/teams" in path:
        return "teams"
    return FALLBACK_PROVIDER


def integration_provider(integration) -> str:
    raw = getattr(integration, "provider", None)
    if raw:
        try:
            return normalise_provider(raw, default=FALLBACK_PROVIDER)
        except ValueError:
            pass
    return infer_provider_from_target(
        getattr(integration, "base_url", None),
        getattr(integration, "endpoint_path", None),
    )


def has_custom_target(base_url: str | None, endpoint_path: str | None) -> bool:
    return bool((base_url or "").strip() or (endpoint_path or "").strip())


def resolve_integration_target(provider: str | None, base_url: str | None, endpoint_path: str | None) -> str:
    current_base = (base_url or "").strip()
    current_path = (endpoint_path or "").strip()
    if has_custom_target(current_base, current_path):
        if not current_base:
            raise ValueError("Custom notification target is invalid")
        return resolve_webhook_target(current_base, current_path)
    return provider_default_target(provider)
