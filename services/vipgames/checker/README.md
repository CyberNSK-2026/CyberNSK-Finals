# VIP Games Checker

Python checker for ForkAD-compatible `check/put/get` flow with 5 vuln slots:

- `0` / `achievements`
- `1` / `puzzle`
- `2` / `petfarm`
- `3` / `alchemy`
- `4` / `cards`

## Install

No external dependencies are required (Python 3.10+ is enough).

## Run

```bash
python3 checker.py check <host>
python3 checker.py put <host> <id> <flag> <vuln>
python3 checker.py get <host> <flag_id> <flag> <vuln>
python3 checker.py smoke <host>
```

Examples:

```bash
python3 checker.py put 127.0.0.1 12 FLAG_ABC 0
python3 checker.py get 127.0.0.1 '<flag_id_from_put>' FLAG_ABC 0
```

## Status codes

- `101` OK
- `102` CORRUPT
- `103` MUMBLE
- `104` DOWN
- `110` CHECKER_ERROR

## Local self-test

```bash
python3 checker.py self-test
```

## End-to-end smoke test

Requires running service at `<host>`:

```bash
python3 smoke_test.py <host>
```

## Notes

- The checker uses hardcoded service port `8642` when `<host>` is passed without an explicit port.
- `flag_id` is HMAC-signed (`CHECKER_SECRET` env var).
- `flag_id` does not contain the account password; checker recomputes it deterministically from host/vuln/round/slot.
- `CHECKER_TIMEOUT` (seconds) controls request timeout per operation.

# VIP Games walkthrow

Vulnerable pixel-medieval web arcade service for Attack-Defense CTF.

## Implemented stack

- TypeScript (`strict`)
- Fastify 5
- SSR templates: Nunjucks
- Storage: SQLite (`better-sqlite3`)
- Auth: cookie sessions + bcryptjs
- Static UI: classic old flash portal style

## One-command launch

```bash
docker compose up --build
```

Service URL: `http://<host>:3000`

## Features

- Open registration and login for all users.
- Profile tracking:
  - total game runs
  - completed runs
  - average score
- Achievement board per account.
- 4 mini-games:
  - Puzzle Forge
  - Pet Farm
  - Alchemy Lab
  - Card Hall

## Implemented vulnerabilities

1. Achievement board owner-binding bug
- Endpoint: `GET /api/achievements/board/:username/details?code=...`
- Flaw: detail lookup ignores board owner in one projection path.
- Flag flow: checker stores flag in journal -> unlocks `ARCHIVIST` -> retrieves secret note from board details.

2. Puzzle stego layer exposure
- Endpoint: `GET /api/games/puzzle/:id/preview?mode=solved`
- Flaw: solved mode leaks hidden payload (`hiddenPayload`) from stored board layer.

3. Pet Farm confused deputy
- Endpoint: `POST /api/games/petfarm/boosters/apply`
- Flaw: booster ownership is validated, target pet ownership is not, and the target pet projection is returned.

4. Alchemy state-machine bypass
- Endpoint: `POST /api/games/alchemy/runs/:id/finalize`
- Flaw: finalize can be called outside the owner-controlled transition flow and returns finalized artifacts.

5. Card trade logic duplication surface
- Endpoint: `POST /api/games/cards/trades/:id/accept`
- Flaw: trade creation/accept misses robust card ownership guards and can duplicate a foreign card.

## API summary (checker-oriented)

- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/logout`
- `GET /api/profile/me`

Achievements:
- `POST /api/achievements/journal`
- `POST /api/achievements/unlock`
- `GET /api/achievements/board/me`
- `GET /api/achievements/board/me/details?code=ARCHIVIST`
- `GET /api/achievements/board/:username/details?code=ARCHIVIST`

Puzzle:
- `POST /api/games/puzzle/boards`
- `POST /api/games/puzzle/:id/save-stego`
- `GET /api/games/puzzle/:id/preview?mode=solved`

Pet Farm:
- `POST /api/games/petfarm/pets`
- `POST /api/games/petfarm/boosters`
- `POST /api/games/petfarm/boosters/apply`
- `GET /api/games/petfarm/pets/:id`

Alchemy:
- `POST /api/games/alchemy/runs`
- `POST /api/games/alchemy/runs/:id/finalize`
- `GET /api/games/alchemy/runs/:id/artifact`

Cards:
- `POST /api/games/cards`
- `GET /api/games/cards/:id`
- `POST /api/games/cards/trades`
- `POST /api/games/cards/trades/:id/accept`

## Project layout

- `src/server.ts` - app bootstrap
- `src/services/db.ts` - schema + storage + vulnerable logic
- `src/routes/web.ts` - SSR pages
- `src/routes/api.ts` - API routes
- `src/public` - pixel-medieval assets
- `docker-compose.yml` - run configuration
- `Dockerfile` - container build
