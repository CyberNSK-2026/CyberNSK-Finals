# Silver Pear Checker And API Contract

## Checker Model

### Roles Used By The Checker

- The checker registers one random `seller`
- The checker registers one random `buyer`
- The seller creates the flagged product
- The buyer purchases it and is later reused in `get`

### Stored State

The checker stores:

```json
{
  "product_id": 15,
  "note_slot": "top",
  "buyer_name": "buyer_x",
  "buyer_password": "pw_x"
}
```

Compact form:

```text
15:top:buyer_x:pw_x
```

### Honest Flow

#### `check`

1. Verify `/api/health`
2. Register a seller and create a product with private notes
3. Register a buyer
4. Confirm notes are locked before purchase
5. Buy the product as buyer
6. Confirm notes unlock after purchase

#### `put`

1. Register a random seller
2. Register a random buyer
3. Seller creates a product in a seeded brand
4. Seller writes the flag into one private note slot
5. Buyer purchases the product
6. Checker stores product id, note slot, and buyer credentials

#### `get`

1. Load checker state
2. Log in as the stored buyer
3. Request `GET /api/products/{product_id}/notes`
4. Verify that the expected slot contains the flag

## Service API

### Domain Rules

- The service has two roles: `seller` and `buyer`
- Brands are fixed and pre-seeded
- Sellers can create products only inside the seeded brands
- Sellers can attach exactly one private description to each of their own products
- Buyers can create orders and unlock notes only after a completed purchase
- Product cards are public
- Full notes from `description` stay private until a buyer purchases the product
- Auth responses keep the legacy `buyer` JSON key even when the account role is `seller`

### Shared JSON Objects

#### Account Payload

```json
{
  "id": 7,
  "name": "alice",
  "role": "buyer",
  "status": "beginner",
  "balance": 2000,
  "total_spent": 0,
  "next_order_discount": 0,
  "wheel_used": false,
  "created_at": "2026-04-20T07:35:00Z"
}
```

#### Brand

```json
{
  "id": 2,
  "name": "Nocturne House"
}
```

#### Product Card

```json
{
  "id": 15,
  "brand_id": 2,
  "brand_name": "Nocturne House",
  "title": "Ashen Citrus",
  "short_description": "Dry citrus perfume with cold mineral undertones.",
  "price": 12500
}
```

#### Product Notes

```json
{
  "product_id": 15,
  "description": "A layered perfume that opens bright and ends on a heavy dark accord.",
  "top": "bergamot, grapefruit zest",
  "middle": "iris, violet leaf",
  "base": "FLAG{example}"
}
```

### Public Endpoints

#### `GET /api/health`

Returns a basic health payload.

#### `GET /api/storefront`

Returns the public catalog grouped by brand and the sale timer.

#### `GET /api/brands`

Returns the fixed list of available brands.

#### `GET /api/products/{product_id}`

Returns the public card for one product.

### Auth Endpoints

#### `POST /api/register`

Request:

```json
{
  "name": "alice",
  "password": "hunter2",
  "role": "seller",
  "status": "beginner"
}
```

Allowed roles:

- `seller`
- `buyer`

Regular UI values for `status`:

- `beginner`
- `niche`
- `parfums maniac`
- `n0se`

Response:

```json
{
  "buyer": {
    "id": 7,
    "name": "alice",
    "role": "seller",
    "status": "beginner",
    "balance": 2000,
    "total_spent": 0,
    "next_order_discount": 0,
    "wheel_used": false,
    "created_at": "2026-04-20T07:35:00Z"
  }
}
```

Notes:

- Registration still accepts `status`
- The intended vulnerability is that `beauty legend` is accepted through this request path and grants a `100%` next-order discount

#### `POST /api/login`

Logs the account in and sets a session cookie.

#### `POST /api/logout`

Clears the session cookie.

#### `GET /api/me`

Returns the current authenticated account under the legacy `buyer` key.

### Seller Endpoints

Seller endpoints require `role = seller`.

#### `POST /api/products`

Request:

```json
{
  "brand_id": 2,
  "title": "Ashen Citrus",
  "short_description": "Dry citrus perfume with cold mineral undertones.",
  "price": 12500
}
```

Response:

```json
{
  "product": {
    "id": 15,
    "brand_id": 2,
    "brand_name": "Nocturne House",
    "title": "Ashen Citrus",
    "short_description": "Dry citrus perfume with cold mineral undertones.",
    "price": 12500
  }
}
```

#### `POST /api/products/{product_id}/description`

Adds the private notes for a product owned by the current seller.

### Buyer Endpoints

Buyer endpoints require `role = buyer`.

#### `POST /api/wheel/spin`

Runs the discount wheel for the current buyer.

#### `POST /api/orders`

Creates a new buyer draft order.

#### `POST /api/orders/{order_id}/items`

Adds a product to a draft order.

#### `GET /api/orders`

Lists the buyer's own orders.

#### `GET /api/orders/{order_id}`

Returns the buyer's own order details.

#### `POST /api/orders/{order_id}/checkout`

Completes a draft order using buyer balance and discount state.

#### `POST /api/orders/{order_id}/apply-promocode`

Applies a promocode to a draft order.

#### `GET /api/products/{product_id}/notes`

Returns the private notes only if the current buyer has already purchased the product.
