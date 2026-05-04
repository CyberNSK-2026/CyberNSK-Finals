use actix_web::{web, HttpRequest, HttpResponse};
use chrono::Utc;
use rusqlite::params;
use uuid::Uuid;

use crate::auth;
use crate::models::{NoteCreateReq, NoteIdQuery, NoteInfo, PreviewReq, PREVIEW_FEE_PRIVATE};
use crate::util::{fetch, gate};
use crate::AppState;

pub async fn create_note(
    state: web::Data<AppState>,
    req: HttpRequest,
    body: web::Json<NoteCreateReq>,
) -> HttpResponse {
    let claims = match auth::require_claims(&req, &state.keys) {
        Ok(c) => c,
        Err(resp) => return resp,
    };

    if body.title.is_empty() || body.title.len() > 128 {
        return HttpResponse::BadRequest()
            .json(serde_json::json!({"error": "Title must be 1-128 chars"}));
    }
    if body.body.is_empty() || body.body.len() > 4096 {
        return HttpResponse::BadRequest()
            .json(serde_json::json!({"error": "Body must be 1-4096 chars"}));
    }

    let visibility = match body.visibility.as_deref().unwrap_or("private") {
        "private" => "private",
        "public" => "public",
        _ => "private",
    };

    let db = state.db.lock().unwrap();
    let note_id = Uuid::new_v4().to_string();
    let now = Utc::now().to_rfc3339();

    // Newly-created notes are listed in the owner's activity feed by
    // default. Archiving a note later flips `listed` to 0 so it drops
    // out of profile timelines without actually deleting the content.
    db.execute(
        "INSERT INTO notes (id, owner_id, title, body, visibility, listed, preview, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, 1, '', ?6)",
        params![note_id, claims.sub, body.title, body.body, visibility, now],
    )
    .unwrap();

    HttpResponse::Ok().json(serde_json::json!({
        "id": note_id,
        "visibility": visibility,
    }))
}

pub async fn get_note(
    state: web::Data<AppState>,
    req: HttpRequest,
    query: web::Query<NoteIdQuery>,
) -> HttpResponse {
    let claims = match auth::require_claims(&req, &state.keys) {
        Ok(c) => c,
        Err(resp) => return resp,
    };

    let db = state.db.lock().unwrap();
    let result = db.query_row(
        "SELECT n.id, n.owner_id, u.username, n.title, n.body, n.visibility, n.preview, n.created_at
         FROM notes n JOIN users u ON u.id = n.owner_id
         WHERE n.id = ?1",
        params![query.id],
        |row| {
            Ok(NoteInfo {
                id: row.get(0)?,
                owner_id: row.get(1)?,
                owner_username: row.get(2)?,
                title: row.get(3)?,
                body: row.get(4)?,
                visibility: row.get(5)?,
                preview: row.get(6)?,
                created_at: row.get(7)?,
            })
        },
    );

    match result {
        Ok(note) => {
            if note.visibility == "private" && note.owner_id != claims.sub {
                return HttpResponse::Forbidden()
                    .json(serde_json::json!({"error": "Access denied"}));
            }
            HttpResponse::Ok().json(note)
        }
        Err(_) => HttpResponse::NotFound().json(serde_json::json!({"error": "Note not found"})),
    }
}

pub async fn list_my_notes(state: web::Data<AppState>, req: HttpRequest) -> HttpResponse {
    let claims = match auth::require_claims(&req, &state.keys) {
        Ok(c) => c,
        Err(resp) => return resp,
    };

    let db = state.db.lock().unwrap();
    let mut stmt = db
        .prepare(
            "SELECT n.id, n.owner_id, u.username, n.title, n.body, n.visibility, n.preview, n.created_at
             FROM notes n JOIN users u ON u.id = n.owner_id
             WHERE n.owner_id = ?1
             ORDER BY n.created_at DESC",
        )
        .unwrap();

    let notes: Vec<NoteInfo> = stmt
        .query_map(params![claims.sub], |row| {
            Ok(NoteInfo {
                id: row.get(0)?,
                owner_id: row.get(1)?,
                owner_username: row.get(2)?,
                title: row.get(3)?,
                body: row.get(4)?,
                visibility: row.get(5)?,
                preview: row.get(6)?,
                created_at: row.get(7)?,
            })
        })
        .unwrap()
        .filter_map(|r| r.ok())
        .collect();

    HttpResponse::Ok().json(notes)
}

pub async fn note_preview(
    state: web::Data<AppState>,
    req: HttpRequest,
    body: web::Json<PreviewReq>,
) -> HttpResponse {
    let claims = match auth::require_claims(&req, &state.keys) {
        Ok(c) => c,
        Err(resp) => return resp,
    };

    // Dedupe concurrent submissions for the same note so a double-click
    // never triggers the outbound fetch twice.
    let gate_key = format!("preview:{}:{}", claims.sub, body.note_id);
    let _gate = match gate::acquire(gate_key) {
        Some(g) => g,
        None => {
            return HttpResponse::Conflict()
                .json(serde_json::json!({"error": "preview already in progress"}));
        }
    };

    // Validate the destination before we read from the DB — if the URL is
    // obviously bad we want to fail fast without touching the balance.
    let fetch_url = match fetch::ensure_public_url(&body.url) {
        Ok(u) => u,
        Err(e) => {
            return HttpResponse::BadRequest().json(serde_json::json!({"error": e}));
        }
    };

    let owner: (String, String) = {
        let db = state.db.lock().unwrap();
        match db.query_row(
            "SELECT owner_id, visibility FROM notes WHERE id = ?1",
            params![body.note_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        ) {
            Ok(t) => t,
            Err(_) => {
                return HttpResponse::NotFound()
                    .json(serde_json::json!({"error": "Note not found"}));
            }
        }
    };

    if owner.0 != claims.sub {
        return HttpResponse::Forbidden().json(serde_json::json!({"error": "Not your note"}));
    }

    if owner.1 == "private" {
        let balance: f64 = {
            let db = state.db.lock().unwrap();
            db.query_row(
                "SELECT balance FROM users WHERE id = ?1",
                params![claims.sub],
                |row| row.get(0),
            )
            .unwrap_or(0.0)
        };
        if balance < PREVIEW_FEE_PRIVATE {
            return HttpResponse::PaymentRequired().json(serde_json::json!({
                "error": "Insufficient balance for preview",
                "required": PREVIEW_FEE_PRIVATE,
                "balance": balance
            }));
        }
    }

    let response = match state.http_client.get(fetch_url).send().await {
        Ok(r) => r,
        Err(e) => {
            return HttpResponse::BadGateway()
                .json(serde_json::json!({"error": format!("Fetch failed: {}", e)}));
        }
    };

    let text = response.text().await.unwrap_or_default();
    let preview_text = extract_title_or_snippet(&text);

    if owner.1 == "private" {
        let db = state.db.lock().unwrap();
        db.execute(
            "UPDATE users SET balance = balance - ?1 WHERE id = ?2",
            params![PREVIEW_FEE_PRIVATE, claims.sub],
        )
        .ok();
    }

    let db = state.db.lock().unwrap();
    db.execute(
        "UPDATE notes SET preview = ?1 WHERE id = ?2",
        params![preview_text, body.note_id],
    )
    .ok();

    HttpResponse::Ok().json(serde_json::json!({
        "preview": preview_text,
    }))
}

fn extract_title_or_snippet(html: &str) -> String {
    if let Some(start) = html.to_lowercase().find("<title>") {
        if let Some(end) = html[start + 7..].to_lowercase().find("</title>") {
            let title = &html[start + 7..start + 7 + end];
            return title.trim().chars().take(500).collect();
        }
    }
    html.trim().chars().take(500).collect()
}
