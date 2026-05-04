use actix_web::{web, HttpRequest, HttpResponse};
use rusqlite::params;

use crate::auth;
use crate::models::{FeedNote, PublicUser};
use crate::AppState;

pub async fn list_users(state: web::Data<AppState>, req: HttpRequest) -> HttpResponse {
    if let Err(resp) = auth::require_claims(&req, &state.keys) {
        return resp;
    }

    let db = state.db.lock().unwrap();
    let mut stmt = db
        .prepare("SELECT id, username, display_name FROM users ORDER BY username")
        .unwrap();

    let users: Vec<PublicUser> = stmt
        .query_map([], |row| {
            Ok(PublicUser {
                id: row.get(0)?,
                username: row.get(1)?,
                display_name: row.get(2)?,
            })
        })
        .unwrap()
        .filter_map(|r| r.ok())
        .collect();

    HttpResponse::Ok().json(users)
}

pub async fn user_profile(
    state: web::Data<AppState>,
    req: HttpRequest,
    path: web::Path<String>,
) -> HttpResponse {
    if let Err(resp) = auth::require_claims(&req, &state.keys) {
        return resp;
    }

    let username = path.into_inner();
    let db = state.db.lock().unwrap();

    let user: PublicUser = match db.query_row(
        "SELECT id, username, display_name FROM users WHERE username = ?1",
        params![username],
        |row| {
            Ok(PublicUser {
                id: row.get(0)?,
                username: row.get(1)?,
                display_name: row.get(2)?,
            })
        },
    ) {
        Ok(u) => u,
        Err(_) => {
            return HttpResponse::NotFound().json(serde_json::json!({"error": "User not found"}))
        }
    };

    // Recent notes on the user's public profile. Archived items (listed=0)
    // are suppressed so they never appear in activity feeds; everything
    // else passes through the profile's note renderer, which handles the
    // per-note visibility presentation.
    let mut stmt = db
        .prepare(
            "SELECT n.id, u.username, n.title, n.body, n.visibility, n.created_at
             FROM notes n
             JOIN users u ON u.id = n.owner_id
             WHERE n.owner_id = ?1 AND n.listed = 1
             ORDER BY n.created_at DESC
             LIMIT 10",
        )
        .unwrap();

    let recent_notes: Vec<FeedNote> = stmt
        .query_map(params![user.id], |row| {
            Ok(FeedNote {
                id: row.get(0)?,
                owner_username: row.get(1)?,
                title: row.get(2)?,
                body: row.get(3)?,
                visibility: row.get(4)?,
                created_at: row.get(5)?,
            })
        })
        .unwrap()
        .filter_map(|r| r.ok())
        .collect();

    let tx_count: i64 = db
        .query_row(
            "SELECT COUNT(*) FROM transactions
             WHERE from_user = ?1 OR to_user = ?1",
            params![user.id],
            |row| row.get(0),
        )
        .unwrap_or(0);

    HttpResponse::Ok().json(serde_json::json!({
        "user": user,
        "stats": {
            "transaction_count": tx_count,
        },
        "recent_notes": recent_notes,
    }))
}
