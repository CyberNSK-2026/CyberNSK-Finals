CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS brand (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    is_marketplace_brand BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS buyer (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('buyer', 'seller')),
    status TEXT NOT NULL CHECK (status IN ('beginner', 'niche', 'parfums maniac', 'n0se', 'beauty legend')),
    balance INTEGER NOT NULL DEFAULT 2000 CHECK (balance >= 0),
    total_spent INTEGER NOT NULL DEFAULT 0 CHECK (total_spent >= 0),
    next_order_discount INTEGER NOT NULL DEFAULT 0 CHECK (next_order_discount BETWEEN 0 AND 100),
    wheel_used BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS product (
    id BIGSERIAL PRIMARY KEY,
    brand_id BIGINT NOT NULL REFERENCES brand(id) ON DELETE RESTRICT,
    title TEXT NOT NULL,
    short_description TEXT NOT NULL,
    price INTEGER NOT NULL CHECK (price >= 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_by BIGINT REFERENCES buyer(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS description (
    id BIGSERIAL PRIMARY KEY,
    product_id BIGINT NOT NULL UNIQUE REFERENCES product(id) ON DELETE CASCADE,
    description TEXT NOT NULL,
    top TEXT NOT NULL,
    middle TEXT NOT NULL,
    base TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS promocode (
    id BIGSERIAL PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    discount_percent INTEGER NOT NULL CHECK (discount_percent BETWEEN 0 AND 100),
    owner_id BIGINT REFERENCES buyer(id) ON DELETE CASCADE,
    used_by BIGINT REFERENCES buyer(id) ON DELETE SET NULL,
    is_one_time BOOLEAN NOT NULL DEFAULT TRUE,
    source TEXT NOT NULL CHECK (source IN ('wheel', 'admin', 'marketing')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    used_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS purchase_order (
    id BIGSERIAL PRIMARY KEY,
    public_id UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    buyer_id BIGINT NOT NULL REFERENCES buyer(id) ON DELETE CASCADE,
    promocode_id BIGINT REFERENCES promocode(id) ON DELETE SET NULL,
    status TEXT NOT NULL CHECK (status IN ('draft', 'completed', 'cancelled')),
    total_price INTEGER NOT NULL DEFAULT 0 CHECK (total_price >= 0),
    final_price INTEGER NOT NULL DEFAULT 0 CHECK (final_price >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS list_transaction (
    id BIGSERIAL PRIMARY KEY,
    transaction_id BIGINT NOT NULL REFERENCES purchase_order(id) ON DELETE CASCADE,
    product_id BIGINT NOT NULL REFERENCES product(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price INTEGER NOT NULL CHECK (unit_price >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_buyer_role ON buyer(role);
CREATE INDEX IF NOT EXISTS idx_product_brand_id ON product(brand_id);
CREATE INDEX IF NOT EXISTS idx_description_product_id ON description(product_id);
CREATE INDEX IF NOT EXISTS idx_promocode_owner_id ON promocode(owner_id);
CREATE INDEX IF NOT EXISTS idx_promocode_used_by ON promocode(used_by);
CREATE INDEX IF NOT EXISTS idx_purchase_order_buyer_id ON purchase_order(buyer_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_status ON purchase_order(status);
CREATE INDEX IF NOT EXISTS idx_list_transaction_transaction_id ON list_transaction(transaction_id);
CREATE INDEX IF NOT EXISTS idx_list_transaction_product_id ON list_transaction(product_id);
