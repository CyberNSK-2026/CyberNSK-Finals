"""Нейтральные имена пользователей и чеклистов — без шаблонов ``u_*`` / ``chk_*``."""

from __future__ import annotations

import secrets
from typing import Tuple

_FIRST = (
    "Alex",
    "Jordan",
    "Morgan",
    "Riley",
    "Casey",
    "Quinn",
    "Jamie",
    "Drew",
    "Skyler",
    "Reese",
    "Taylor",
    "Cameron",
    "Avery",
    "Rowan",
    "Sage",
)

_LAST = (
    "Nguyen",
    "Patel",
    "Kowalski",
    "Silva",
    "Martinez",
    "Okafor",
    "Fischer",
    "Tanaka",
    "Berg",
    "Lindqvist",
    "Novak",
    "Costa",
    "Yilmaz",
    "Park",
    "Haddad",
)

# Домены только синтаксически валидные под CheckD ``EmailValidator`` (не проверяем MX).
_EMAIL_DOMAINS = (
    "posthaven.net",
    "deskrelay.io",
    "inboxvault.dev",
    "syncflow.app",
    "ledgerlane.org",
    "bundletrack.co",
    "archivetea.com",
    "draftpulse.net",
    "queuebeam.io",
    "sheetstack.dev",
    "foldernest.app",
    "cacheport.org",
    "batchline.co",
    "mirrorvault.net",
    "vaultrelay.io",
    "inboxtrail.dev",
    "deskanchor.com",
    "ledgerdrop.net",
    "syncpatch.io",
    "archivemint.dev",
)

_LOCAL = (
    "desk",
    "ledger",
    "vault",
    "inbox",
    "archive",
    "draft",
    "bundle",
    "sheet",
    "folder",
    "cache",
    "queue",
    "batch",
    "stack",
    "index",
    "mirror",
)

_CHECKLIST = (
    "Q4 office supply review",
    "Vendor onboarding checklist",
    "Release gate — staging",
    "Weekly safety walkthrough",
    "Asset handover — IT",
    "Contract renewal prep",
    "Incident postmortem items",
    "New hire first week",
    "Facilities winter prep",
    "Budget variance follow-up",
    "Audit evidence collection",
    "Sprint exit criteria",
    "Data retention review",
    "Access review — contractors",
    "Travel pre-approval",
)

_CHECKLIST_DESC = (
    "Internal use only.",
    "Please complete all sections.",
    "Owner updates weekly.",
    "Escalate blockers to ops.",
    "Attach receipts where noted.",
)

_FILE_STEM = (
    "minutes",
    "attachment",
    "export",
    "backup",
    "snapshot",
    "summary",
    "draft_copy",
    "notes",
    "packing_list",
    "receipt_scan",
)

_Q_TITLE = (
    "Confirm receipt",
    "Additional context",
    "Follow-up item",
    "Sign-off required",
    "Details",
    "Comments",
    "Reference",
    "Acknowledgement",
)


def random_display_user() -> str:
    return f"{secrets.choice(_FIRST)} {secrets.choice(_LAST)}"


def random_email() -> str:
    """Случайный локальный префикс и случайный домен из пула (regex CheckD)."""
    local = f"{secrets.choice(_LOCAL)}{secrets.randbelow(90000) + 10000}"
    return f"{local}@{secrets.choice(_EMAIL_DOMAINS)}"


def random_checklist_title() -> str:
    base = secrets.choice(_CHECKLIST)
    salt = secrets.randbelow(900) + 100
    return f"{base} ({salt})"


def random_checklist_description() -> str:
    return secrets.choice(_CHECKLIST_DESC)


def random_filename(ext: str = "txt") -> str:
    stem = secrets.choice(_FILE_STEM)
    n = secrets.randbelow(90000) + 10000
    return f"{stem}_{n}.{ext.lstrip('.')}"


def random_question_title() -> str:
    return secrets.choice(_Q_TITLE)


def random_q_name() -> str:
    """Короткий идентификатор поля вопроса (``q_name``), не человекочитаемый."""
    alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
    return "".join(secrets.choice(alphabet) for _ in range(10))


def slot_question_labels() -> Tuple[str, str]:
    """(q_name, title) для скрытого чеклиста: тело флага в ``description``."""
    return random_q_name(), random_question_title()


def smoke_pair_labels() -> Tuple[Tuple[str, str, str], Tuple[str, str, str]]:
    """Два вопроса smoke: (q_name, title, description) × 2."""
    bool_title = secrets.choice(("Ready to proceed?", "Pre-check complete?", "Gate cleared?"))
    text_title = secrets.choice(("Notes", "Remarks", "Additional info"))
    return (
        (random_q_name(), bool_title, "yes / no"),
        (random_q_name(), text_title, "free text"),
    )


def flag_prompt_question() -> Tuple[str, str, str]:
    """(q_name, title, description) для вопроса, ответом которого служит флаг (v3/v4)."""
    qn = random_q_name()
    title = secrets.choice(
        (
            "Compliance confirmation",
            "Reference token",
            "Verification string",
            "Ticket ID",
            "Case reference",
            "Approval code",
        )
    )
    desc = secrets.choice(
        (
            "Paste the value from the email.",
            "Single line only.",
            "Required for closure.",
            "As provided by finance.",
        )
    )
    return qn, title, desc
