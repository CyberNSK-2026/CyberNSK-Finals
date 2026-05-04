import os
import uuid
from typing import Optional

import aiofiles
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models import Artifact, Ticket, TicketMessage, TicketPriority, TicketStatus, User
from utils.auth import get_current_user, has_support_access
from utils.casefiles import artifact_storage_path, write_case_snapshot
from utils.dispatchboard import record_preview
from utils.refs import next_artifact_ref, next_case_number
from utils.share_tokens import ensure_share_token
from utils.ticket_events import emit_ticket_event

router = APIRouter(prefix="/api/tickets", tags=["tickets"])


class TicketCreate(BaseModel):
    title: str
    description: Optional[str] = None
    priority: TicketPriority = TicketPriority.medium
    report_template: Optional[str] = None
    vendor_case_id: Optional[str] = None
    device_serial: Optional[str] = None
    automation_secret: Optional[str] = None


class TicketUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    status: Optional[TicketStatus] = None
    priority: Optional[TicketPriority] = None
    report_template: Optional[str] = None
    resolution: Optional[str] = None
    agent_id: Optional[str] = None
    vendor_case_id: Optional[str] = None
    device_serial: Optional[str] = None
    automation_secret: Optional[str] = None


class TicketMessageCreate(BaseModel):
    body: str


def _summarise_ticket_update(before: dict, ticket: Ticket) -> tuple[str, str]:
    changes: list[str] = []

    if before["status"] != ticket.status:
        changes.append(f"status {before['status']} -> {ticket.status}")
    if before["priority"] != ticket.priority:
        changes.append(f"priority {before['priority']} -> {ticket.priority}")
    if before["agent_id"] != ticket.agent_id:
        changes.append("owner assigned" if ticket.agent_id else "owner cleared")
    if before["resolution"] != ticket.resolution:
        changes.append("resolution updated")
    if before["title"] != ticket.title:
        changes.append("title updated")
    if before["description"] != ticket.description:
        changes.append("description updated")
    if before["vendor_case_id"] != ticket.vendor_case_id:
        changes.append("vendor case ID updated")
    if before["device_serial"] != ticket.device_serial:
        changes.append("device serial updated")

    if not changes:
        return "Ticket updated", "Ticket fields were updated."

    return (
        "Ticket updated: " + ", ".join(changes[:3]),
        "\n".join(f"- {item}" for item in changes),
    )


async def _get_ticket_with_access(
    ticket_id: str,
    current_user: User,
    db: AsyncSession,
) -> Ticket:
    result = await db.execute(select(Ticket).where(Ticket.id == ticket_id))
    ticket = result.scalar_one_or_none()
    if not ticket:
        raise HTTPException(404, "Ticket not found")
    if not has_support_access(current_user) and ticket.customer_id != current_user.id:
        raise HTTPException(403, "Forbidden")
    return ticket


async def _resolve_artifact_by_reference(reference: str, db: AsyncSession) -> Artifact | None:
    filters = [Artifact.id == reference]
    if reference.isdigit():
        filters.append(Artifact.public_ref == int(reference))
    result = await db.execute(select(Artifact).where(or_(*filters)))
    return result.scalar_one_or_none()


def _ticket_view(ticket: Ticket, support_access: bool) -> dict:
    base = {
        "id": ticket.id,
        "case_number": ticket.case_number,
        "title": ticket.title,
        "description": ticket.description,
        "vendor_case_id": ticket.vendor_case_id,
        "device_serial": ticket.device_serial,
        "status": ticket.status,
        "priority": ticket.priority,
        "created_at": str(ticket.created_at),
        "customer_id": ticket.customer_id,
    }
    if support_access:
        base.update({
            "resolution": ticket.resolution,
            "agent_id": ticket.agent_id,
        })
    return base


@router.post("")
async def create_ticket(
    body: TicketCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    ticket = Ticket(
        case_number=await next_case_number(db),
        title=body.title,
        description=body.description,
        vendor_case_id=body.vendor_case_id,
        device_serial=body.device_serial,
        automation_secret=body.automation_secret,
        priority=body.priority,
        customer_id=current_user.id,
        report_template=body.report_template or f"Case {{{{ ticket.case_number }}}}: {{{{ ticket.title }}}}",
    )
    db.add(ticket)
    await db.commit()
    await db.refresh(ticket)
    await ensure_share_token(db, ticket.id, current_user.id, ticket.case_number)
    await write_case_snapshot(ticket, db)
    await record_preview(
        reference=ticket.case_number,
        event_type="ticket.created",
        preview=f"{ticket.title}\n{ticket.description or ''}",
    )
    await emit_ticket_event(
        db=db,
        ticket=ticket,
        event_type="ticket.created",
        summary="Ticket created",
        body=ticket.description or ticket.title,
        actor=current_user,
    )
    return _ticket_view(ticket, has_support_access(current_user))


@router.get("")
async def list_tickets(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    support_access = has_support_access(current_user)
    if support_access:
        result = await db.execute(select(Ticket))
    else:
        result = await db.execute(select(Ticket).where(Ticket.customer_id == current_user.id))
    tickets = result.scalars().all()
    return [_ticket_view(ticket, support_access) for ticket in tickets]


@router.get("/{ticket_id}")
async def get_ticket(
    ticket_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    ticket = await _get_ticket_with_access(ticket_id, current_user, db)
    return _ticket_view(ticket, has_support_access(current_user))


@router.patch("/{ticket_id}")
async def update_ticket(
    ticket_id: str,
    body: TicketUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    ticket = await _get_ticket_with_access(ticket_id, current_user, db)
    support_access = has_support_access(current_user)
    data = body.model_dump(exclude_none=True)
    before = {
        "title": ticket.title,
        "description": ticket.description,
        "status": ticket.status,
        "priority": ticket.priority,
        "resolution": ticket.resolution,
        "agent_id": ticket.agent_id,
        "vendor_case_id": ticket.vendor_case_id,
        "device_serial": ticket.device_serial,
    }

    if not support_access:
        allowed_fields = {
            "title",
            "description",
            "report_template",
            "vendor_case_id",
            "device_serial",
            "automation_secret",
        }
        for field, value in data.items():
            if field in allowed_fields:
                setattr(ticket, field, value)
    else:
        for field, value in data.items():
            setattr(ticket, field, value)

    await db.commit()
    await db.refresh(ticket)
    await write_case_snapshot(ticket, db)
    await record_preview(
        reference=ticket.case_number,
        event_type="ticket.updated",
        preview=f"{ticket.title}\n{ticket.description or ''}\n{ticket.resolution or ''}",
    )
    summary, event_body = _summarise_ticket_update(before, ticket)
    await emit_ticket_event(
        db=db,
        ticket=ticket,
        event_type="ticket.updated",
        summary=summary,
        body=event_body,
        actor=current_user,
    )
    return _ticket_view(ticket, support_access)


@router.post("/{ticket_id}/artifacts")
async def upload_artifact(
    ticket_id: str,
    file: UploadFile = File(...),
    description: str = Form(default=""),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    ticket = await _get_ticket_with_access(ticket_id, current_user, db)
    if ticket.status == TicketStatus.closed:
        raise HTTPException(409, "Closed tickets do not accept new attachments")

    artifact_id = str(uuid.uuid4())
    public_ref = await next_artifact_ref(db)
    storage_path = artifact_storage_path(ticket.case_number, public_ref, file.filename)

    async with aiofiles.open(storage_path, "wb") as handle:
        content = await file.read()
        await handle.write(content)

    artifact = Artifact(
        id=artifact_id,
        public_ref=public_ref,
        ticket_id=ticket.id,
        filename=file.filename,
        description=description,
        content_type=file.content_type,
        file_size=len(content),
        storage_path=storage_path,
    )
    db.add(artifact)
    await db.commit()
    await db.refresh(artifact)
    await write_case_snapshot(ticket, db)
    await record_preview(
        reference=str(artifact.public_ref),
        event_type="artifact.uploaded",
        preview=f"{artifact.filename}\n{artifact.description or ''}",
    )
    await emit_ticket_event(
        db=db,
        ticket=ticket,
        event_type="artifact.uploaded",
        summary=f"Attachment uploaded: {artifact.filename}",
        body=artifact.description or artifact.filename,
        actor=current_user,
    )

    return {
        "id": artifact.id,
        "public_ref": artifact.public_ref,
        "filename": artifact.filename,
        "description": artifact.description,
        "content_type": artifact.content_type,
        "file_size": artifact.file_size,
        "uploaded_at": str(artifact.uploaded_at),
    }


@router.get("/{ticket_id}/artifacts")
async def list_artifacts(
    ticket_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await _get_ticket_with_access(ticket_id, current_user, db)
    result = await db.execute(select(Artifact).where(Artifact.ticket_id == ticket_id))
    artifacts = result.scalars().all()
    return [
        {
            "id": artifact.id,
            "public_ref": artifact.public_ref,
            "filename": artifact.filename,
            "content_type": artifact.content_type,
            "file_size": artifact.file_size,
        }
        for artifact in artifacts
    ]


@router.get("/{ticket_id}/messages")
async def list_messages(
    ticket_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await _get_ticket_with_access(ticket_id, current_user, db)
    result = await db.execute(
        select(TicketMessage, User)
        .join(User, User.id == TicketMessage.author_id)
        .where(TicketMessage.ticket_id == ticket_id)
        .order_by(TicketMessage.created_at.asc())
    )
    return [
        {
            "id": message.id,
            "body": message.body,
            "created_at": str(message.created_at),
            "author_id": author.id,
            "author_username": author.username,
            "author_role": author.role,
        }
        for message, author in result.all()
    ]


@router.post("/{ticket_id}/messages")
async def create_message(
    ticket_id: str,
    body: TicketMessageCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    ticket = await _get_ticket_with_access(ticket_id, current_user, db)
    if ticket.status == TicketStatus.closed:
        raise HTTPException(409, "Closed tickets do not accept new messages")
    text = body.body.strip()
    if not text:
        raise HTTPException(400, "Message body cannot be empty")

    message = TicketMessage(
        ticket_id=ticket.id,
        author_id=current_user.id,
        body=text,
    )
    db.add(message)
    await db.commit()
    await db.refresh(message)
    await write_case_snapshot(ticket, db)
    await record_preview(
        reference=message.id,
        event_type="ticket.message.created",
        preview=message.body,
    )
    await emit_ticket_event(
        db=db,
        ticket=ticket,
        event_type="ticket.message.created",
        summary=f"New message from {current_user.username}",
        body=message.body,
        actor=current_user,
    )
    return {
        "id": message.id,
        "body": message.body,
        "created_at": str(message.created_at),
        "author_id": current_user.id,
        "author_username": current_user.username,
        "author_role": current_user.role,
    }


@router.get("/{ticket_id}/artifacts/{artifact_id}")
async def get_artifact(
    ticket_id: str,
    artifact_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if not has_support_access(current_user):
        await _get_ticket_with_access(ticket_id, current_user, db)

    artifact = await _resolve_artifact_by_reference(artifact_id, db)
    if not artifact:
        raise HTTPException(404, "Artifact not found")

    return {
        "id": artifact.id,
        "public_ref": artifact.public_ref,
        "ticket_id": artifact.ticket_id,
        "filename": artifact.filename,
        "description": artifact.description,
        "content_type": artifact.content_type,
        "file_size": artifact.file_size,
        "uploaded_at": str(artifact.uploaded_at),
    }


@router.get("/{ticket_id}/artifacts/{artifact_id}/download")
async def download_artifact(
    ticket_id: str,
    artifact_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if not has_support_access(current_user):
        await _get_ticket_with_access(ticket_id, current_user, db)

    artifact = await _resolve_artifact_by_reference(artifact_id, db)
    if not artifact:
        raise HTTPException(404, "Artifact not found")
    if not os.path.exists(artifact.storage_path):
        raise HTTPException(404, "File not found on disk")

    return FileResponse(
        artifact.storage_path,
        filename=artifact.filename,
        media_type=artifact.content_type or "application/octet-stream",
    )
