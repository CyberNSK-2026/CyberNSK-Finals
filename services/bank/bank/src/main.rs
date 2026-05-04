mod auth;
mod db;
mod handlers;
mod models;
mod util;

use actix_cors::Cors;
use actix_files::{Files, NamedFile};
use actix_web::{
    dev::ServiceRequest, http::header, middleware::Logger, web, App, HttpResponse, HttpServer,
};
use rusqlite::Connection;
use std::env;
use std::sync::Mutex;

pub struct AppState {
    pub db: Mutex<Connection>,
    pub keys: auth::JwtKeys,
    pub http_client: reqwest::Client,
    pub merchant_client: reqwest::Client,
}

async fn health() -> HttpResponse {
    HttpResponse::Ok().json(serde_json::json!({
        "status": "ok",
        "service": "ctf-bank",
        "version": "3.0.0",
    }))
}

async fn serve_index() -> actix_web::Result<NamedFile> {
    Ok(NamedFile::open("./static/index.html")?)
}

fn first_header_value(
    req: &ServiceRequest,
    name: impl actix_web::http::header::AsHeaderName,
) -> Option<String> {
    req.headers()
        .get(name)?
        .to_str()
        .ok()?
        .split(',')
        .next()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.trim_matches('"').to_owned())
}

fn client_ip_for_logs(req: &ServiceRequest) -> String {
    let connection_info = req.connection_info();

    let forwarded_ip = (req.headers().contains_key(header::FORWARDED)
        || req.headers().contains_key("x-forwarded-for"))
    .then(|| connection_info.realip_remote_addr().map(str::to_owned))
    .flatten();

    forwarded_ip
        .or_else(|| first_header_value(req, "x-real-ip"))
        .or_else(|| connection_info.peer_addr().map(str::to_owned))
        .unwrap_or_else(|| "-".to_string())
}

fn access_logger(format: &str) -> Logger {
    Logger::new(format).custom_request_replace("client_ip", client_ip_for_logs)
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init();

    let (private_pem, public_pem) = auth::generate_rsa_keys();
    let keys = auth::JwtKeys::new(private_pem, public_pem);

    let conn = Connection::open("bank.db").expect("open db");
    conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;")
        .ok();
    db::init(&conn);

    let state = web::Data::new(AppState {
        db: Mutex::new(conn),
        keys,
        http_client: util::fetch::preview_client(),
        merchant_client: util::fetch::merchant_client(),
    });

    let public_addr = env::var("BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:8080".into());
    let internal_addr =
        env::var("INTERNAL_BIND_ADDR").unwrap_or_else(|_| "127.0.0.1:8081".into());

    log::info!("Public API: http://{}", public_addr);
    log::info!("Internal:   http://{}", internal_addr);

    let state_internal = state.clone();

    let internal_server = HttpServer::new(move || {
        App::new()
            .wrap(access_logger("%{client_ip}xi %r %s %Dms").log_target("internal"))
            .app_data(state_internal.clone())
            .route("/internal/health", web::get().to(handlers::internal::health))
            .route("/internal/metrics", web::get().to(handlers::internal::metrics))
    })
    .bind(&internal_addr)?
    .run();

    let public_server = HttpServer::new(move || {
        let cors = Cors::permissive();

        App::new()
            .wrap(cors)
            .wrap(access_logger("%{client_ip}xi \"%r\" %s %b %Dms"))
            .app_data(state.clone())
            .route("/", web::get().to(serve_index))
            .service(Files::new("/static", "./static"))
            .route("/api/health", web::get().to(health))
            // Auth
            .route("/api/auth/register", web::post().to(handlers::account::register))
            .route("/api/auth/login", web::post().to(handlers::account::login))
            // Account
            .route("/api/me", web::get().to(handlers::account::get_me))
            .route("/api/profile", web::put().to(handlers::account::update_profile))
            .route("/api/users", web::get().to(handlers::users::list_users))
            .route(
                "/api/users/{username}",
                web::get().to(handlers::users::user_profile),
            )
            // Transfers
            .route("/api/transfer", web::post().to(handlers::transfer::transfer))
            .route(
                "/api/transactions",
                web::get().to(handlers::transfer::list_transactions),
            )
            .route(
                "/api/transactions/stats",
                web::get().to(handlers::stats::transaction_stats),
            )
            // Notes
            .route("/api/notes", web::post().to(handlers::notes::create_note))
            .route("/api/notes", web::get().to(handlers::notes::list_my_notes))
            .route("/api/note", web::get().to(handlers::notes::get_note))
            .route(
                "/api/notes/preview",
                web::post().to(handlers::notes::note_preview),
            )
            // Messages
            .route(
                "/api/messages",
                web::post().to(handlers::messages::send_message),
            )
            .route(
                "/api/messages",
                web::get().to(handlers::messages::list_messages),
            )
            // Crypto
            .route(
                "/api/public-key",
                web::get().to(handlers::account::get_public_key),
            )
            // Merchant
            .route(
                "/api/merchant/register",
                web::post().to(handlers::merchant::register_merchant),
            )
            .route(
                "/api/merchant/pay",
                web::post().to(handlers::merchant::merchant_pay),
            )
    })
    .bind(&public_addr)?
    .run();

    tokio::try_join!(public_server, internal_server)?;
    Ok(())
}
