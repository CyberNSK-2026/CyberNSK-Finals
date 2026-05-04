//! Outbound HTTP fetch policy for user-supplied URLs.
//!
//! The preview feature lets users attach a title/snippet from an external
//! page to a note. We need to allow the broad public web (title extraction
//! is useful on almost any site) while rejecting the obvious internal-only
//! destinations — loopback, link-local, private ranges, cloud metadata.

use std::net::{IpAddr, ToSocketAddrs};
use std::time::Duration;

/// Hostnames that are always rejected as the literal request target.
///
/// Numeric IPs are additionally filtered via [`is_internal_address`];
/// domain names are resolved and each returned address is checked.
const BLOCKLIST_HOSTS: &[&str] = &[
    "localhost",
    "127.0.0.1",
    "0.0.0.0",
    "::1",
    "::",
    "169.254.169.254", // AWS / GCP cloud metadata
    "metadata.google.internal",
];

/// Outbound ports that are never fetched — infrastructure services (SSH,
/// SMTP, SMB, databases, caches) plus the internal metrics port.
const BLOCKED_PORTS: &[u16] = &[
    22, 23, 25, 53, 110, 143, 445, 1433, 3306, 5432, 6379, 8081, 9200, 11211, 27017,
];

/// Validate that `raw` is safe for server-side fetching.
///
/// Returns the parsed URL on success. The caller feeds the returned
/// [`reqwest::Url`] (not the raw string) into the HTTP client so the
/// request sees exactly what we validated.
pub fn ensure_public_url(raw: &str) -> Result<reqwest::Url, &'static str> {
    let parsed = reqwest::Url::parse(raw).map_err(|_| "malformed URL")?;

    match parsed.scheme() {
        "http" | "https" => {}
        _ => return Err("only http/https is allowed"),
    }

    if let Some(port) = parsed.port() {
        if BLOCKED_PORTS.contains(&port) {
            return Err("port is on the blocklist");
        }
    }

    let host = parsed.host_str().ok_or("URL missing host")?;
    if BLOCKLIST_HOSTS
        .iter()
        .any(|h| h.eq_ignore_ascii_case(host))
    {
        return Err("host is on the internal blocklist");
    }

    if let Ok(ip) = host.parse::<IpAddr>() {
        if is_internal_address(&ip) {
            return Err("refusing to fetch internal address");
        }
    } else {
        // Domain: resolve and reject if any returned address is internal.
        // We only check the connect-time port so we don't hit DNS twice
        // for the same host.
        let connect_port = parsed.port_or_known_default().unwrap_or(80);
        let addrs: Vec<_> = (host, connect_port)
            .to_socket_addrs()
            .map_err(|_| "could not resolve host")?
            .collect();
        if addrs.is_empty() {
            return Err("host did not resolve");
        }
        for sa in &addrs {
            if is_internal_address(&sa.ip()) {
                return Err("host resolves to an internal address");
            }
        }
    }

    Ok(parsed)
}

fn is_internal_address(ip: &IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => {
            v4.is_loopback()
                || v4.is_private()
                || v4.is_link_local()
                || v4.is_broadcast()
                || v4.is_unspecified()
        }
        IpAddr::V6(v6) => v6.is_loopback() || v6.is_unspecified(),
    }
}

/// Construct the shared HTTP client used for merchant callbacks.
///
/// Merchant webhooks are point-to-point: the merchant gives us a URL,
/// we POST the settlement. Real merchants do not redirect their
/// webhook endpoints off-domain, so we disable redirect following
/// entirely — this also closes off any SSRF redirect game on this
/// code path.
pub fn merchant_client() -> reqwest::Client {
    reqwest::Client::builder()
        .timeout(Duration::from_secs(5))
        .user_agent("NeoBank-Merchant/1.0")
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .expect("build merchant http client")
}

/// Construct the shared HTTP client used for URL previews.
///
/// Kept as a single long-lived `Client` so the connection pool is reused
/// across requests. The custom redirect policy caps hop count and guards
/// against redirects into the literal internal hostnames — without it,
/// any bit.ly-style shortener that redirects off-domain would be blocked.
pub fn preview_client() -> reqwest::Client {
    reqwest::Client::builder()
        .timeout(Duration::from_secs(5))
        .user_agent("NeoBank-Preview/1.0")
        .redirect(reqwest::redirect::Policy::custom(|attempt| {
            if attempt.previous().len() >= 3 {
                return attempt.stop();
            }
            if let Some(host) = attempt.url().host_str() {
                if BLOCKLIST_HOSTS
                    .iter()
                    .any(|h| h.eq_ignore_ascii_case(host))
                {
                    return attempt.error("redirect to blocked host");
                }
            }
            attempt.follow()
        }))
        .build()
        .expect("build http client")
}
