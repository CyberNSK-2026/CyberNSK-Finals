# NeoBank - Attack-Defense CTF Service

Standalone online banking service written in Rust. The service exposes a
public banking API, a loopback-only internal API, and a merchant payment
flow with signed settlement callbacks.

## Quick Start

```bash
docker compose up --build -d

# then open http://localhost:8080 in a browser

# ForcAD-style checker run
python checker/checker.py check localhost
python checker/checker.py put localhost seed 'CTF{test}' 1

# legacy env-based checker run (used by docker compose testing profile)
docker compose --profile testing run --rm checker

# end-to-end exploit suite
python exploit_all.py localhost 8080
```

`docker-compose.yml` enables `ALLOW_PRIVATE_CALLBACKS=1` for local testing so
the merchant callback scenario can use a loopback webhook. Do not rely on that
flag for production or competition deployment.

| Surface | URL |
|---|---|
| Web UI | http://localhost:8080 |
| Public API | http://localhost:8080/api/* |
| Internal API | http://127.0.0.1:8081/internal/* |

## Architecture

The bank runs two HTTP servers in one process:

- Public server on `0.0.0.0:8080` for the SPA and the public REST API.
- Internal server on `127.0.0.1:8081` for `/internal/health` and `/internal/metrics`.

The internal server is intentionally reachable only from loopback. From the
outside, it should only be visible indirectly through SSRF-style bugs.

## Public Features

| Area | Endpoints |
|---|---|
| Auth | `/api/auth/register`, `/api/auth/login` |
| Account | `/api/me`, `/api/profile`, `/api/users`, `/api/users/{username}` |
| Transfers | `/api/transfer`, `/api/transactions`, `/api/transactions/stats` |
| Notes | `/api/notes` (create/list), `/api/note?id=`, `/api/notes/preview` |
| Messages | `/api/messages` (send/list; `inbox`, `sent`, `all`) |
| Crypto | `/api/public-key` |
| Merchant | `/api/merchant/register`, `/api/merchant/pay` |

## Checker

The checker is ForcAD-compatible and uses only ordinary user-level APIs.
Primary CLI:

```bash
python checker/checker.py check <host>
python checker/checker.py put <host> <id> <flag> <vuln>
python checker/checker.py get <host> <flag_id> <flag> <vuln>
```

The current checker keeps env-based fallback mode for local manual runs and the
`docker compose --profile testing run checker` workflow.

`check` validates the normal user flow end-to-end:

- auth and profile update
- user listing and public profile view
- transfers and transaction stats
- private notes and private messages
- public key endpoint
- merchant registration, merchant payment, and merchant nonce replay protection

Legitimate PUT/GET flag stores:

| Store | Plant flow | Read-back flow |
|---|---|---|
| 1 | `/api/transfer` comment between two checker-owned users | `GET /api/transactions` |
| 2 | private note body via `/api/notes` | `GET /api/note?id=` |
| 3 | private message body via `/api/messages` | `GET /api/messages?folder=inbox` |

There is also an organizer-side settlement field,
`merchant_settlements.receipt_note`, described in [WRITEUP.md](WRITEUP.md) and
used by the exploit suite. The checker does not PUT/GET that store because the
service intentionally has no legitimate read-back endpoint for it.

See [checker/checker.py](checker/checker.py) and
[checker/forcad-config-example.yml](checker/forcad-config-example.yml).

## Vulnerabilities And Exploits

The service writeup documents 5 vulnerabilities and 4 flag stores. The exploit
suite currently runs 6 end-to-end scenarios because the SQL injection path is
exercised twice:

- once against `transactions.comment`
- once against `merchant_settlements.receipt_note`

See [WRITEUP.md](WRITEUP.md) for the organizer writeup and
[exploit_all.py](exploit_all.py) for runnable attack scripts.

## Repository Layout

```text
bank/                       Rust service
  src/
    handlers/               HTTP handlers by feature area
    util/                   SSRF guard, stats bucket parsing, request gating
    db.rs                   schema and seed data
    models.rs               request/response DTOs
    main.rs                 server wiring
  static/index.html         SPA frontend

checker/                    Python checker
  checker.py                ForcAD checker with CLI + env fallback

docker-compose.yml          Local orchestration
exploit_all.py              End-to-end exploit suite
WRITEUP.md                  Organizer vulnerability writeup
README.md                   This file
```
