import secrets

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from config import settings

engine = create_async_engine(settings.database_url, echo=False, pool_pre_ping=True)
AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


async def get_db() -> AsyncSession:
    async with AsyncSessionLocal() as session:
        yield session


async def init_db():
    from models import artifact, integration, report, share_token, ticket, ticket_event, ticket_message, user  # noqa

    async with engine.begin() as conn:
        await conn.execute(text("SELECT pg_advisory_xact_lock(2147483647)"))
        await conn.run_sync(Base.metadata.create_all)
        await conn.execute(
            text("ALTER TABLE users ADD COLUMN IF NOT EXISTS workspace VARCHAR(32) DEFAULT 'portal'")
        )
        await conn.execute(
            text("ALTER TABLE users ADD COLUMN IF NOT EXISTS queue_scope VARCHAR(32) DEFAULT 'personal'")
        )
        await conn.execute(
            text("ALTER TABLE users ADD COLUMN IF NOT EXISTS contact_phone VARCHAR(128) DEFAULT ''")
        )
        await conn.execute(
            text("ALTER TABLE integrations ADD COLUMN IF NOT EXISTS ticket_id VARCHAR(36)")
        )
        await conn.execute(
            text("ALTER TABLE integrations ADD COLUMN IF NOT EXISTS provider VARCHAR(64) DEFAULT 'generic_webhook'")
        )
        await conn.execute(
            text("ALTER TABLE integrations ADD COLUMN IF NOT EXISTS base_url VARCHAR(512) DEFAULT ''")
        )
        await conn.execute(
            text("ALTER TABLE integrations ADD COLUMN IF NOT EXISTS endpoint_path TEXT DEFAULT ''")
        )
        await conn.execute(
            text("ALTER TABLE integrations ALTER COLUMN base_url SET DEFAULT ''")
        )
        await conn.execute(
            text("ALTER TABLE integrations ALTER COLUMN endpoint_path SET DEFAULT ''")
        )
        await conn.execute(
            text("UPDATE integrations SET provider = 'generic_webhook' WHERE provider IS NULL")
        )
        await conn.execute(
            text(
                "UPDATE integrations SET base_url = '', endpoint_path = '' "
                "WHERE provider = 'discord' AND endpoint_path = '/providers/discord'"
            )
        )
        await conn.execute(
            text(
                "UPDATE integrations SET base_url = '', endpoint_path = '' "
                "WHERE provider = 'slack' AND endpoint_path = '/providers/slack'"
            )
        )
        await conn.execute(
            text(
                "UPDATE integrations SET base_url = '', endpoint_path = '' "
                "WHERE provider = 'teams' AND endpoint_path = '/providers/teams'"
            )
        )
        await conn.execute(
            text(
                "UPDATE integrations SET base_url = '', endpoint_path = '' "
                "WHERE provider = 'generic_webhook' AND endpoint_path = '/providers/webhook'"
            )
        )
        await conn.execute(text("CREATE SEQUENCE IF NOT EXISTS ticket_case_seq"))
        await conn.execute(text("CREATE SEQUENCE IF NOT EXISTS artifact_ref_seq"))
        await conn.execute(
            text("ALTER TABLE tickets ADD COLUMN IF NOT EXISTS case_number VARCHAR(32)")
        )
        await conn.execute(
            text("ALTER TABLE tickets ADD COLUMN IF NOT EXISTS vendor_case_id VARCHAR(128)")
        )
        await conn.execute(
            text("ALTER TABLE tickets ADD COLUMN IF NOT EXISTS device_serial VARCHAR(128)")
        )
        await conn.execute(
            text("ALTER TABLE tickets ADD COLUMN IF NOT EXISTS automation_secret VARCHAR(256)")
        )
        await conn.execute(
            text("ALTER TABLE artifacts ADD COLUMN IF NOT EXISTS public_ref BIGINT")
        )
        await conn.execute(
            text(
                "UPDATE tickets "
                "SET case_number = 'SD-' || LPAD(nextval('ticket_case_seq')::text, 6, '0') "
                "WHERE case_number IS NULL"
            )
        )
        await conn.execute(
            text(
                "UPDATE artifacts "
                "SET public_ref = nextval('artifact_ref_seq') "
                "WHERE public_ref IS NULL"
            )
        )
        await conn.execute(
            text("CREATE UNIQUE INDEX IF NOT EXISTS ix_tickets_case_number ON tickets(case_number)")
        )
        await conn.execute(
            text("CREATE UNIQUE INDEX IF NOT EXISTS ix_artifacts_public_ref ON artifacts(public_ref)")
        )

    await _seed_support_account()


async def _seed_support_account():
    from models import User, UserRole
    from utils.auth import hash_password

    async with AsyncSessionLocal() as session:
        result = await session.execute(
            text("SELECT id FROM users WHERE username = :username"),
            {"username": settings.support_username},
        )
        existing_user_id = result.scalar_one_or_none()

        password = settings.support_password
        generated_password = None
        if not password:
            generated_password = secrets.token_urlsafe(12)
            password = generated_password

        if existing_user_id:
            user = await session.get(User, existing_user_id)
            user.email = settings.support_email
            if settings.support_password:
                user.hashed_password = hash_password(password)
            user.role = UserRole.agent
            user.workspace = "operations"
            user.queue_scope = "all"
            user.access_level = max(user.access_level, 5)
            await session.commit()
            return

        support_user = User(
            username=settings.support_username,
            email=settings.support_email,
            hashed_password=hash_password(password),
            role=UserRole.agent,
            access_level=5,
            workspace="operations",
            queue_scope="all",
        )
        session.add(support_user)
        await session.commit()

        if generated_password:
            print(
                "Seeded support account credentials:",
                f"username={settings.support_username}",
                f"password={generated_password}",
                flush=True,
            )
