//! Tiny in-process coalescer used to dedupe duplicate submissions.
//!
//! The typical case is a user double-clicking a "Preview" button — two
//! requests arrive within milliseconds, both trigger the same outbound
//! fetch, both update the note. The gate blocks the duplicate until the
//! first one finishes, at which point a fresh gate can be taken.

use std::collections::HashSet;
use std::sync::{Mutex, OnceLock};

fn in_flight_set() -> &'static Mutex<HashSet<String>> {
    static SET: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();
    SET.get_or_init(|| Mutex::new(HashSet::new()))
}

/// RAII guard returned by [`acquire`]. The key is released automatically
/// when the guard is dropped (typically at end of the handler).
pub struct Gate {
    key: String,
}

impl Drop for Gate {
    fn drop(&mut self) {
        let mut set = in_flight_set().lock().unwrap();
        set.remove(&self.key);
    }
}

/// Try to take the gate for `key`. Returns `None` if another request for
/// the same key is already in flight; the caller should respond with a
/// 409 in that case.
pub fn acquire(key: String) -> Option<Gate> {
    let mut set = in_flight_set().lock().unwrap();
    if !set.insert(key.clone()) {
        return None;
    }
    Some(Gate { key })
}
