"""Текст из PDF (рендер HTML → печать) для поиска флага в чекере."""

from __future__ import annotations

import io
import re

from pypdf import PdfReader


def extract_text_from_pdf(pdf_bytes: bytes) -> str:
    reader = PdfReader(io.BytesIO(pdf_bytes))
    chunks: list[str] = []
    for page in reader.pages:
        chunks.append(page.extract_text() or "")
    return "\n".join(chunks)


def normalize_pdf_text_for_search(s: str) -> str:
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    s = re.sub(r"[\u00a0\u2000-\u200b]", " ", s)
    s = re.sub(r"\s+", " ", s)
    return s.strip()


def flag_visible_in_pdf(pdf_bytes: bytes, flag: str) -> bool:
    """Флаг как подстрока в извлечённом тексте (после нормализации пробелов)."""
    raw = extract_text_from_pdf(pdf_bytes)
    if flag in raw:
        return True
    norm = normalize_pdf_text_for_search(raw)
    nf = normalize_pdf_text_for_search(flag)
    return nf in norm if nf else False


def flag_visible_in_pdf_relaxed(pdf_bytes: bytes, flag: str) -> bool:
    """Дополнительно: без пробелов (на случай разрыва строки посередине флага)."""
    if flag_visible_in_pdf(pdf_bytes, flag):
        return True
    raw = extract_text_from_pdf(pdf_bytes)
    compact = re.sub(r"\s+", "", raw)
    return flag.replace(" ", "") in compact
