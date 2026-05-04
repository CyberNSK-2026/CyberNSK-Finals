from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from config import settings
from database import get_db
from models import User
from utils.roles import is_support_capable

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")




def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (
        expires_delta or timedelta(minutes=settings.jwt_expire_minutes)
    )
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.jwt_secret, algorithm=settings.jwt_algorithm)


async def _lookup_by_account_id(db: AsyncSession, account_id: str) -> User | None:
    result = await db.execute(select(User).where(User.id == account_id))
    return result.scalar_one_or_none()


async def _lookup_by_account_handle(db: AsyncSession, handle: str) -> User | None:
    result = await db.execute(select(User).where(User.username == handle))
    return result.scalar_one_or_none()


async def _resolve_principal(db: AsyncSession, subject: str, kind: str) -> User | None:
    if kind == "service":
        return await _lookup_by_account_handle(db, subject)
    return await _lookup_by_account_id(db, subject)


async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except JWTError:
        raise credentials_exception

    subject: str = payload.get("sub")
    if not subject:
        raise credentials_exception
    kind: str = payload.get("kind", "user")

    user = await _resolve_principal(db, subject, kind)
    if user is None:
        raise credentials_exception
    return user


def has_support_access(user) -> bool:
    return is_support_capable(user)


async def require_agent(current_user: User = Depends(get_current_user)) -> User:
    if not has_support_access(current_user):
        raise HTTPException(status_code=403, detail="Agent role required")
    return current_user
