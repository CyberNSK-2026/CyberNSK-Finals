from typing import Any, Optional
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException
from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel, ValidationError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models import Integration, Ticket, User
from utils.auth import get_current_user, has_support_access
from utils.delivery_providers import (
    DEFAULT_PROVIDER,
    has_custom_target,
    integration_provider,
    normalise_provider,
    provider_label,
    provider_default_target,
    provider_summary,
)
from utils.ticket_events import build_test_payload, deliver_integration_payload
from utils.security import (
    WebhookConfigError,
    validate_endpoint_path,
    validate_webhook_base,
)

router = APIRouter(prefix="/api/integrations", tags=["integrations"])


def _decompose_webhook_url(url: str) -> tuple[str, str]:
    stripped = url.strip()
    if not stripped:
        return "", ""

    parsed = urlparse(stripped)
    if not parsed.scheme or not parsed.hostname:
        return stripped, ""
    base = f"{parsed.scheme}://{parsed.netloc}"
    path = parsed.path or ""
    if parsed.query:
        path = f"{path}?{parsed.query}"
    return base, path


def _absorb_legacy_webhook(values: dict) -> dict:
    legacy = values.pop("webhook_url", None)
    if legacy is None:
        return values
    base, path = _decompose_webhook_url(str(legacy))
    values["_hidden_base_url"] = base
    values["_hidden_endpoint_path"] = path
    values["_hidden_webhook_override"] = True
    return values


class IntegrationCreate(BaseModel):
    name: str
    provider: Optional[str] = None
    signing_token: Optional[str] = None
    ticket_id: Optional[str] = None
    is_active: Optional[bool] = True

    model_config = {"extra": "ignore"}


class IntegrationUpdate(BaseModel):
    name: Optional[str] = None
    provider: Optional[str] = None
    signing_token: Optional[str] = None
    is_active: Optional[bool] = None
    ticket_id: Optional[str] = None

    model_config = {"extra": "ignore"}


async def _get_ticket_scope(
    ticket_id: Optional[str],
    current_user: User,
    db: AsyncSession,
    require_ticket: bool,
) -> Ticket | None:
    if not ticket_id:
        if require_ticket:
            raise HTTPException(400, "ticket_id is required for customer ticket subscriptions")
        return None

    result = await db.execute(select(Ticket).where(Ticket.id == ticket_id))
    ticket = result.scalar_one_or_none()
    if not ticket:
        raise HTTPException(404, "Ticket not found")

    if not has_support_access(current_user) and ticket.customer_id != current_user.id:
        raise HTTPException(403, "Forbidden")
    return ticket


async def _get_integration_with_access(
    integration_id: str,
    current_user: User,
    db: AsyncSession,
) -> Integration:
    result = await db.execute(select(Integration).where(Integration.id == integration_id))
    integration = result.scalar_one_or_none()
    if not integration:
        raise HTTPException(404, "Integration not found")
    if integration.owner_id != current_user.id and not has_support_access(current_user):
        raise HTTPException(403, "Forbidden")
    return integration


def _view(integration: Integration) -> dict[str, Any]:
    provider = integration_provider(integration)
    return {
        "id": integration.id,
        "name": integration.name,
        "provider": provider,
        "provider_label": provider_label(provider),
        "provider_summary": provider_summary(provider),
        "is_active": integration.is_active,
        "ticket_id": integration.ticket_id,
        "scope": "workspace" if integration.ticket_id is None else "ticket",
    }


def _apply_base(raw: Optional[str]) -> str:
    if raw is None:
        raise HTTPException(400, "Invalid base URL: Base URL is required")
    try:
        return validate_webhook_base(raw)
    except WebhookConfigError as exc:
        raise HTTPException(400, f"Invalid base URL: {exc}")


def _apply_path(raw: Optional[str]) -> str:
    if raw is None:
        return ""
    try:
        return validate_endpoint_path(raw)
    except WebhookConfigError as exc:
        raise HTTPException(400, f"Invalid endpoint path: {exc}")


def _resolve_provider(raw: Optional[str], *, default: str) -> str:
    if raw is not None:
        try:
            return normalise_provider(raw, default=default)
        except ValueError as exc:
            raise HTTPException(400, str(exc))
    return default


def _validated_payload(model_cls, body: dict[str, Any]):
    try:
        return model_cls.model_validate(body)
    except ValidationError as exc:
        raise RequestValidationError(exc.errors()) from exc


def _hidden_target(values: dict[str, Any]) -> tuple[Optional[str], Optional[str], bool]:
    payload = dict(values)
    payload = _absorb_legacy_webhook(payload)
    return (
        payload.pop("_hidden_base_url", None),
        payload.pop("_hidden_endpoint_path", None),
        bool(payload.pop("_hidden_webhook_override", False)),
    )


def _resolve_target_for_storage(
    *,
    provider: str,
    hidden_base_url: Optional[str],
    hidden_endpoint_path: Optional[str],
    explicit_target: bool,
) -> tuple[str, str]:
    if explicit_target:
        if not hidden_base_url and not hidden_endpoint_path:
            try:
                provider_default_target(provider)
            except ValueError as exc:
                raise HTTPException(400, str(exc))
            return "", ""
        return _apply_base(hidden_base_url), _apply_path(hidden_endpoint_path)

    try:
        provider_default_target(provider)
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    return "", ""


@router.post("")
async def create_integration(
    body: dict[str, Any],
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    hidden_base_url, hidden_endpoint_path, explicit_target = _hidden_target(body)
    payload = _validated_payload(IntegrationCreate, body)
    provider = _resolve_provider(
        payload.provider,
        default=DEFAULT_PROVIDER,
    )
    base_url, endpoint_path = _resolve_target_for_storage(
        provider=provider,
        hidden_base_url=hidden_base_url,
        hidden_endpoint_path=hidden_endpoint_path,
        explicit_target=explicit_target,
    )

    support_access = has_support_access(current_user)
    ticket = await _get_ticket_scope(
        payload.ticket_id,
        current_user,
        db,
        require_ticket=not support_access,
    )
    integration = Integration(
        name=payload.name,
        provider=provider,
        base_url=base_url,
        endpoint_path=endpoint_path,
        signing_token=payload.signing_token,
        owner_id=current_user.id,
        ticket_id=ticket.id if ticket else None,
        is_active=payload.is_active if payload.is_active is not None else True,
    )
    db.add(integration)
    await db.commit()
    await db.refresh(integration)
    return _view(integration)


@router.get("")
async def list_integrations(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Integration).where(Integration.owner_id == current_user.id)
    )
    integrations = result.scalars().all()
    return [_view(i) for i in integrations]


@router.patch("/{integration_id}")
async def update_integration(
    integration_id: str,
    body: dict[str, Any],
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    support_access = has_support_access(current_user)
    integration = await _get_integration_with_access(integration_id, current_user, db)

    hidden_base_url, hidden_endpoint_path, explicit_target = _hidden_target(body)
    payload = _validated_payload(IntegrationUpdate, body)
    data = payload.model_dump(exclude_none=True)
    current_provider = integration_provider(integration)
    next_provider = _resolve_provider(
        payload.provider,
        default=current_provider,
    )

    if explicit_target:
        data["base_url"], data["endpoint_path"] = _resolve_target_for_storage(
            provider=next_provider,
            hidden_base_url=hidden_base_url,
            hidden_endpoint_path=hidden_endpoint_path,
            explicit_target=True,
        )
    elif payload.provider is not None and not has_custom_target(integration.base_url, integration.endpoint_path):
        try:
            provider_default_target(next_provider)
        except ValueError as exc:
            raise HTTPException(400, str(exc))
        data["base_url"] = ""
        data["endpoint_path"] = ""

    if payload.provider is not None:
        data["provider"] = next_provider

    if "ticket_id" in data:
        ticket = await _get_ticket_scope(
            data["ticket_id"],
            current_user,
            db,
            require_ticket=not support_access,
        )
        integration.ticket_id = ticket.id if ticket else None
        data.pop("ticket_id")

    for field, value in data.items():
        setattr(integration, field, value)
    await db.commit()
    await db.refresh(integration)
    return _view(integration)


@router.post("/{integration_id}/trigger")
async def trigger_webhook(
    integration_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    integration = await _get_integration_with_access(integration_id, current_user, db)
    if not integration.is_active:
        raise HTTPException(400, "Integration is disabled")

    try:
        ticket = None
        if integration.ticket_id:
            ticket = await _get_ticket_scope(
                integration.ticket_id,
                current_user,
                db,
                require_ticket=True,
            )

        payload = build_test_payload(integration=integration, ticket=ticket, actor=current_user)
        result = await deliver_integration_payload(integration=integration, payload=payload)
        provider = integration_provider(integration)
        return {
            "integration_id": integration.id,
            "status_code": result["status_code"],
            "ok": result["ok"],
            "body": result.get("body", ""),
            "provider": provider,
            "provider_label": provider_label(provider),
        }
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(502, "Delivery failed")
