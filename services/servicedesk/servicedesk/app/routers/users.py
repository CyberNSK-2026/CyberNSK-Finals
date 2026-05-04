from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models import User
from utils.auth import get_current_user, has_support_access

router = APIRouter(prefix="/api/users", tags=["users"])

ALLOWED_WORKSPACES = {"portal", "kiosk", "operations"}
ALLOWED_QUEUE_SCOPES = {"personal", "team", "all"}


class ProfileUpdate(BaseModel):
    username: Optional[str] = None
    email: Optional[str] = None
    contact_phone: Optional[str] = Field(default=None, max_length=128)
    workspace: Optional[str] = None
    queue_scope: Optional[str] = None
    access_level: Optional[int] = Field(default=None, ge=1, le=5)


@router.get("/me")
async def get_me(current_user: User = Depends(get_current_user)):
    return {
        "id": current_user.id,
        "username": current_user.username,
        "email": current_user.email,
        "contact_phone": current_user.contact_phone,
        "role": current_user.role,
        "support_mode": has_support_access(current_user),
    }


@router.patch("/me")
async def update_profile(
    body: ProfileUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    data = body.model_dump(exclude_none=True)

    if "workspace" in data and data["workspace"] not in ALLOWED_WORKSPACES:
        raise HTTPException(400, "Unsupported workspace")
    if "queue_scope" in data and data["queue_scope"] not in ALLOWED_QUEUE_SCOPES:
        raise HTTPException(400, "Unsupported queue scope")

    for field, value in data.items():
        setattr(current_user, field, value)

    await db.commit()
    await db.refresh(current_user)

    return {
        "id": current_user.id,
        "username": current_user.username,
        "role": current_user.role,
        "workspace": current_user.workspace,
        "queue_scope": current_user.queue_scope,
        "contact_phone": current_user.contact_phone,
    }


@router.get("/{user_id}")
async def get_user(
    user_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if not has_support_access(current_user) and current_user.id != user_id:
        raise HTTPException(403, "Forbidden")
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(404, "User not found")
    return {
        "id": user.id,
        "username": user.username,
        "role": user.role,
        "access_level": user.access_level,
        "workspace": user.workspace,
        "contact_phone": user.contact_phone,
    }


@router.get("")
async def list_users(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(User))
    users = result.scalars().all()
    payload = []
    for u in users:
        entry = {
            "id": u.id,
            "username": u.username,
            "role": u.role,
            "access_level": u.access_level,
            "workspace": u.workspace,
            "contact_phone": u.contact_phone,
        }
        payload.append(entry)
    return payload
