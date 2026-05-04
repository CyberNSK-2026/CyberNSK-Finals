//! Query-time bucketing specification for the analytics endpoint.
//!
//! A "bucket" selects how transactions are grouped in `/api/transactions/stats`:
//! by a time window, by counterparty, or by a custom time prefix. Named
//! shortcuts cover the common cases; the parametric forms let the front-end
//! build custom bucketings without the server needing redeployment for
//! every new chart widget.
//!
//! The spec language is intentionally tiny:
//!
//! ```text
//!   day | month | counterparty
//!   window:<N>            prefix-of-N characters of created_at
//!   tz:<offset>:<width>   time-zone-adjusted prefix
//! ```

use std::fmt;

/// Upper bound on raw spec length. Bucket specs are short by construction
/// (a timezone-tagged window is at most ~20 characters) so anything larger
/// is almost certainly a mistake and we reject it.
const MAX_SPEC_LEN: usize = 256;

/// Parsed bucketing spec. Call [`BucketSpec::as_sql`] to obtain the SQL
/// fragment suitable for splicing into a `GROUP BY`.
#[derive(Debug)]
pub struct BucketSpec {
    mode: String,
    arg: String,
}

#[derive(Debug)]
pub enum SpecError {
    TooLong,
    EmptyMode,
    BadMode,
}

impl fmt::Display for SpecError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SpecError::TooLong => f.write_str("bucket spec too long"),
            SpecError::EmptyMode => f.write_str("empty bucket mode"),
            SpecError::BadMode => f.write_str("bucket mode contains unsupported characters"),
        }
    }
}

impl BucketSpec {
    /// Parse a raw spec of the form `<mode>` or `<mode>:<arg>`.
    ///
    /// The mode is validated strictly (ASCII alphanumeric + underscore); the
    /// argument is mode-specific and interpreted by [`as_sql`].
    pub fn parse(raw: &str) -> Result<Self, SpecError> {
        let raw = raw.trim();
        if raw.len() > MAX_SPEC_LEN {
            return Err(SpecError::TooLong);
        }
        let (mode, arg) = match raw.split_once(':') {
            Some((m, rest)) => (m, rest),
            None => (raw, ""),
        };
        if mode.is_empty() {
            return Err(SpecError::EmptyMode);
        }
        if !mode
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_')
        {
            return Err(SpecError::BadMode);
        }
        Ok(Self {
            mode: mode.to_owned(),
            arg: arg.to_owned(),
        })
    }

    /// Default "group by day" used when the caller didn't specify anything.
    pub fn default_day() -> Self {
        Self {
            mode: "day".into(),
            arg: String::new(),
        }
    }

    /// Render this spec as the SQL fragment used in `GROUP BY`.
    ///
    /// The token `?1` is reserved for the viewer's user id (bound by the
    /// caller) and is only referenced in `counterparty` mode.
    pub fn as_sql(&self) -> String {
        match self.mode.as_str() {
            "day" => "substr(t.created_at, 1, 10)".into(),
            "month" => "substr(t.created_at, 1, 7)".into(),
            "counterparty" => {
                "CASE WHEN t.from_user = ?1 THEN tu.username ELSE fu.username END".into()
            }
            "window" => {
                // width-of-N prefix of created_at. ISO-8601 is padded, so a
                // numeric width is meaningful: 4=year, 7=month, 10=day, 13=hour.
                format!("substr(t.created_at, 1, {})", self.arg)
            }
            "tz" => {
                // tz:<offset>:<width> — e.g. "tz:+03:00:10" groups by day in
                // Moscow time. Offset is fed to SQLite's datetime() modifier.
                let (offset, width) =
                    self.arg.rsplit_once(':').unwrap_or((self.arg.as_str(), "10"));
                format!(
                    "substr(datetime(t.created_at, '{}'), 1, {})",
                    offset, width
                )
            }
            // Unknown modes silently fall back to day buckets so the UI never
            // breaks on an unrecognised spec from an older client.
            _ => "substr(t.created_at, 1, 10)".into(),
        }
    }
}
