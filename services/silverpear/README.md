# Silver Pear

`Silver Pear` is an Attack-Defence CTF service that models a fragrance marketplace.

The private flag is stored in exactly one note slot of a product description:

- `top`
- `middle`
- `base`

Public product cards are visible to everyone. Full notes are available only through `GET /api/products/{id}/notes` after a completed purchase by a buyer.

## Service Layout

- `silverpear/` - service code copied to the vulnbox image as-is
- `checker/` - checker and shared Python client
- `sploits/` - internal exploit scripts
- `vulns.md` - vulnerability notes
- `checker/api.md` - checker flow and service API contract

## Run Locally

From `services/silverpear/silverpear`:

```bash
docker compose up -d --build
```

Backend schema changes are applied through versioned SQL files in `silverpear/migrations/`.

The service is expected to be reachable on:

```text
http://127.0.0.1:7777
```

## Marketplace Model

- The service has two self-registered roles: `seller` and `buyer`
- Sellers can create products and attach one private description to their own products
- Buyers can create orders, buy products, and unlock notes after purchase
- Brands are fixed and pre-seeded in the database
- Checker state stores:
  - `product_id`
  - `note_slot`
  - `buyer_name`
  - `buyer_password`

During `put`, the checker:

1. Registers a random seller.
2. Registers a random buyer.
3. Seller creates a product in one of the seeded brands.
4. Seller creates the description and writes the flag into one randomly chosen slot from `top/middle/base`.
5. Buyer purchases the product.
6. Checker stores state as JSON with `product_id`, `note_slot`, `buyer_name`, and `buyer_password`.

During `get`, the checker:

1. Logs in as the stored buyer.
2. Requests `GET /api/products/{product_id}/notes`.
3. Reads the slot from state.
4. Verifies the expected flag.

## Checker Flow

The checker is implemented in:

- `checker/checker.py`

Supported actions:

- `info`
- `check`
- `put`
- `get`

Exit codes:

- `101` - `OK`
- `102` - `CORRUPT`
- `103` - `MUMBLE`
- `104` - `DOWN`
- `110` - `CHECKER_ERROR`

Examples:

```bash
py -3 services/silverpear/checker/checker.py info
py -3 services/silverpear/checker/checker.py check 127.0.0.1
py -3 services/silverpear/checker/checker.py put 127.0.0.1 FLAG{demo} 1
py -3 services/silverpear/checker/checker.py get 127.0.0.1 '{"product_id":15,"note_slot":"top","buyer_name":"buyer_x","buyer_password":"pw_x"}' FLAG{demo} 1
```

The checker accepts both common invocation orders:

- `checker.py check HOST`
- `checker.py HOST check`

State format:

```json
{"product_id":15,"note_slot":"top","buyer_name":"buyer_x","buyer_password":"pw_x"}
```

The checker also accepts the compact state form:

```text
15:top:buyer_x:pw_x
```

## Quick Smoke Test

```bash
py -3 services/silverpear/checker/checker.py check 127.0.0.1
py -3 services/silverpear/checker/checker.py put 127.0.0.1 FLAG{smoke} 1
```

If `check` returns exit code `101`, the service is in the expected checker-friendly state.
