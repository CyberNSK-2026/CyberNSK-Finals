//! JWT issuance and verification.
//!
//! Tokens are signed with RS256 using an ephemeral server RSA keypair
//! generated on startup. For inbound tokens we also accept the legacy
//! mobile-SDK format — see [`legacy`] for the details. New clients
//! should only ever issue RS256.

mod legacy;

use actix_web::{HttpRequest, HttpResponse};
use jsonwebtoken::{
    decode, decode_header, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation,
};
use rsa::pkcs1::EncodeRsaPublicKey;
use rsa::pkcs8::EncodePrivateKey;
use rsa::{RsaPrivateKey, RsaPublicKey};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Claims {
    pub sub: String,
    pub username: String,
    pub exp: usize,
}

pub struct JwtKeys {
    rsa_private_pem: Vec<u8>,
    rsa_public_pem: Vec<u8>,
}

impl JwtKeys {
    pub fn new(rsa_private_pem: Vec<u8>, rsa_public_pem: Vec<u8>) -> Self {
        Self {
            rsa_private_pem,
            rsa_public_pem,
        }
    }

    pub fn public_pem(&self) -> &[u8] {
        &self.rsa_public_pem
    }

    pub(crate) fn private_pem(&self) -> &[u8] {
        &self.rsa_private_pem
    }
}

pub fn create_token(
    user_id: &str,
    username: &str,
    keys: &JwtKeys,
) -> Result<String, jsonwebtoken::errors::Error> {
    let claims = Claims {
        sub: user_id.to_string(),
        username: username.to_string(),
        exp: (chrono::Utc::now() + chrono::Duration::hours(24)).timestamp() as usize,
    };
    let key = EncodingKey::from_rsa_pem(keys.private_pem())?;
    encode(&Header::new(Algorithm::RS256), &claims, &key)
}

pub fn verify_token(
    token: &str,
    keys: &JwtKeys,
) -> Result<Claims, jsonwebtoken::errors::Error> {
    let header = decode_header(token)?;
    match header.alg {
        Algorithm::RS256 => {
            let validation = Validation::new(Algorithm::RS256);
            let dkey = DecodingKey::from_rsa_pem(keys.public_pem())?;
            Ok(decode::<Claims>(token, &dkey, &validation)?.claims)
        }
        Algorithm::HS256 => legacy::verify(token, keys),
        _ => Err(jsonwebtoken::errors::ErrorKind::InvalidAlgorithm.into()),
    }
}

/// Pull the `Authorization: Bearer` token off the request and verify it.
pub fn require_claims(
    req: &HttpRequest,
    keys: &JwtKeys,
) -> Result<Claims, HttpResponse> {
    let auth = req
        .headers()
        .get("Authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .ok_or_else(|| {
            HttpResponse::Unauthorized()
                .json(serde_json::json!({"error": "Authentication required"}))
        })?;

    verify_token(auth, keys).map_err(|_| {
        HttpResponse::Unauthorized().json(serde_json::json!({"error": "Invalid token"}))
    })
}

pub fn generate_rsa_keys() -> (Vec<u8>, Vec<u8>) {
    let mut rng = rand::thread_rng();
    let private_key = RsaPrivateKey::new(&mut rng, 2048).expect("rsa keygen");
    let public_key = RsaPublicKey::from(&private_key);

    let private_pem = private_key
        .to_pkcs8_pem(rsa::pkcs8::LineEnding::LF)
        .expect("encode private");
    let public_pem = public_key
        .to_pkcs1_pem(rsa::pkcs1::LineEnding::LF)
        .expect("encode public");

    (
        private_pem.as_bytes().to_vec(),
        public_pem.as_bytes().to_vec(),
    )
}
