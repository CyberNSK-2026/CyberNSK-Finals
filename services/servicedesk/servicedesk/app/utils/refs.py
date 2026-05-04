from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


async def next_case_number(db: AsyncSession) -> str:
    result = await db.execute(text("SELECT nextval('ticket_case_seq')"))
    return f"SD-{int(result.scalar_one()):06d}"


async def next_artifact_ref(db: AsyncSession) -> int:
    result = await db.execute(text("SELECT nextval('artifact_ref_seq')"))
    return int(result.scalar_one())
