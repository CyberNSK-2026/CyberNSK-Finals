use serde::{Deserialize, Serialize};

pub const STARTING_BALANCE: f64 = 100.0;
pub const PREVIEW_FEE_PRIVATE: f64 = 50.0;

// ===== Request DTOs =====

#[derive(Deserialize)]
pub struct RegisterReq {
    pub username: String,
    pub password: String,
}

#[derive(Deserialize)]
pub struct LoginReq {
    pub username: String,
    pub password: String,
}

#[derive(Deserialize)]
pub struct ProfileUpdateReq {
    pub display_name: String,
}

#[derive(Deserialize)]
pub struct TransferReq {
    pub to: String,
    pub amount: f64,
    pub comment: Option<String>,
}

#[derive(Deserialize)]
pub struct TransactionsQuery {
    pub sort: Option<String>,
    pub order: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Deserialize)]
pub struct NoteCreateReq {
    pub title: String,
    pub body: String,
    pub visibility: Option<String>,
}

#[derive(Deserialize)]
pub struct NoteIdQuery {
    pub id: String,
}

#[derive(Deserialize)]
pub struct PreviewReq {
    pub note_id: String,
    pub url: String,
}

#[derive(Deserialize)]
pub struct MessageSendReq {
    pub to: String,
    pub subject: String,
    pub body: String,
}

#[derive(Deserialize)]
pub struct MessagesQuery {
    pub folder: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Deserialize)]
pub struct MerchantPayReq {
    pub merchant_id: String,
    pub username: String,
    pub amount: f64,
    pub nonce: String,
    pub timestamp: String,
    pub signature: String,
    pub description: Option<String>,
}

#[derive(Deserialize)]
pub struct MerchantRegisterReq {
    pub merchant_id: String,
    pub api_key: String,
    pub callback_url: String,
}

/// Response shape from a merchant's webhook. Fields are optional so
/// that a merchant may return either one, both, or neither — the
/// settlement is still recorded regardless.
#[derive(Deserialize)]
pub struct SettlementReceipt {
    #[allow(dead_code)]
    pub receipt_id: Option<String>,
    pub note: Option<String>,
}

// ===== Response DTOs =====

#[derive(Serialize)]
pub struct AccountInfo {
    pub id: String,
    pub username: String,
    pub display_name: String,
    pub balance: f64,
}

#[derive(Serialize)]
pub struct PublicUser {
    pub id: String,
    pub username: String,
    pub display_name: String,
}

#[derive(Serialize)]
pub struct TransactionInfo {
    pub id: String,
    pub from_user: String,
    pub to_user: String,
    pub from_username: String,
    pub to_username: String,
    pub amount: f64,
    pub comment: String,
    pub created_at: String,
}

#[derive(Serialize, Clone)]
pub struct NoteInfo {
    pub id: String,
    pub owner_id: String,
    pub owner_username: String,
    pub title: String,
    pub body: String,
    pub visibility: String,
    pub preview: String,
    pub created_at: String,
}

#[derive(Serialize)]
pub struct FeedNote {
    pub id: String,
    pub owner_username: String,
    pub title: String,
    pub body: String,
    pub visibility: String,
    pub created_at: String,
}

#[derive(Serialize)]
pub struct MessageInfo {
    pub id: String,
    pub sender_id: String,
    pub recipient_id: String,
    pub sender_username: String,
    pub recipient_username: String,
    pub subject: String,
    pub body: String,
    pub created_at: String,
}
