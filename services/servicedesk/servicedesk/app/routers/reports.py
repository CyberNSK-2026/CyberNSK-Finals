from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models import Report, Ticket, User
from utils.auth import get_current_user, has_support_access
from utils.template_engine import (
    TemplateRejected,
    TemplateSyntaxError,
    build_report_context,
    get_report_renderer,
)

router = APIRouter(prefix="/api/reports", tags=["reports"])


class ReportRequest(BaseModel):
    ticket_id: str
    custom_template: Optional[str] = None


@router.post("")
async def generate_report(
    body: ReportRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Ticket).where(Ticket.id == body.ticket_id))
    ticket = result.scalar_one_or_none()
    if not ticket:
        raise HTTPException(404, "Ticket not found")

    if not has_support_access(current_user) and ticket.customer_id != current_user.id:
        raise HTTPException(403, "Forbidden")

    template_str = body.custom_template or ticket.report_template or "Ticket {{ ticket.title }}"

    renderer = get_report_renderer()
    context = build_report_context(ticket, current_user)
    try:
        rendered = renderer.render(template_str, context)
    except TemplateRejected as e:
        raise HTTPException(400, str(e))
    except TemplateSyntaxError as e:
        raise HTTPException(400, f"Template syntax error: {e}")
    except Exception as e:
        rendered = f"[render error] {str(e)}"

    report = Report(
        ticket_id=ticket.id,
        generated_by=current_user.id,
        content=rendered,
    )
    db.add(report)
    await db.commit()
    await db.refresh(report)

    return {
        "report_id": report.id,
        "ticket_id": ticket.id,
        "content": rendered,
        "created_at": str(report.created_at),
    }


@router.get("/{report_id}")
async def get_report(
    report_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Report).where(Report.id == report_id))
    report = result.scalar_one_or_none()
    if not report:
        raise HTTPException(404, "Report not found")
    if report.generated_by != current_user.id and not has_support_access(current_user):
        raise HTTPException(403, "Forbidden")
    return {"report_id": report.id, "content": report.content, "created_at": str(report.created_at)}
