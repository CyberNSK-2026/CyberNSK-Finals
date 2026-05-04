use actix_web::{web, HttpRequest, HttpResponse};
use rusqlite::params;
use serde::Deserialize;

use crate::auth;
use crate::util::bucket::BucketSpec;
use crate::AppState;

#[derive(Deserialize)]
pub struct StatsQuery {
    pub group_by: Option<String>,
    pub period: Option<String>,
}

pub async fn transaction_stats(
    state: web::Data<AppState>,
    req: HttpRequest,
    query: web::Query<StatsQuery>,
) -> HttpResponse {
    let claims = match auth::require_claims(&req, &state.keys) {
        Ok(c) => c,
        Err(resp) => return resp,
    };

    let spec = match query.group_by.as_deref() {
        Some(raw) => match BucketSpec::parse(raw) {
            Ok(s) => s,
            Err(e) => {
                return HttpResponse::BadRequest()
                    .json(serde_json::json!({"error": format!("invalid group_by: {}", e)}));
            }
        },
        None => BucketSpec::default_day(),
    };

    let group_expr = spec.as_sql();

    let period_filter = match query.period.as_deref() {
        Some("week") => "AND t.created_at >= datetime('now', '-7 days')",
        Some("month") => "AND t.created_at >= datetime('now', '-30 days')",
        _ => "",
    };

    let sql = format!(
        "SELECT {} as bucket, COUNT(*) as count, SUM(t.amount) as total \
         FROM transactions t \
         JOIN users fu ON fu.id = t.from_user \
         JOIN users tu ON tu.id = t.to_user \
         WHERE (t.from_user = ?1 OR t.to_user = ?1) {} \
         GROUP BY bucket ORDER BY bucket DESC LIMIT 100",
        group_expr, period_filter
    );

    let db = state.db.lock().unwrap();
    let mut stmt = match db.prepare(&sql) {
        Ok(s) => s,
        Err(_) => {
            return HttpResponse::InternalServerError()
                .json(serde_json::json!({"error": "Query error"}))
        }
    };

    let rows = stmt.query_map(params![claims.sub], |row| {
        Ok(serde_json::json!({
            "bucket": row.get::<_, String>(0).unwrap_or_default(),
            "count": row.get::<_, i64>(1).unwrap_or(0),
            "total": row.get::<_, f64>(2).unwrap_or(0.0),
        }))
    });

    match rows {
        Ok(r) => {
            let stats: Vec<_> = r.filter_map(|x| x.ok()).collect();
            HttpResponse::Ok().json(stats)
        }
        Err(_) => {
            HttpResponse::InternalServerError().json(serde_json::json!({"error": "Stats failed"}))
        }
    }
}
