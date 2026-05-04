# VIP Games

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
- Flaw: booster ownership is validated, target pet ownership is not.

4. Alchemy state-machine bypass
- Endpoint: `POST /api/games/alchemy/runs/:id/finalize`
- Flaw: finalize can be called without strict transition history checks.

5. Card trade logic race surface
- Endpoint: `POST /api/games/cards/trades/:id/accept`
- Flaw: accept path is non-idempotent and misses robust status/ownership guards.

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
- `checker/` - Python checker (already scaffolded)
