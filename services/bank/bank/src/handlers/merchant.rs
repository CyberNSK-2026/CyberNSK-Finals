use std::env;

use actix_web::{web, HttpResponse};
use chrono::Utc;
use hmac::{Hmac, Mac};
use rusqlite::params;
use sha2::Sha256;
use uuid::Uuid;

use crate::models::{MerchantPayReq, MerchantRegisterReq, SettlementReceipt, STARTING_BALANCE};
use crate::util::fetch;
use crate::AppState;

type HmacSha256 = Hmac<Sha256>;

/// Reject payment requests whose signed timestamp is more than this many
/// seconds out of sync with wall-clock. Tight enough to stop replays,
/// loose enough to tolerate ordinary clock drift between merchants.
const MAX_TIMESTAMP_SKEW_SECS: i64 = 300;

/// Notify a merchant's webhook endpoint that a payment has settled.
///
/// Returns the HTTP status we got back (if the callback completed)
/// and, if the merchant replied with a `{receipt_id, note}` JSON
/// receipt, the `note` string from that receipt. Failures (DNS,
/// timeout, validation, non-JSON body) are absorbed silently — the
/// payment itself has already committed, and the settlement row is
/// stored regardless so reconciliation can see the miss.
async fn notify_merchant_callback(
    client: &reqwest::Client,
    url: &str,
    transaction_id: &str,
    merchant_id: &str,
    amount: f64,
    user_id: &str,
    api_key: &str,
) -> (Option<i64>, Option<String>) {
    // Dev escape hatch: when ALLOW_PRIVATE_CALLBACKS is set, accept any
    // parseable URL. Never set in production — used by the local exploit
    // suite so a test merchant webhook can run on loopback.
    let parsed = if env::var("ALLOW_PRIVATE_CALLBACKS").is_ok() {
        match reqwest::Url::parse(url) {
            Ok(u) => u,
            Err(_) => return (None, None),
        }
    } else {
        match fetch::ensure_public_url(url) {
            Ok(u) => u,
            Err(_) => return (None, None),
        }
    };

    let timestamp = Utc::now().timestamp();
    let sign_data = format!(
        "{}|{}|{:.2}|{}",
        transaction_id, merchant_id, amount, timestamp
    );
    let mut mac = HmacSha256::new_from_slice(api_key.as_bytes()).unwrap();
    mac.update(sign_data.as_bytes());
    let signature = hex::encode(mac.finalize().into_bytes());

    let payload = serde_json::json!({
        "transaction_id": transaction_id,
        "merchant_id": merchant_id,
        "amount": amount,
        "user_id": user_id,
        "timestamp": timestamp,
        "signature": signature,
    });

    match client.post(parsed).json(&payload).send().await {
        Ok(resp) => {
            let status = resp.status().as_u16() as i64;
            let note = resp
                .json::<SettlementReceipt>()
                .await
                .ok()
                .and_then(|r| r.note);
            (Some(status), note)
        }
        Err(_) => (None, None),
    }
}

pub async fn merchant_pay(
    state: web::Data<AppState>,
    body: web::Json<MerchantPayReq>,
) -> HttpResponse {
    let (api_key, callback_url) = {
        let db = state.db.lock().unwrap();
        match db.query_row(
            "SELECT api_key, callback_url FROM merchants WHERE id = ?1",
            params![&body.merchant_id],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
        ) {
            Ok(pair) => pair,
            Err(_) => {
                return HttpResponse::NotFound()
                    .json(serde_json::json!({"error": "Merchant not found"}))
            }
        }
    };

    let sign_data = format!(
        "{}|{}|{}|{:.2}",
        body.merchant_id, body.nonce, body.timestamp, body.amount
    );
    let mut mac = HmacSha256::new_from_slice(api_key.as_bytes()).unwrap();
    mac.update(sign_data.as_bytes());
    let expected = hex::encode(mac.finalize().into_bytes());

    if expected != body.signature {
        return HttpResponse::Unauthorized()
            .json(serde_json::json!({"error": "Invalid signature"}));
    }

    let ts: i64 = match body.timestamp.parse() {
        Ok(t) => t,
        Err(_) => {
            return HttpResponse::BadRequest()
                .json(serde_json::json!({"error": "Timestamp must be an integer"}))
        }
    };
    let now_ts = Utc::now().timestamp();
    if (now_ts - ts).abs() > MAX_TIMESTAMP_SKEW_SECS {
        return HttpResponse::BadRequest()
            .json(serde_json::json!({"error": "Timestamp outside accepted window"}));
    }

    if body.amount <= 0.0 {
        return HttpResponse::BadRequest()
            .json(serde_json::json!({"error": "Amount must be positive"}));
    }

    let username = body.username.trim();
    if username.len() < 2 || username.len() > 32 {
        return HttpResponse::BadRequest()
            .json(serde_json::json!({"error": "Username must be 2-32 characters"}));
    }
    if !username
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
    {
        return HttpResponse::BadRequest().json(serde_json::json!({
            "error": "Username may only contain letters, digits, _ and -"
        }));
    }

    let (tx_id, user_id, auto_created) = {
        let db = state.db.lock().unwrap();

        // Nonce uniqueness per merchant — the signature authenticates the
        // request, but a replayed valid request must not be accepted twice.
        let now_iso = Utc::now().to_rfc3339();
        let nonce_inserted = db
            .execute(
                "INSERT OR IGNORE INTO merchant_nonces (merchant_id, nonce, used_at)
                 VALUES (?1, ?2, ?3)",
                params![&body.merchant_id, &body.nonce, &now_iso],
            )
            .unwrap_or(0);
        if nonce_inserted == 0 {
            return HttpResponse::Conflict()
                .json(serde_json::json!({"error": "Nonce already used"}));
        }

        // Look up the payer by username; auto-create the account if the
        // merchant is charging a user who hasn't registered yet. This
        // placeholder account gets the standard STARTING_BALANCE and a
        // random, unknown password hash so it can participate in the
        // bank ledger immediately.
        let existing: Result<(String, f64), _> = db.query_row(
            "SELECT id, balance FROM users WHERE username = ?1",
            params![username],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, f64>(1)?)),
        );

        let (user_id, user_balance, auto_created) = match existing {
            Ok((id, bal)) => (id, bal, false),
            Err(_) => {
                let new_id = Uuid::new_v4().to_string();
                let pw_hash = hex::encode(Uuid::new_v4().as_bytes());
                match db.execute(
                    "INSERT INTO users (id, username, display_name, password_hash, balance, created_at)
                     VALUES (?1, ?2, ?2, ?3, ?4, ?5)",
                    params![new_id, username, pw_hash, STARTING_BALANCE, now_iso],
                ) {
                    Ok(_) => (new_id, STARTING_BALANCE, true),
                    Err(_) => {
                        return HttpResponse::InternalServerError().json(
                            serde_json::json!({"error": "Failed to create payer account"}),
                        )
                    }
                }
            }
        };

        if user_balance < body.amount {
            return HttpResponse::BadRequest()
                .json(serde_json::json!({"error": "Insufficient funds"}));
        }

        let tx_id = Uuid::new_v4().to_string();
        let now = Utc::now().to_rfc3339();
        let desc = body.description.as_deref().unwrap_or("Merchant payment");

        db.execute(
            "UPDATE users SET balance = balance - ?1 WHERE id = ?2",
            params![body.amount, &user_id],
        )
        .unwrap();

        db.execute(
            "INSERT INTO transactions (id, from_user, to_user, amount, comment, created_at)
             VALUES (?1, ?2, ?2, ?3, ?4, ?5)",
            params![&tx_id, &user_id, body.amount, desc, &now],
        )
        .unwrap();

        (tx_id, user_id, auto_created)
    };

    // Settlement notification to the merchant's webhook. The payment has
    // already committed; the callback is best-effort and its outcome is
    // persisted in `merchant_settlements` for reconciliation.
    let (callback_status, receipt_note) = if callback_url.is_empty() {
        (None, None)
    } else {
        notify_merchant_callback(
            &state.merchant_client,
            &callback_url,
            &tx_id,
            &body.merchant_id,
            body.amount,
            &user_id,
            &api_key,
        )
        .await
    };

    let settlement_id = Uuid::new_v4().to_string();
    {
        let db = state.db.lock().unwrap();
        let now = Utc::now().to_rfc3339();
        db.execute(
            "INSERT INTO merchant_settlements
             (id, merchant_id, transaction_id, callback_status, receipt_note, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![
                &settlement_id,
                &body.merchant_id,
                &tx_id,
                callback_status,
                receipt_note,
                &now
            ],
        )
        .ok();
    }

    HttpResponse::Ok().json(serde_json::json!({
        "transaction_id": tx_id,
        "settlement_id": settlement_id,
        "user_id": user_id,
        "user_created": auto_created,
    }))
}

pub async fn register_merchant(
    state: web::Data<AppState>,
    body: web::Json<MerchantRegisterReq>,
) -> HttpResponse {
    let db = state.db.lock().unwrap();
    let now = Utc::now().to_rfc3339();

    let exists: i64 = db
        .query_row(
            "SELECT COUNT(*) FROM merchants WHERE id = ?1",
            params![body.merchant_id],
            |row| row.get(0),
        )
        .unwrap_or(0);

    if exists > 0 {
        let stored_key: String = match db.query_row(
            "SELECT api_key FROM merchants WHERE id = ?1",
            params![body.merchant_id],
            |row| row.get(0),
        ) {
            Ok(k) => k,
            Err(_) => {
                return HttpResponse::NotFound().json(serde_json::json!({"error": "not found"}))
            }
        };
        if stored_key != body.api_key {
            return HttpResponse::Unauthorized()
                .json(serde_json::json!({"error": "Invalid API key"}));
        }
        db.execute(
            "UPDATE merchants SET callback_url = ?1 WHERE id = ?2",
            params![body.callback_url, body.merchant_id],
        )
        .ok();
        HttpResponse::Ok().json(serde_json::json!({"ok": true}))
    } else {
        db.execute(
            "INSERT INTO merchants (id, api_key, callback_url, created_at)
             VALUES (?1, ?2, ?3, ?4)",
            params![body.merchant_id, body.api_key, body.callback_url, now],
        )
        .ok();
        HttpResponse::Ok().json(serde_json::json!({
            "merchant_id": body.merchant_id,
        }))
    }
}
