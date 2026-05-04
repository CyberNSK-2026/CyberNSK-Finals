from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from config import settings
from models import Integration, Ticket, TicketEvent, User, UserRole
from utils.delivery_providers import integration_provider, provider_label, resolve_integration_target
from utils.notifications import DISPATCH_TOKEN_HEADER, SIGNATURE_HEADER, get_dispatch_token


@dataclass(frozen=True)
class PreparedIntegrationDelivery:
    integration_id: str
    target_url: str
    signing_token: str | None
    payload: dict[str, Any]


_background_delivery_tasks: set[asyncio.Task[Any]] = set()


def build_ticket_snapshot(ticket: Ticket) -> dict[str, Any]:
    return {
        "id": ticket.id,
        "case_number": ticket.case_number,
        "title": ticket.title,
        "description": ticket.description,
        "vendor_case_id": ticket.vendor_case_id,
        "device_serial": ticket.device_serial,
        "status": ticket.status,
        "priority": ticket.priority,
        "customer_id": ticket.customer_id,
        "agent_id": ticket.agent_id,
        "resolution": ticket.resolution,
        "created_at": str(ticket.created_at),
        "updated_at": str(ticket.updated_at),
    }


def build_actor_snapshot(actor: User | None) -> dict[str, Any] | None:
    if actor is None:
        return None
    return {
        "id": actor.id,
        "username": actor.username,
        "role": actor.role,
    }


def _build_generic_payload(
    *,
    ticket: Ticket,
    event_type: str,
    summary: str,
    body: str | None,
    actor: User | None,
    happened_at: datetime,
    integration: Integration,
) -> tuple[dict[str, Any], str, str]:
    case_ref = ticket.case_number or ticket.id
    headline = f"[{case_ref}] {summary}"
    preview = (body or "").strip()
    rendered_text = headline if not preview else f"{headline}\n{preview}"
    rendered_text = rendered_text[:1900]

    payload = {
        "event": event_type,
        "event_type": event_type,
        "summary": summary,
        "message": body or summary,
        "text": rendered_text,
        "content": rendered_text,
        "destination": integration.name,
        "happened_at": happened_at.isoformat(),
        "ticket_id": ticket.id,
        "ticket": build_ticket_snapshot(ticket),
        "actor": build_actor_snapshot(actor),
        "portal_url": settings.portal_base_url,
    }
    return payload, headline, rendered_text


def build_webhook_payload(
    *,
    ticket: Ticket,
    event_type: str,
    summary: str,
    body: str | None,
    actor: User | None,
    happened_at: datetime,
    integration: Integration,
) -> dict[str, Any]:
    generic, headline, rendered_text = _build_generic_payload(
        ticket=ticket,
        event_type=event_type,
        summary=summary,
        body=body,
        actor=actor,
        happened_at=happened_at,
        integration=integration,
    )
    provider = integration_provider(integration)
    case_ref = ticket.case_number or ticket.id
    actor_name = actor.username if actor else "system"
    portal_url = generic["portal_url"]

    if provider == "discord":
        return {
            "username": "ServiceDesk",
            "content": headline,
            "embeds": [
                {
                    "title": summary,
                    "description": rendered_text,
                    "color": 5793266,
                    "fields": [
                        {"name": "Case", "value": case_ref, "inline": True},
                        {"name": "Actor", "value": actor_name, "inline": True},
                        {"name": "Event", "value": event_type, "inline": True},
                    ],
                    "footer": {"text": "ServiceDesk"},
                    "url": portal_url,
                }
            ],
        }

    if provider == "slack":
        return {
            "text": rendered_text,
            "blocks": [
                {
                    "type": "header",
                    "text": {"type": "plain_text", "text": f"ServiceDesk: {summary}"},
                },
                {
                    "type": "section",
                    "text": {"type": "mrkdwn", "text": rendered_text},
                },
                {
                    "type": "context",
                    "elements": [
                        {"type": "mrkdwn", "text": f"*Case:* {case_ref}"},
                        {"type": "mrkdwn", "text": f"*Actor:* {actor_name}"},
                        {"type": "mrkdwn", "text": f"*Link:* {portal_url}"},
                    ],
                },
            ],
        }

    if provider == "teams":
        return {
            "@type": "MessageCard",
            "@context": "https://schema.org/extensions",
            "summary": summary,
            "themeColor": "2F80ED",
            "title": f"ServiceDesk: {summary}",
            "text": rendered_text,
            "sections": [
                {
                    "facts": [
                        {"name": "Case", "value": case_ref},
                        {"name": "Actor", "value": actor_name},
                        {"name": "Event", "value": event_type},
                    ],
                    "markdown": True,
                }
            ],
            "potentialAction": [
                {
                    "@type": "OpenUri",
                    "name": "Open ServiceDesk",
                    "targets": [{"os": "default", "uri": portal_url}],
                }
            ],
        }

    generic["provider"] = provider
    generic["provider_label"] = provider_label(provider)
    return generic


def build_test_payload(
    *,
    integration: Integration,
    ticket: Ticket | None,
    actor: User | None,
) -> dict[str, Any]:
    now = datetime.now(timezone.utc)
    provider = integration_provider(integration)
    if ticket is None:
        preview = "This is a delivery preview generated by ServiceDesk."
        if provider == "discord":
            return {
                "username": "ServiceDesk",
                "content": "ServiceDesk test delivery",
                "embeds": [
                    {
                        "title": "Test delivery from ServiceDesk",
                        "description": preview,
                        "color": 5793266,
                    }
                ],
            }
        if provider == "slack":
            return {
                "text": f"ServiceDesk test delivery\n{preview}",
                "blocks": [
                    {
                        "type": "section",
                        "text": {"type": "mrkdwn", "text": f"*ServiceDesk test delivery*\n{preview}"},
                    }
                ],
            }
        if provider == "teams":
            return {
                "@type": "MessageCard",
                "@context": "https://schema.org/extensions",
                "summary": "Test delivery from ServiceDesk",
                "themeColor": "2F80ED",
                "title": "ServiceDesk test delivery",
                "text": preview,
            }
        return {
            "event": "notification.test",
            "event_type": "notification.test",
            "summary": "Test delivery from ServiceDesk",
            "message": preview,
            "text": f"ServiceDesk test delivery\n{preview}",
            "content": f"ServiceDesk test delivery\n{preview}",
            "destination": integration.name,
            "happened_at": now.isoformat(),
            "ticket_id": integration.ticket_id,
            "ticket": None,
            "actor": build_actor_snapshot(actor),
            "portal_url": settings.portal_base_url,
            "provider": provider,
            "provider_label": provider_label(provider),
        }

    return build_webhook_payload(
        ticket=ticket,
        event_type="ticket.delivery.test",
        summary="Test delivery from ServiceDesk",
        body="This is a delivery preview generated by ServiceDesk for the linked ticket.",
        actor=actor,
        happened_at=now,
        integration=integration,
    )


def _workspace_integration_matches(ticket: Ticket, integration: Integration, owner: User) -> bool:
    if integration.ticket_id:
        return integration.ticket_id == ticket.id

    if owner.role == UserRole.customer:
        return owner.id == ticket.customer_id

    if owner.queue_scope == "all":
        return True

    return owner.id == ticket.agent_id


async def _matching_integrations(db: AsyncSession, ticket: Ticket) -> list[Integration]:
    result = await db.execute(
        select(Integration, User)
        .join(User, User.id == Integration.owner_id)
        .where(Integration.is_active.is_(True))
    )

    matches: dict[str, Integration] = {}
    for integration, owner in result.all():
        if _workspace_integration_matches(ticket, integration, owner):
            matches[integration.id] = integration
    return list(matches.values())


def _prepare_integration_delivery(
    *,
    integration: Integration,
    payload: dict[str, Any],
) -> PreparedIntegrationDelivery:
    return PreparedIntegrationDelivery(
        integration_id=integration.id,
        target_url=resolve_integration_target(
            integration_provider(integration),
            integration.base_url,
            integration.endpoint_path,
        ),
        signing_token=integration.signing_token,
        payload=payload,
    )


async def _deliver_prepared_payload(
    *,
    delivery: PreparedIntegrationDelivery,
    client: httpx.AsyncClient | None = None,
) -> dict[str, Any]:
    headers = {
        DISPATCH_TOKEN_HEADER: get_dispatch_token(),
        "Content-Type": "application/json",
    }
    if delivery.signing_token:
        headers[SIGNATURE_HEADER] = delivery.signing_token

    owns_client = client is None
    if owns_client:
        client = httpx.AsyncClient(
            timeout=settings.webhook_request_timeout,
            follow_redirects=settings.webhook_follow_redirects,
        )

    try:
        response = await client.post(delivery.target_url, headers=headers, json=delivery.payload)
        body_preview = response.text[: settings.webhook_preview_bytes]
        return {
            "integration_id": delivery.integration_id,
            "status_code": response.status_code,
            "ok": response.is_success,
            "body": body_preview,
        }
    finally:
        if owns_client:
            await client.aclose()


async def deliver_integration_payload(
    *,
    integration: Integration,
    payload: dict[str, Any],
    client: httpx.AsyncClient | None = None,
) -> dict[str, Any]:
    return await _deliver_prepared_payload(
        delivery=_prepare_integration_delivery(integration=integration, payload=payload),
        client=client,
    )


async def _run_background_deliveries(deliveries: list[PreparedIntegrationDelivery]) -> None:
    if not deliveries:
        return

    try:
        async with httpx.AsyncClient(
            timeout=settings.webhook_request_timeout,
            follow_redirects=settings.webhook_follow_redirects,
        ) as client:
            results = await asyncio.gather(
                *[
                    _deliver_prepared_payload(delivery=delivery, client=client)
                    for delivery in deliveries
                ],
                return_exceptions=True,
            )
    except Exception as exc:
        print(f"ticket event background delivery setup failed: {exc}", flush=True)
        return

    for result in results:
        if isinstance(result, Exception):
            print(f"ticket event delivery failed: {result}", flush=True)


def _schedule_background_deliveries(deliveries: list[PreparedIntegrationDelivery]) -> None:
    if not deliveries:
        return

    task = asyncio.create_task(_run_background_deliveries(deliveries))
    _background_delivery_tasks.add(task)
    task.add_done_callback(_background_delivery_tasks.discard)


async def emit_ticket_event(
    *,
    db: AsyncSession,
    ticket: Ticket,
    event_type: str,
    summary: str,
    body: str | None = None,
    actor: User | None = None,
) -> TicketEvent:
    happened_at = datetime.now(timezone.utc)
    event = TicketEvent(
        ticket_id=ticket.id,
        actor_id=actor.id if actor else None,
        event_type=event_type,
        summary=summary,
        body=body,
        created_at=happened_at,
    )
    db.add(event)
    await db.commit()

    integrations = await _matching_integrations(db, ticket)
    if integrations:
        deliveries: list[PreparedIntegrationDelivery] = []
        for integration in integrations:
            try:
                deliveries.append(
                    _prepare_integration_delivery(
                        integration=integration,
                        payload=build_webhook_payload(
                            ticket=ticket,
                            event_type=event.event_type,
                            summary=event.summary,
                            body=event.body,
                            actor=actor,
                            happened_at=event.created_at,
                            integration=integration,
                        ),
                    )
                )
            except Exception as exc:
                print(
                    f"ticket event delivery preparation failed for integration {integration.id}: {exc}",
                    flush=True,
                )
        _schedule_background_deliveries(deliveries)

    return event
