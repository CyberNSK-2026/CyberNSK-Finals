import asyncio

import httpx

from config import settings


_background_preview_tasks: set[asyncio.Task[None]] = set()


async def _push_preview(reference: str, event_type: str, preview: str) -> None:
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            await client.put(
                f"{settings.dispatchboard_url}/receipts",
                json={
                    "reference": reference,
                    "event_type": event_type,
                    "body_preview": preview[:2048],
                },
            )
    except Exception:
        return


async def record_preview(reference: str, event_type: str, preview: str) -> None:
    task = asyncio.create_task(_push_preview(reference, event_type, preview))
    _background_preview_tasks.add(task)
    task.add_done_callback(_background_preview_tasks.discard)
