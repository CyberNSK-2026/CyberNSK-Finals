use actix_web::{web, HttpRequest, HttpResponse};
use chrono::Utc;
use rusqlite::params;
use uuid::Uuid;

use crate::auth;
use crate::models::{MessageInfo, MessageSendReq, MessagesQuery};
use crate::AppState;

pub async fn send_message(
    state: web::Data<AppState>,
    req: HttpRequest,
    body: web::Json<MessageSendReq>,
) -> HttpResponse {
    let claims = match auth::require_claims(&req, &state.keys) {
        Ok(c) => c,
        Err(resp) => return resp,
    };

    if body.subject.is_empty() || body.subject.len() > 128 {
        return HttpResponse::BadRequest()
            .json(serde_json::json!({"error": "Subject must be 1-128 chars"}));
    }
    if body.body.is_empty() || body.body.len() > 4096 {
        return HttpResponse::BadRequest()
            .json(serde_json::json!({"error": "Body must be 1-4096 chars"}));
    }

    let recipient_id = if body.to.len() == 36 && body.to.contains('-') {
        body.to.clone()
    } else {
        let db = state.db.lock().unwrap();
        match db.query_row(
            "SELECT id FROM users WHERE username = ?1",
            params![body.to],
            |row| row.get::<_, String>(0),
        ) {
            Ok(id) => id,
            Err(_) => {
                return HttpResponse::NotFound()
                    .json(serde_json::json!({"error": "Recipient not found"}))
            }
        }
    };

    let db = state.db.lock().unwrap();
    let msg_id = Uuid::new_v4().to_string();
    let now = Utc::now().to_rfc3339();

    db.execute(
        "INSERT INTO messages (id, sender_id, recipient_id, subject, body, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![
            msg_id,
            claims.sub,
            recipient_id,
            body.subject,
            body.body,
            now
        ],
    )
    .unwrap();

    HttpResponse::Ok().json(serde_json::json!({
        "id": msg_id,
    }))
}

pub async fn list_messages(
    state: web::Data<AppState>,
    req: HttpRequest,
    query: web::Query<MessagesQuery>,
) -> HttpResponse {
    let claims = match auth::require_claims(&req, &state.keys) {
        Ok(c) => c,
        Err(resp) => return resp,
    };

    let folder = query.folder.as_deref().unwrap_or("inbox");
    let limit = query.limit.unwrap_or(50).clamp(1, 200);

    let where_clause = match folder {
        "inbox" => "m.recipient_id = ?1",
        "sent" => "m.sender_id = ?1",
        "all" => "m.recipient_id = ?1 OR m.sender_id = ?1",
        _ => {
            return HttpResponse::BadRequest().json(serde_json::json!({"error": "Invalid folder"}))
        }
    };

    let sql = format!(
        "SELECT m.id, m.sender_id, m.recipient_id, su.username, ru.username,
                m.subject, m.body, m.created_at
         FROM messages m
         JOIN users su ON su.id = m.sender_id
         JOIN users ru ON ru.id = m.recipient_id
         WHERE {}
         ORDER BY m.created_at DESC
         LIMIT ?2",
        where_clause
    );

    let db = state.db.lock().unwrap();
    let mut stmt = match db.prepare(&sql) {
        Ok(s) => s,
        Err(_) => {
            return HttpResponse::InternalServerError()
                .json(serde_json::json!({"error": "Query error"}))
        }
    };

    let msgs: Vec<MessageInfo> = stmt
        .query_map(params![claims.sub, limit], |row| {
            Ok(MessageInfo {
                id: row.get(0)?,
                sender_id: row.get(1)?,
                recipient_id: row.get(2)?,
                sender_username: row.get(3)?,
                recipient_username: row.get(4)?,
                subject: row.get(5)?,
                body: row.get(6)?,
                created_at: row.get(7)?,
            })
        })
        .unwrap()
        .filter_map(|r| r.ok())
        .collect();

    HttpResponse::Ok().json(msgs)
}
