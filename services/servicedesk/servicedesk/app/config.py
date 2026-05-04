import secrets

from pydantic import Field
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql+asyncpg://sd:sd_pass@localhost/servicedesk"
    dispatchboard_url: str = "http://dispatchboard:8081"
    upload_dir: str = "/uploads"

    jwt_secret: str = Field(default_factory=lambda: secrets.token_urlsafe(32))
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60 * 24 * 7

    support_username: str = "support"
    support_email: str = "support@servicedesk.local"
    support_password: str | None = None

    share_link_brand: str = "servicedesk.local"
    share_link_revision: str = "v2"
    portal_base_url: str = "http://localhost:8080"

    discord_webhook_url: str | None = "https://example.com"
    slack_webhook_url: str | None = "https://example.com"
    teams_webhook_url: str | None = "https://example.com"
    generic_webhook_url: str | None = "https://example.com"
    webhook_request_timeout: float = 10.0
    webhook_preview_bytes: int = 4096
    webhook_follow_redirects: bool = True

    class Config:
        env_file = ".env"


settings = Settings()
