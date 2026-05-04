# Silver Pear Vulnerability Notes

`Silver Pear` now uses a marketplace model with two self-registered roles:

- `seller`
- `buyer`

Flags are stored in exactly one private product note slot:

- `top`
- `middle`
- `base`

The intended attack surface is still built around buyers eventually reaching `GET /api/products/{product_id}/notes`, but in the vulnerable paths below they do so without following the honest checker flow.

## Vulnerability Overview

The service currently preserves 4 exploit chains:

1. Registration status bypass to `beauty legend`
2. `list_transaction` enumeration plus legacy transaction IDOR
3. Predictable hidden jackpot promocode
4. SQL injection in promocode apply

## Vuln 1: Registration Status Bypass

Script:

- `sploits/vuln1_status_beauty_legend.py`

Bug:

- `POST /api/register` still accepts a user-controlled `status`
- it is supposed to be normal UI-only values such as `beginner`, `niche`, `parfums maniac`, `n0se`
- but the backend also accepts `beauty legend`
- this grants `next_order_discount = 100`

Impact:

- an attacker can register as a normal `buyer`
- set `status = beauty legend`
- create an order
- purchase any target product for `final_price = 0`
- unlock private notes without paying

Exploit flow:

1. Register a random `seller`
2. Seller creates a flagged product and its private notes
3. Register an attacker as `buyer` with `status = beauty legend`
4. Attacker creates an order and adds the target product
5. Honest checkout applies the attacker-controlled `100%` next-order discount
6. Attacker reads `GET /api/products/{product_id}/notes`

## Vuln 2: List Transaction Enumeration Plus Transaction IDOR

Script:

- `sploits/vuln2_list_transaction_idor.py`

Bug:

- `GET /api/list_transaction/{id}` leaks `transaction_public_id`
- `list_transaction.id` is sequential and easy to enumerate
- `GET /api/transactions/{public_id}` does not validate ownership
- the legacy transaction response includes full unlocked product notes

Impact:

- any authenticated buyer can enumerate list item ids
- recover victim transaction UUIDs
- request the legacy transaction endpoint
- read private notes from someone else's completed purchase

Exploit flow:

1. Register a random `seller`
2. Register a victim `buyer`
3. Seller creates a flagged product
4. Victim buyer honestly purchases it
5. Register an attacker `buyer`
6. Attacker queries `GET /api/list_transaction/{id}` and recovers `transaction_public_id`
7. Attacker requests `GET /api/transactions/{public_id}`
8. Response contains the victim's unlocked notes and the flag

## Vuln 3: Predictable Hidden Jackpot Promocode

Script:

- `sploits/vuln3_predictable_wheel.py`

Bug:

- the service creates a hidden jackpot promocode for every new account
- the jackpot code is derived from service start time and Go `math/rand`
- the public storefront exposes `sale_ends_at`
- from that timestamp, an attacker can reconstruct service start time

Impact:

- a buyer can predict the hidden `100%` jackpot code for their own account
- apply it to a draft order
- complete the order for free
- unlock private notes

Exploit flow:

1. Register a random `seller`
2. Seller creates a flagged product
3. Register an attacker `buyer`
4. Attacker optionally spins the wheel once to stay close to a natural workflow
5. Attacker reads `sale_ends_at` from `/api/storefront`
6. Attacker reconstructs service start time
7. Attacker predicts the hidden jackpot code from username hash plus Go RNG state
8. Attacker applies the predicted promocode to a draft order
9. Order becomes free and notes unlock

## Vuln 4: SQL Injection In Promocode Apply

Script:

- `sploits/vuln4_promocode_sqli.py`

Bug:

- promocode lookup is built with raw string interpolation
- attacker-controlled `code` reaches SQL directly in `POST /api/orders/{order_id}/apply-promocode`

Impact:

- an attacker can inject a union-based payload
- forge a `100%` discount result row
- force order completion
- unlock private notes for a product they did not honestly pay for

Exploit flow:

1. Register a random `seller`
2. Seller creates a flagged product
3. Register an attacker `buyer`
4. Attacker creates a draft order and adds the target product
5. Attacker submits a crafted SQLi payload as promocode
6. Backend accepts a forged `100%` discount
7. Order becomes `completed`
8. Attacker requests private notes and reads the flag

## Related Files

- `checker/checker.py`
- `checker/common.py`
- `checker/api.md`
- `sploits/vuln1_status_beauty_legend.py`
- `sploits/vuln2_list_transaction_idor.py`
- `sploits/vuln3_predictable_wheel.py`
- `sploits/vuln4_promocode_sqli.py`
