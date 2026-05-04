# VIP Games - Vulnerabilities

## VULN 1: Achievement board owner-binding bug

- Class: broken business authorization in achievement projection logic.
- Surface: `/api/achievements/board/:username/details?code=<achievement_code>`
- Root cause:
  - board lookup is done by `username`
  - detail lookup by `achievement_code`
  - one join branch does not enforce `detail.user_id == board.user_id`
- Exploit impact: attacker can fetch `secretNote` copied from checker achievement flow.
- Flag location: `user_achievements.secret_note`
- Fix direction:
  - enforce strict owner binding in every query path
  - deny cross-user achievement detail projection

## VULN 2: Puzzle stego layer exposure

- Class: sensitive data exposure due to wrong layer selection in business logic.
- Surface: `/api/games/puzzle/:id/preview?mode=solved`
- Root cause:
  - solved preview branch can return original asset blob reference
  - original blob includes hidden payload used by checker
- Exploit impact: attacker can download stego-bearing layer and extract flag.
- Flag location: hidden payload in puzzle asset blob.
- Fix direction:
  - always render and serve sanitized derived preview
  - block direct original blob handoff in public routes

## VULN 3: Pet Farm booster target mismatch

- Class: confused deputy / object-binding logic flaw.
- Surface: `/api/games/petfarm/boosters/apply`
- Root cause:
  - verifies booster ownership
  - does not verify that `pet_id` belongs to same user
- Exploit impact: attacker can apply their booster to a foreign pet and receive the target pet projection in the response.
- Flag location: pet `tag`/`bio`.
- Fix direction:
  - enforce `(booster.owner_id == session.user_id && pet.owner_id == session.user_id)`
  - wrap validation + mutation in one transaction

## VULN 4: Alchemy state-machine finalize bypass

- Class: workflow validation bypass.
- Surface: `/api/games/alchemy/runs/:id/finalize`
- Root cause:
  - endpoint allows finalize calls outside the owner-controlled transition flow
  - already finalized runs are returned to the caller
- Exploit impact: attacker reaches artifact output without required transitions and obtains flag-bearing artifact note.
- Flag location: `recipe_runs.artifact_note`.
- Fix direction:
  - enforce strict finite-state transitions
  - persist signed transition log or monotonic sequence checks

## VULN 5: Card trade double-accept race

- Class: broken trade ownership / duplication in business transaction.
- Surface: `/api/games/cards/trades/:id/accept`
- Root cause:
  - trade creation does not verify that `card_id` belongs to the proposer
  - accept duplicates the referenced card to the recipient without robust ownership guards
- Exploit impact: attacker duplicates a victim card into their own account and reads flag-bearing card metadata.
- Flag location: `cards.custom_name` or metadata.
- Fix direction:
  - verify proposer owns the card when creating a trade
  - verify acceptor is the intended recipient
  - make accept idempotent and non-duplicating

## Checker notes

- `put/get/check` must use only public endpoints and normal game flows.
- No checker-only routes.
- `flag_id` should include:
  - `v` (vuln key)
  - `u` (checker username)
  - entity id (`aid`, `pid`, `pet`, `rid`, `cid`)
  - round/slot material needed to recompute credentials
  - integrity signature (HMAC)
