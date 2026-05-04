from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models import Ticket, TicketEvent, User
from utils.auth import get_current_user, has_support_access

router = APIRouter(prefix="/api/notifications", tags=["notifications"])


def _parse_after(value: Optional[str]) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise HTTPException(400, f"Invalid after cursor: {exc}")


@router.get("")
async def list_notifications(
    limit: int = Query(default=20, ge=1, le=50),
    after: Optional[str] = None,
    include_own: bool = False,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    cursor = _parse_after(after)

    stmt = (
        select(TicketEvent, Ticket, User)
        .join(Ticket, Ticket.id == TicketEvent.ticket_id)
        .outerjoin(User, User.id == TicketEvent.actor_id)
        .order_by(TicketEvent.created_at.desc())
        .limit(limit)
    )

    if has_support_access(current_user):
        stmt = stmt.where(Ticket.agent_id == current_user.id)
    else:
        stmt = stmt.where(Ticket.customer_id == current_user.id)

    if cursor is not None:
        stmt = stmt.where(TicketEvent.created_at > cursor)
    if not include_own:
        stmt = stmt.where((TicketEvent.actor_id.is_(None)) | (TicketEvent.actor_id != current_user.id))

    result = await db.execute(stmt)
    items = []
    for event, ticket, actor in result.all():
        items.append({
            "id": event.id,
            "ticket_id": ticket.id,
            "case_number": ticket.case_number,
            "ticket_title": ticket.title,
            "event_type": event.event_type,
            "summary": event.summary,
            "body": event.body,
            "created_at": event.created_at.isoformat(),
            "actor_id": actor.id if actor else None,
            "actor_username": actor.username if actor else None,
            "actor_role": actor.role if actor else None,
        })
    return {"items": items}
