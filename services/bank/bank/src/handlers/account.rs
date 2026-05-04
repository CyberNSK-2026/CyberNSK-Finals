use actix_web::{web, HttpRequest, HttpResponse};
use chrono::Utc;
use rusqlite::params;
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::auth;
use crate::models::{AccountInfo, LoginReq, ProfileUpdateReq, RegisterReq, STARTING_BALANCE};
use crate::AppState;

fn hash_password(password: &str) -> String {
    hex::encode(Sha256::digest(password.as_bytes()))
}

pub async fn register(state: web::Data<AppState>, body: web::Json<RegisterReq>) -> HttpResponse {
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
    if body.password.len() < 6 || body.password.len() > 128 {
        return HttpResponse::BadRequest()
            .json(serde_json::json!({"error": "Password must be 6-128 characters"}));
    }

    let db = state.db.lock().unwrap();
    let user_id = Uuid::new_v4().to_string();
    let pw_hash = hash_password(&body.password);
    let now = Utc::now().to_rfc3339();

    match db.execute(
        "INSERT INTO users (id, username, display_name, password_hash, balance, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![user_id, username, username, pw_hash, STARTING_BALANCE, now],
    ) {
        Ok(_) => HttpResponse::Ok().json(serde_json::json!({
            "user_id": user_id,
            "username": username,
            "starting_balance": STARTING_BALANCE
        })),
        Err(_) => {
            HttpResponse::Conflict().json(serde_json::json!({"error": "Username already taken"}))
        }
    }
}

pub async fn login(state: web::Data<AppState>, body: web::Json<LoginReq>) -> HttpResponse {
    let db = state.db.lock().unwrap();
    let pw_hash = hash_password(&body.password);

    let result = db.query_row(
        "SELECT id, username FROM users WHERE username = ?1 AND password_hash = ?2",
        params![body.username, pw_hash],
        |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
    );

    match result {
        Ok((user_id, username)) => match auth::create_token(&user_id, &username, &state.keys) {
            Ok(token) => HttpResponse::Ok().json(serde_json::json!({
                "token": token,
                "user_id": user_id,
                "username": username,
            })),
            Err(_) => HttpResponse::InternalServerError()
                .json(serde_json::json!({"error": "Failed to issue token"})),
        },
        Err(_) => {
            HttpResponse::Unauthorized().json(serde_json::json!({"error": "Invalid credentials"}))
        }
    }
}

pub async fn get_me(state: web::Data<AppState>, req: HttpRequest) -> HttpResponse {
    let claims = match auth::require_claims(&req, &state.keys) {
        Ok(c) => c,
        Err(resp) => return resp,
    };

    let db = state.db.lock().unwrap();
    let result = db.query_row(
        "SELECT id, username, display_name, balance FROM users WHERE id = ?1",
        params![claims.sub],
        |row| {
            Ok(AccountInfo {
                id: row.get(0)?,
                username: row.get(1)?,
                display_name: row.get(2)?,
                balance: row.get(3)?,
            })
        },
    );

    match result {
        Ok(info) => HttpResponse::Ok().json(info),
        Err(_) => HttpResponse::NotFound().json(serde_json::json!({"error": "Not found"})),
    }
}

pub async fn update_profile(
    state: web::Data<AppState>,
    req: HttpRequest,
    body: web::Json<ProfileUpdateReq>,
) -> HttpResponse {
    let claims = match auth::require_claims(&req, &state.keys) {
        Ok(c) => c,
        Err(resp) => return resp,
    };

    if body.display_name.len() > 64 {
        return HttpResponse::BadRequest()
            .json(serde_json::json!({"error": "Display name too long"}));
    }

    let db = state.db.lock().unwrap();
    db.execute(
        "UPDATE users SET display_name = ?1 WHERE id = ?2",
        params![body.display_name, claims.sub],
    )
    .ok();

    HttpResponse::Ok().json(serde_json::json!({"ok": true}))
}

pub async fn get_public_key(state: web::Data<AppState>) -> HttpResponse {
    let pem = String::from_utf8_lossy(state.keys.public_pem()).to_string();
    HttpResponse::Ok()
        .content_type("application/x-pem-file")
        .body(pem)
}
