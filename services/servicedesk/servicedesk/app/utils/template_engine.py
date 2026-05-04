from __future__ import annotations

from typing import Any

from jinja2 import TemplateSyntaxError
from jinja2.sandbox import SandboxedEnvironment

from config import Settings, settings


class TemplateRejected(ValueError):
    pass


class ReportRuntime:
    def __init__(self, env_settings: Settings) -> None:
        self._env_settings = env_settings

    @property
    def brand(self) -> str:
        return self._env_settings.share_link_brand

    @property
    def support_contact(self) -> str:
        return self._env_settings.support_email

    @property
    def defaults(self) -> Settings:
        return self._env_settings

    def format_header(self, ticket: Any) -> str:
        return f"Case {ticket.case_number} — {ticket.title}"

    def format_agent_line(self, user: Any) -> str:
        return f"Handled by {user.username} <{user.email}>"


class RestrictedReportRenderer:
    def __init__(self) -> None:
        self._env = SandboxedEnvironment(
            trim_blocks=True,
            lstrip_blocks=True,
            keep_trailing_newline=False,
        )

    def render(self, source: str, context: dict[str, Any]) -> str:
        if source is None:
            return ""
        template = self._env.from_string(source)
        return template.render(**context)


_renderer: RestrictedReportRenderer | None = None


def get_report_renderer() -> RestrictedReportRenderer:
    global _renderer
    if _renderer is None:
        _renderer = RestrictedReportRenderer()
    return _renderer


def build_report_context(ticket: Any, user: Any) -> dict[str, Any]:
    return {
        "ticket": ticket,
        "user": user,
        "runtime": ReportRuntime(settings),
    }


__all__ = [
    "ReportRuntime",
    "RestrictedReportRenderer",
    "TemplateRejected",
    "TemplateSyntaxError",
    "get_report_renderer",
    "build_report_context",
]
