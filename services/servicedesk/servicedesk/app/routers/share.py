from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models import Artifact, ShareToken, Ticket, TicketMessage, User
from models import User as UserModel
from utils.auth import get_current_user, has_support_access
from utils.share_tokens import ensure_share_token

router = APIRouter(prefix="/api/share", tags=["share"])


class ShareCreate(BaseModel):
    ticket_id: str
    audience: str = "external-review"


@router.post("")
async def create_share_token(
    body: ShareCreate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Ticket).where(Ticket.id == body.ticket_id))
    ticket = result.scalar_one_or_none()
    if not ticket:
        raise HTTPException(404, "Ticket not found")
    if not has_support_access(current_user) and ticket.customer_id != current_user.id:
        raise HTTPException(403, "Forbidden")

    share = await ensure_share_token(
        db=db,
        ticket_id=body.ticket_id,
        created_by=current_user.id,
        case_number=ticket.case_number,
        audience=body.audience,
    )
    share_path = f"/api/share/{share.token}"
    host = request.headers.get("host") or request.url.netloc
    scheme = request.headers.get("x-forwarded-proto", request.url.scheme)
    return {
        "share_token": share.token,
        "share_url": f"{scheme}://{host}{share_path}",
        "share_path": share_path,
        "ticket_id": share.ticket_id,
        "case_number": ticket.case_number,
    }


@router.get("/{token}")
async def view_shared_ticket(
    token: str,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(ShareToken).where(ShareToken.token == token))
    share = result.scalar_one_or_none()
    if not share or not share.is_active:
        raise HTTPException(404, "Share token not found or expired")

    t_result = await db.execute(select(Ticket).where(Ticket.id == share.ticket_id))
    ticket = t_result.scalar_one_or_none()
    if not ticket:
        raise HTTPException(404, "Ticket not found")

    a_result = await db.execute(
        select(Artifact).where(Artifact.ticket_id == ticket.id)
    )
    artifacts = a_result.scalars().all()
    m_result = await db.execute(
        select(TicketMessage, UserModel)
        .join(UserModel, UserModel.id == TicketMessage.author_id)
        .where(TicketMessage.ticket_id == ticket.id)
        .order_by(TicketMessage.created_at.asc())
    )

    return {
        "ticket": {
            "id": ticket.id,
            "case_number": ticket.case_number,
            "title": ticket.title,
            "description": ticket.description,
            "vendor_case_id": ticket.vendor_case_id,
            "status": ticket.status,
            "priority": ticket.priority,
            "report_template": ticket.report_template,
            "resolution": ticket.resolution,
        },
        "artifacts": [
            {
                "id": a.id,
                "filename": a.filename,
                "description": a.description,
            }
            for a in artifacts
        ],
        "messages": [
            {
                "id": message.id,
                "body": message.body,
                "author_username": author.username,
                "author_role": author.role,
                "created_at": str(message.created_at),
            }
            for message, author in m_result.all()
        ],
    }
