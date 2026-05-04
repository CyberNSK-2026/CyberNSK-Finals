use actix_web::{web, HttpResponse};

use crate::AppState;

pub async fn metrics(state: web::Data<AppState>) -> HttpResponse {
    let db = state.db.lock().unwrap();

    let user_count: i64 = db
        .query_row("SELECT COUNT(*) FROM users", [], |row| row.get(0))
        .unwrap_or(0);
    let tx_count: i64 = db
        .query_row("SELECT COUNT(*) FROM transactions", [], |row| row.get(0))
        .unwrap_or(0);
    let msg_count: i64 = db
        .query_row("SELECT COUNT(*) FROM messages", [], |row| row.get(0))
        .unwrap_or(0);

    let mut output = String::new();
    output.push_str("# HELP bank_users_total Total registered users\n");
    output.push_str("# TYPE bank_users_total gauge\n");
    output.push_str(&format!("bank_users_total {}\n", user_count));
    output.push_str("# HELP bank_transactions_total Total transactions\n");
    output.push_str("# TYPE bank_transactions_total gauge\n");
    output.push_str(&format!("bank_transactions_total {}\n", tx_count));
    output.push_str("# HELP bank_messages_total Total messages\n");
    output.push_str("# TYPE bank_messages_total gauge\n");
    output.push_str(&format!("bank_messages_total {}\n", msg_count));

    output.push_str("\n# Recent activity log\n");
    let mut stmt = db
        .prepare(
            "SELECT m.created_at, su.username, ru.username, m.subject, m.body
             FROM messages m
             JOIN users su ON su.id = m.sender_id
             JOIN users ru ON ru.id = m.recipient_id
             ORDER BY m.created_at DESC LIMIT 100",
        )
        .unwrap();
    let rows = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, String>(4)?,
            ))
        })
        .unwrap();
    for r in rows.flatten() {
        output.push_str(&format!(
            "msg ts={} from={} to={} subject={:?} body={:?}\n",
            r.0, r.1, r.2, r.3, r.4
        ));
    }

    HttpResponse::Ok()
        .content_type("text/plain; version=0.0.4")
        .body(output)
}

pub async fn health() -> HttpResponse {
    HttpResponse::Ok().body("ok")
}
