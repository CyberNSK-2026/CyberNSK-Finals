import os
import re

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from config import settings
from models import Artifact, Ticket, TicketMessage, User

def case_directory(case_number: str) -> str:
    path = os.path.join(settings.upload_dir, "cases", case_number)
    os.makedirs(path, exist_ok=True)
    return path


def snapshot_path(case_number: str) -> str:
    return os.path.join(case_directory(case_number), "snapshot.txt")


def artifact_storage_path(case_number: str, public_ref: int, filename: str | None) -> str:
    common_name = re.compile(r"[^A-Za-z0-9._-]+").sub("_", os.path.basename(filename or "attachment.bin")).strip("._")
    if not common_name:
        common_name = "attachment.bin"
    return os.path.join(case_directory(case_number), f"{public_ref:06d}-{common_name}")


async def write_case_snapshot(ticket: Ticket, db: AsyncSession) -> None:
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
        f"Case: {ticket.case_number}",
        f"Title: {ticket.title}",
        f"Status: {ticket.status}",
        f"Priority: {ticket.priority}",
        f"Vendor Case ID: {ticket.vendor_case_id or ''}",
        f"Device Serial: {ticket.device_serial or ''}",
        f"Description: {ticket.description or ''}",
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
        lines.append(f"- #{artifact.public_ref}: {artifact.filename}")

    with open(snapshot_path(ticket.case_number), "w", encoding="utf-8") as snapshot:
        snapshot.write("\n".join(lines))
