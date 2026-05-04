use chrono::Utc;
use rusqlite::{params, Connection};
use std::env;

pub fn init(conn: &Connection) {
    conn.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            username TEXT UNIQUE NOT NULL,
            display_name TEXT NOT NULL DEFAULT '',
            password_hash TEXT NOT NULL,
            balance REAL NOT NULL DEFAULT 100.0,
            created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS transactions (
            id TEXT PRIMARY KEY,
            from_user TEXT NOT NULL,
            to_user TEXT NOT NULL,
            amount REAL NOT NULL,
            comment TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            FOREIGN KEY (from_user) REFERENCES users(id),
            FOREIGN KEY (to_user) REFERENCES users(id)
        );

        CREATE TABLE IF NOT EXISTS notes (
            id TEXT PRIMARY KEY,
            owner_id TEXT NOT NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            visibility TEXT NOT NULL DEFAULT 'private',
            listed INTEGER NOT NULL DEFAULT 1,
            preview TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            FOREIGN KEY (owner_id) REFERENCES users(id)
        );

        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            sender_id TEXT NOT NULL,
            recipient_id TEXT NOT NULL,
            subject TEXT NOT NULL,
            body TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY (sender_id) REFERENCES users(id),
            FOREIGN KEY (recipient_id) REFERENCES users(id)
        );

        CREATE TABLE IF NOT EXISTS merchants (
            id TEXT PRIMARY KEY,
            api_key TEXT NOT NULL,
            callback_url TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS merchant_nonces (
            merchant_id TEXT NOT NULL,
            nonce TEXT NOT NULL,
            used_at TEXT NOT NULL,
            PRIMARY KEY (merchant_id, nonce)
        );

        CREATE TABLE IF NOT EXISTS merchant_settlements (
            id TEXT PRIMARY KEY,
            merchant_id TEXT NOT NULL,
            transaction_id TEXT NOT NULL,
            callback_status INTEGER,
            receipt_note TEXT,
            created_at TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_tx_from ON transactions(from_user);
        CREATE INDEX IF NOT EXISTS idx_tx_to ON transactions(to_user);
        CREATE INDEX IF NOT EXISTS idx_notes_owner ON notes(owner_id);
        CREATE INDEX IF NOT EXISTS idx_notes_created ON notes(created_at);
        CREATE INDEX IF NOT EXISTS idx_msg_recipient ON messages(recipient_id);
        CREATE INDEX IF NOT EXISTS idx_msg_sender ON messages(sender_id);
    ",
    )
    .expect("create tables");

    let merchant_key = env::var("MERCHANT_KEY").unwrap_or_else(|_| "merchant-key-2024-ctf".into());
    let now = Utc::now().to_rfc3339();
    conn.execute(
        "INSERT OR IGNORE INTO merchants (id, api_key, callback_url, created_at)
         VALUES (?1, ?2, ?3, ?4)",
        params!["shop-001", merchant_key, "", now],
    )
    .ok();

    log::info!("Database ready");
}
