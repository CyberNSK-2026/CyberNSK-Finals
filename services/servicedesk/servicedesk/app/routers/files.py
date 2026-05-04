import os
import time

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from config import settings
from database import get_db
from models import Artifact, Ticket, TicketMessage, User
from utils.auth import get_current_user, has_support_access
from utils.filenames import FilenameRejected, normalise_export_name

router = APIRouter(prefix="/api/files", tags=["files"])


class ExportRequest(BaseModel):
    ticket_id: str


def _exports_dir() -> str:
    export_dir = os.path.join(settings.upload_dir, "exports")
    os.makedirs(export_dir, exist_ok=True)
    return export_dir


async def _ticket_for_export(ticket_id: str, current_user: User, db: AsyncSession) -> Ticket:
    result = await db.execute(select(Ticket).where(Ticket.id == ticket_id))
    ticket = result.scalar_one_or_none()
    if not ticket:
        raise HTTPException(404, "Ticket not found")
    if not has_support_access(current_user) and ticket.customer_id != current_user.id:
        raise HTTPException(403, "Forbidden")
    return ticket


@router.post("/exports")
async def create_ticket_export(
    body: ExportRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    ticket = await _ticket_for_export(body.ticket_id, current_user, db)

    message_rows = await db.execute(
        select(TicketMessage, User)
        .join(User, User.id == TicketMessage.author_id)
        .where(TicketMessage.ticket_id == ticket.id)
        .order_by(TicketMessage.created_at.asc())
    )
    artifact_rows = await db.execute(
        select(Artifact).where(Artifact.ticket_id == ticket.id).order_by(Artifact.uploaded_at.asc())
    )

    lines = [
        f"Case Number: {ticket.case_number}",
        f"Case Export: {ticket.id}",
        f"Title: {ticket.title}",
        f"Status: {ticket.status}",
        f"Priority: {ticket.priority}",
        f"Customer: {ticket.customer_id}",
        f"Vendor Case ID: {ticket.vendor_case_id or ''}",
        f"Device Serial: {ticket.device_serial or ''}",
        "",
        "Description:",
        ticket.description or "",
        "",
        "Messages:",
    ]

    for message, author in message_rows.all():
        lines.extend([
            f"- {author.username} ({author.role}) @ {message.created_at}",
            message.body,
            "",
        ])

    lines.append("Attachments:")
    for artifact in artifact_rows.scalars().all():
        lines.extend([
            f"- {artifact.filename}",
            f"  Note: {artifact.description or ''}",
        ])

    export_name = f"case-export-{ticket.case_number}-{int(time.time())}.txt"
    export_path = os.path.join(_exports_dir(), export_name)
    with open(export_path, "w", encoding="utf-8") as export_file:
        export_file.write("\n".join(lines))

    return {
        "ticket_id": ticket.id,
        "export_name": export_name,
        "download_path": f"/api/files/exports/download?name={export_name}",
    }


@router.get("/exports/download")
async def download_export(
    name: str,
    current_user: User = Depends(get_current_user),
):
    try:
        safe_name = normalise_export_name(name)
    except FilenameRejected as exc:
        raise HTTPException(400, str(exc))

    file_path = os.path.join(_exports_dir(), safe_name)

    if not os.path.exists(file_path):
        raise HTTPException(404, "File not found")

    return FileResponse(file_path, filename=os.path.basename(file_path))


@router.get("/artifact/{artifact_id}")
async def safe_download(
    artifact_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Artifact).where(Artifact.id == artifact_id))
    artifact = result.scalar_one_or_none()
    if not artifact:
        raise HTTPException(404, "Not found")

    if not has_support_access(current_user):
        t = await db.execute(select(Ticket).where(Ticket.id == artifact.ticket_id))
        ticket = t.scalar_one_or_none()
        if not ticket or ticket.customer_id != current_user.id:
            raise HTTPException(403, "Forbidden")

    if not os.path.exists(artifact.storage_path):
        raise HTTPException(404, "File not found on disk")

    return FileResponse(artifact.storage_path, filename=artifact.filename)
