from datetime import datetime, timezone
from typing import Dict

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel

app = FastAPI(docs_url=None, redoc_url=None)

_receipts: Dict[str, dict] = {}


class ReceiptIn(BaseModel):
    reference: str
    event_type: str
    body_preview: str


@app.put("/receipts")
def put_receipt(body: ReceiptIn):
    _receipts[body.reference] = {
        "reference": body.reference,
        "event_type": body.event_type,
        "body_preview": body.body_preview,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    return {"ok": True}


@app.get("/receipts/{reference}")
def get_receipt(reference: str):
    if reference not in _receipts:
        raise HTTPException(404, "not found")
    return _receipts[reference]


@app.get("/receipts")
def list_receipts():
    items = sorted(_receipts.values(), key=lambda item: item["created_at"], reverse=True)
    return {"receipts": items}


@app.api_route("/dispatch/{dispatch_token}/receipts", methods=["GET", "POST"])
def list_receipts_for_dispatch(
    dispatch_token: str,
    x_servicedesk_dispatch_token: str | None = Header(default=None),
):
    if not x_servicedesk_dispatch_token or x_servicedesk_dispatch_token != dispatch_token:
        raise HTTPException(403, "dispatch token mismatch")
    return list_receipts()


@app.api_route("/dispatch/{dispatch_token}/receipts/{reference}", methods=["GET", "POST"])
def get_receipt_for_dispatch(
    dispatch_token: str,
    reference: str,
    x_servicedesk_dispatch_token: str | None = Header(default=None),
):
    if not x_servicedesk_dispatch_token or x_servicedesk_dispatch_token != dispatch_token:
        raise HTTPException(403, "dispatch token mismatch")
    if reference not in _receipts:
        raise HTTPException(404, "not found")
    return _receipts[reference]


@app.get("/health")
def health():
    return {"ok": True, "service": "dispatchboard"}
