#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import sys
import traceback
import urllib.error

from common import (
    FlagState,
    HttpError,
    SilverPearClient,
    create_and_purchase_flag_product,
    create_product_with_flag,
    register_and_login,
)

OK = 101
CORRUPT = 102
MUMBLE = 103
DOWN = 104
CHECKER_ERROR = 110


class CorruptError(RuntimeError):
    pass


class MumbleError(RuntimeError):
    pass


def die(code: int, message: str) -> int:
    print(message)
    return code


def parse_invocation(argv: list[str]) -> tuple[str, str | None, list[str]]:
    args = argv[1:]
    if not args:
        raise MumbleError("missing checker action")

    actions = {"info", "check", "put", "get"}
    action_index = None
    for index, token in enumerate(args[:2]):
        if token in actions:
            action_index = index
            break
    if action_index is None:
        raise MumbleError("unsupported checker action")

    action = args[action_index]
    remaining = args[:action_index] + args[action_index + 1 :]

    if action == "info":
        return action, None, remaining
    if not remaining:
        raise MumbleError("missing host argument")

    host = remaining[0]
    extra = remaining[1:]
    return action, host, extra


def checker_info() -> int:
    print(
        json.dumps(
            {
                "name": "silverpear",
                "vulns": 4,
                "state": "json:{product_id,note_slot,buyer_name,buyer_password}",
                "public_flag_description": "Flag is stored in one of the private product note slots.",
            },
            sort_keys=True,
        )
    )
    return OK


def checker_check(host: str) -> int:
    health = SilverPearClient(host).health()
    if health.get("status") != "ok":
        raise MumbleError(f"unexpected health payload: {health}")

    seller, _, _ = register_and_login(host, prefix="seller_check", role="seller")
    created = create_product_with_flag(seller, "FLAG{check_dummy}", price=900, title_prefix="CHECK")
    product_id = int(created["product"]["id"])
    slot = created["note_slot"]

    buyer, username, _ = register_and_login(host, prefix="buyer_check", role="buyer")
    status, locked = buyer.get_notes(product_id, expected=(403,))
    if status != 403 or locked.get("error") != "product notes are locked":
        raise MumbleError(f"notes lock is unstable: {locked}")

    order = buyer.create_order()["order"]
    order = buyer.add_order_item(order["public_id"], product_id)["order"]
    order = buyer.checkout_order(order["public_id"])["order"]
    if order["status"] != "completed":
        raise MumbleError(f"order not completed: {order}")
    if order["final_price"] != 900:
        raise MumbleError(f"unexpected final price for honest buyer {username}: {order}")

    notes = buyer.get_notes(product_id)[1]["notes"]
    if notes[slot] != "FLAG{check_dummy}":
        raise MumbleError(f"unexpected notes payload: {notes}")

    return die(OK, "service is healthy")


def _extract_put_flag_and_vuln(extra: list[str]) -> tuple[str, str]:
    if len(extra) < 2:
        raise MumbleError("put requires at least FLAG and VULN")
    return extra[-2], extra[-1]


def _extract_get_state_flag_vuln(extra: list[str]) -> tuple[str, str, str]:
    if len(extra) < 3:
        raise MumbleError("get requires STATE FLAG VULN")
    return extra[0], extra[1], extra[2]


def checker_put(host: str, extra: list[str]) -> int:
    flag, _vuln = _extract_put_flag_and_vuln(extra)
    seller, _, _ = register_and_login(host, prefix="seller_put", role="seller")
    buyer, buyer_name, buyer_password = register_and_login(host, prefix="buyer_put", role="buyer")
    created = create_and_purchase_flag_product(seller, buyer, flag, price=1800, title_prefix="PUT")
    state = FlagState(
        product_id=created["product_id"],
        note_slot=created["note_slot"],
        buyer_name=buyer_name,
        buyer_password=buyer_password,
    )
    print(state.dumps())
    return OK


def checker_get(host: str, extra: list[str]) -> int:
    raw_state, flag, _vuln = _extract_get_state_flag_vuln(extra)
    state = FlagState.loads(raw_state)

    buyer = SilverPearClient(host)
    buyer.login(state.buyer_name, state.buyer_password)
    status, payload = buyer.get_notes(state.product_id, expected=(200, 404))
    if status == 404:
        raise CorruptError(f"product {state.product_id} not found")

    notes = payload["notes"]
    actual = notes.get(state.note_slot)
    if actual != flag:
        raise CorruptError(f"flag not found in {state.note_slot}: {notes}")

    return die(OK, "flag is present")


def main(argv: list[str]) -> int:
    action, host, extra = parse_invocation(argv)
    if action == "info":
        return checker_info()
    if action == "check":
        return checker_check(host or "")
    if action == "put":
        return checker_put(host or "", extra)
    if action == "get":
        return checker_get(host or "", extra)
    raise MumbleError(f"unsupported action {action}")


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except CorruptError as exc:
        sys.exit(die(CORRUPT, str(exc)))
    except MumbleError as exc:
        sys.exit(die(MUMBLE, str(exc)))
    except (urllib.error.URLError, TimeoutError) as exc:
        sys.exit(die(DOWN, f"network error: {exc}"))
    except HttpError as exc:
        if exc.status >= 500:
            sys.exit(die(DOWN, str(exc)))
        sys.exit(die(MUMBLE, str(exc)))
    except Exception as exc:
        print(f"checker internal error: {exc}")
        traceback.print_exc()
        sys.exit(CHECKER_ERROR)
