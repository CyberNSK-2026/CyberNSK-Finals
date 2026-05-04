import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from "fastify";
import { hashPassword, validateCredentials, verifyPassword } from "../services/auth.js";

function unauthorized(reply: FastifyReply): never {
  reply.code(401).send({ error: "unauthorized" });
  throw new Error("unauthorized");
}

function requireUser(request: FastifyRequest, reply: FastifyReply) {
  if (!request.currentUser) {
    unauthorized(reply);
  }
  return request.currentUser;
}

function parseId(value: string): number {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) {
    throw new Error("invalid_id");
  }
  return n;
}

export const apiRoutes: FastifyPluginAsync = async (app) => {
  app.post("/api/auth/register", async (request, reply) => {
    const body = (request.body ?? {}) as { username?: string; password?: string };
    const username = String(body.username ?? "").trim();
    const password = String(body.password ?? "");

    const err = validateCredentials(username, password);
    if (err) {
      return reply.code(400).send({ error: err });
    }

    const existing = app.db.getUserByUsername(username);
    if (existing) {
      return reply.code(409).send({ error: "user_exists" });
    }

    const passwordHash = await hashPassword(password);
    const userId = app.db.createUser(username, passwordHash);
    const token = app.db.createSession(userId);
    reply.setCookie("vip_sid", token, { path: "/", httpOnly: true, sameSite: "lax" });
    return reply.code(201).send({ ok: true, userId, username });
  });

  app.post("/api/auth/login", async (request, reply) => {
    const body = (request.body ?? {}) as { username?: string; password?: string };
    const username = String(body.username ?? "").trim();
    const password = String(body.password ?? "");

    const user = app.db.getUserByUsername(username);
    if (!user) {
      return reply.code(403).send({ error: "invalid_credentials" });
    }
    const ok = await verifyPassword(password, user.passwordHash);
    if (!ok) {
      return reply.code(403).send({ error: "invalid_credentials" });
    }

    const token = app.db.createSession(user.id);
    reply.setCookie("vip_sid", token, { path: "/", httpOnly: true, sameSite: "lax" });
    return { ok: true, username: user.username };
  });

  app.post("/api/auth/logout", async (request, reply) => {
    const sid = request.cookies.vip_sid;
    if (sid) {
      app.db.clearSession(sid);
    }
    reply.clearCookie("vip_sid", { path: "/" });
    return { ok: true };
  });

  app.get("/api/profile/me", async (request, reply) => {
    const user = requireUser(request, reply);
    const stats = app.db.getUserStats(user.id);
    const achievements = app.db.listAchievements(user.id);
    return {
      user: { id: user.id, username: user.username, createdAt: user.createdAt },
      stats,
      achievements,
    };
  });

  app.post("/api/achievements/journal", async (request, reply) => {
    const user = requireUser(request, reply);
    const body = (request.body ?? {}) as { title?: string; note?: string };
    const title = String(body.title ?? "").trim();
    const note = String(body.note ?? "").trim();
    if (!title || !note) {
      return reply.code(400).send({ error: "title_and_note_required" });
    }
    const id = app.db.putJournal(user.id, title.slice(0, 80), note.slice(0, 256));
    return reply.code(201).send({ id });
  });

  app.post("/api/achievements/unlock", async (request, reply) => {
    const user = requireUser(request, reply);
    const body = (request.body ?? {}) as { code?: string; sourceEntryId?: number };
    const code = String(body.code ?? "").toUpperCase();
    const sourceEntryId = Number.isInteger(body.sourceEntryId) ? Number(body.sourceEntryId) : undefined;
    if (!code) {
      return reply.code(400).send({ error: "code_required" });
    }
    const achievementId = app.db.unlockAchievement(user.id, code, sourceEntryId);
    return reply.code(201).send({ achievementId, code });
  });

  app.get("/api/achievements/board/me", async (request, reply) => {
    const user = requireUser(request, reply);
    const items = app.db.listAchievements(user.id);
    return { username: user.username, items };
  });

  app.get("/api/achievements/board/me/details", async (request, reply) => {
    const user = requireUser(request, reply);
    const query = request.query as { code?: string; achievementId?: string };
    const code = String(query.code ?? "").toUpperCase();
    const achievementId = query.achievementId ? parseId(query.achievementId) : undefined;
    const details = app.db.getAchievementDetailsVulnerable(user.username, code, achievementId);
    if (!details) {
      return reply.code(404).send({ error: "not_found" });
    }
    return details;
  });

  app.get("/api/achievements/board/:username/details", async (request, reply) => {
    const params = request.params as { username: string };
    const query = request.query as { code?: string; achievementId?: string };
    const code = String(query.code ?? "").toUpperCase();
    const achievementId = query.achievementId ? parseId(query.achievementId) : undefined;
    const details = app.db.getAchievementDetailsVulnerable(params.username, code, achievementId);
    if (!details) {
      return reply.code(404).send({ error: "not_found" });
    }
    return details;
  });

  app.get("/api/games/:game", async (request, reply) => {
    const params = request.params as { game: string };
    if (!["puzzle", "petfarm", "alchemy", "cards"].includes(params.game)) {
      return reply.code(404).send({ error: "game_not_found" });
    }
    return { game: params.game, ok: true, style: "pixel-medieval" };
  });

  app.post("/api/games/puzzle/boards", async (request, reply) => {
    const user = requireUser(request, reply);
    const body = (request.body ?? {}) as { title?: string };
    const title = String(body.title ?? "Untitled board").trim().slice(0, 80) || "Untitled board";
    const id = app.db.createPuzzleBoard(user.id, title);
    return reply.code(201).send({ id, title });
  });

  app.post("/api/games/puzzle/:id/save-stego", async (request, reply) => {
    const user = requireUser(request, reply);
    const params = request.params as { id: string };
    const body = (request.body ?? {}) as { payload?: string };
    const id = parseId(params.id);
    const payload = String(body.payload ?? "");
    if (!payload) {
      return reply.code(400).send({ error: "payload_required" });
    }
    app.db.savePuzzleStego(user.id, id, payload.slice(0, 256));
    return reply.code(201).send({ ok: true, id });
  });

  app.get("/api/games/puzzle/:id/preview", async (request, reply) => {
    const params = request.params as { id: string };
    const id = parseId(params.id);
    const mode = String((request.query as { mode?: string }).mode ?? "normal");
    const board = app.db.getPuzzleBoard(id);
    if (!board) {
      return reply.code(404).send({ error: "not_found" });
    }

    if (mode === "solved") {
      return {
        id,
        preview: "stained_glass_render.png",
        hiddenPayload: board.stegoPayload,
      };
    }

    return {
      id,
      preview: "stained_glass_render.png",
      hiddenPayload: null,
    };
  });

  app.post("/api/games/petfarm/pets", async (request, reply) => {
    const user = requireUser(request, reply);
    const body = (request.body ?? {}) as { name?: string; tag?: string };
    const name = String(body.name ?? "Squire").trim().slice(0, 60) || "Squire";
    const tag = String(body.tag ?? "").slice(0, 256);
    if (!tag) {
      return reply.code(400).send({ error: "tag_required" });
    }
    const id = app.db.createPet(user.id, name, tag);
    return reply.code(201).send({ id, name, tag });
  });

  app.post("/api/games/petfarm/boosters", async (request, reply) => {
    const user = requireUser(request, reply);
    const body = (request.body ?? {}) as { payload?: string };
    const payload = String(body.payload ?? "").slice(0, 256);
    if (!payload) {
      return reply.code(400).send({ error: "payload_required" });
    }
    const id = app.db.createBooster(user.id, payload);
    return reply.code(201).send({ id });
  });

  app.post("/api/games/petfarm/boosters/apply", async (request, reply) => {
    const user = requireUser(request, reply);
    const body = (request.body ?? {}) as { boosterId?: number; petId?: number };
    const boosterId = Number(body.boosterId);
    const petId = Number(body.petId);
    if (!Number.isInteger(boosterId) || !Number.isInteger(petId)) {
      return reply.code(400).send({ error: "boosterId_and_petId_required" });
    }
    try {
      const pet = app.db.applyBoosterVulnerable(user.id, boosterId, petId);
      return { ok: true, pet };
    } catch (err) {
      return reply.code(409).send({ error: (err as Error).message });
    }
  });

  app.get("/api/games/petfarm/pets/:id", async (request, reply) => {
    const user = requireUser(request, reply);
    const params = request.params as { id: string };
    const id = parseId(params.id);
    const pet = app.db.getPet(id);
    if (!pet || pet.userId !== user.id) {
      return reply.code(404).send({ error: "not_found" });
    }
    return pet;
  });

  app.post("/api/games/alchemy/runs", async (request, reply) => {
    const user = requireUser(request, reply);
    const body = (request.body ?? {}) as { recipe?: string };
    const recipe = String(body.recipe ?? "moon_salt").slice(0, 64);
    const id = app.db.createAlchemyRun(user.id, recipe);
    return reply.code(201).send({ id, state: "draft" });
  });

  app.post("/api/games/alchemy/runs/:id/finalize", async (request, reply) => {
    const user = requireUser(request, reply);
    const params = request.params as { id: string };
    const id = parseId(params.id);
    const body = (request.body ?? {}) as { artifactNote?: string };
    const artifactNote = String(body.artifactNote ?? "").slice(0, 256);
    if (!artifactNote) {
      return reply.code(400).send({ error: "artifactNote_required" });
    }
    const artifact = app.db.finalizeAlchemyRunVulnerable(user.id, id, artifactNote);
    return reply.code(201).send({ ok: true, id, artifact });
  });

  app.get("/api/games/alchemy/runs/:id/artifact", async (request, reply) => {
    const user = requireUser(request, reply);
    const params = request.params as { id: string };
    const id = parseId(params.id);
    const artifact = app.db.getAlchemyArtifact(id);
    if (!artifact || artifact.userId !== user.id) {
      return reply.code(404).send({ error: "not_found" });
    }
    return artifact;
  });

  app.post("/api/games/cards", async (request, reply) => {
    const user = requireUser(request, reply);
    const body = (request.body ?? {}) as { customName?: string; power?: number };
    const customName = String(body.customName ?? "").slice(0, 256);
    const power = Number(body.power ?? 1);
    if (!customName || !Number.isFinite(power)) {
      return reply.code(400).send({ error: "invalid_card_payload" });
    }
    const id = app.db.createCard(user.id, customName, Math.max(1, Math.min(100, Math.floor(power))));
    return reply.code(201).send({ id, customName });
  });

  app.get("/api/games/cards/:id", async (request, reply) => {
    const user = requireUser(request, reply);
    const params = request.params as { id: string };
    const id = parseId(params.id);
    const card = app.db.getCard(id);
    if (!card || card.userId !== user.id) {
      return reply.code(404).send({ error: "not_found" });
    }
    return card;
  });

  app.post("/api/games/cards/trades", async (request, reply) => {
    const user = requireUser(request, reply);
    const body = (request.body ?? {}) as { toUserId?: number; cardId?: number };
    const toUserId = Number(body.toUserId);
    const cardId = Number(body.cardId);
    if (!Number.isInteger(toUserId) || !Number.isInteger(cardId)) {
      return reply.code(400).send({ error: "toUserId_and_cardId_required" });
    }
    const id = app.db.createTrade(user.id, toUserId, cardId);
    return reply.code(201).send({ id });
  });

  app.post("/api/games/cards/trades/:id/accept", async (request, reply) => {
    const user = requireUser(request, reply);
    const params = request.params as { id: string };
    const id = parseId(params.id);
    try {
      return app.db.acceptTradeVulnerable(user.id, id);
    } catch (err) {
      return reply.code(404).send({ error: (err as Error).message });
    }
  });
};
