import fs from "node:fs";
import path from "node:path";
import Database from "better-sqlite3";
import { randomBytes } from "node:crypto";
import type { GameKey, User, UserStats } from "../types.js";

export class Db {
  private readonly db: Database.Database;

  constructor(dbPath: string) {
    fs.mkdirSync(path.dirname(dbPath), { recursive: true });
    this.db = new Database(dbPath);
    this.db.pragma("journal_mode = WAL");
    this.db.pragma("foreign_keys = ON");
    this.init();
  }

  private init(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS sessions (
        token TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );

      CREATE TABLE IF NOT EXISTS game_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        game TEXT NOT NULL,
        score INTEGER NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );

      CREATE TABLE IF NOT EXISTS achievement_journal (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        note TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );

      CREATE TABLE IF NOT EXISTS user_achievements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        code TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        points INTEGER NOT NULL,
        progress INTEGER NOT NULL DEFAULT 100,
        secret_note TEXT,
        unlocked_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );

      CREATE TABLE IF NOT EXISTS puzzle_boards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        stego_payload TEXT,
        tiles_seed TEXT NOT NULL,
        solved INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );

      CREATE TABLE IF NOT EXISTS pets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        tag TEXT NOT NULL,
        bio TEXT NOT NULL,
        rarity TEXT NOT NULL,
        state_json TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );

      CREATE TABLE IF NOT EXISTS pet_boosters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        payload TEXT NOT NULL,
        used INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );

      CREATE TABLE IF NOT EXISTS alchemy_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        recipe TEXT NOT NULL,
        state TEXT NOT NULL,
        steps_json TEXT NOT NULL,
        artifact_note TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );

      CREATE TABLE IF NOT EXISTS cards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        custom_name TEXT NOT NULL,
        power INTEGER NOT NULL,
        metadata_json TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );

      CREATE TABLE IF NOT EXISTS trades (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        from_user_id INTEGER NOT NULL,
        to_user_id INTEGER NOT NULL,
        card_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(from_user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(to_user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(card_id) REFERENCES cards(id) ON DELETE CASCADE
      );

      CREATE INDEX IF NOT EXISTS idx_game_runs_user_game ON game_runs(user_id, game);
      CREATE INDEX IF NOT EXISTS idx_achievements_user_code ON user_achievements(user_id, code);
      CREATE INDEX IF NOT EXISTS idx_journal_user ON achievement_journal(user_id);
    `);
  }

  createUser(username: string, passwordHash: string): number {
    const stmt = this.db.prepare(
      "INSERT INTO users(username, password_hash) VALUES (?, ?)"
    );
    const info = stmt.run(username, passwordHash);
    return Number(info.lastInsertRowid);
  }

  getUserByUsername(username: string): User | undefined {
    const row = this.db
      .prepare("SELECT id, username, password_hash, created_at FROM users WHERE username = ?")
      .get(username) as
      | { id: number; username: string; password_hash: string; created_at: string }
      | undefined;
    if (!row) {
      return undefined;
    }
    return {
      id: row.id,
      username: row.username,
      passwordHash: row.password_hash,
      createdAt: row.created_at,
    };
  }

  getUserById(userId: number): User | undefined {
    const row = this.db
      .prepare("SELECT id, username, password_hash, created_at FROM users WHERE id = ?")
      .get(userId) as
      | { id: number; username: string; password_hash: string; created_at: string }
      | undefined;
    if (!row) {
      return undefined;
    }
    return {
      id: row.id,
      username: row.username,
      passwordHash: row.password_hash,
      createdAt: row.created_at,
    };
  }

  createSession(userId: number): string {
    const token = randomBytes(24).toString("hex");
    this.db.prepare("INSERT INTO sessions(token, user_id) VALUES (?, ?)").run(token, userId);
    return token;
  }

  getSessionUser(token: string): User | undefined {
    const row = this.db
      .prepare(
        `SELECT u.id, u.username, u.password_hash, u.created_at
         FROM sessions s
         JOIN users u ON u.id = s.user_id
         WHERE s.token = ?`
      )
      .get(token) as
      | { id: number; username: string; password_hash: string; created_at: string }
      | undefined;
    if (!row) {
      return undefined;
    }
    return {
      id: row.id,
      username: row.username,
      passwordHash: row.password_hash,
      createdAt: row.created_at,
    };
  }

  clearSession(token: string): void {
    this.db.prepare("DELETE FROM sessions WHERE token = ?").run(token);
  }

  addGameRun(userId: number, game: GameKey, score: number, status = "completed"): void {
    this.db
      .prepare("INSERT INTO game_runs(user_id, game, score, status) VALUES (?, ?, ?, ?)")
      .run(userId, game, score, status);
  }

  getUserStats(userId: number): UserStats {
    const row = this.db
      .prepare(
        `SELECT
          COUNT(*) AS total_runs,
          SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_runs,
          COALESCE(AVG(score), 0) AS avg_score
         FROM game_runs
         WHERE user_id = ?`
      )
      .get(userId) as { total_runs: number; completed_runs: number | null; avg_score: number };

    return {
      totalRuns: row.total_runs,
      completedRuns: row.completed_runs ?? 0,
      averageScore: Number(row.avg_score.toFixed(2)),
    };
  }

  putJournal(userId: number, title: string, note: string): number {
    const info = this.db
      .prepare("INSERT INTO achievement_journal(user_id, title, note) VALUES (?, ?, ?)")
      .run(userId, title, note);
    return Number(info.lastInsertRowid);
  }

  unlockAchievement(userId: number, code: string, sourceEntryId?: number): number {
    const mapping = {
      ARCHIVIST: {
        title: "Royal Archivist",
        description: "Preserved a chronicle for the realm.",
        points: 70,
      },
      PUZZLE_KNIGHT: {
        title: "Puzzle Knight",
        description: "Solved a stained-glass board.",
        points: 40,
      },
      BREEDER: {
        title: "Pet Breeder",
        description: "Raised a rare companion.",
        points: 35,
      },
      ALCHEMIST: {
        title: "Alchemy Master",
        description: "Distilled a stable artifact.",
        points: 45,
      },
      CARD_KEEPER: {
        title: "Card Keeper",
        description: "Expanded the royal deck.",
        points: 25,
      },
    } as const;

    const meta = mapping[code as keyof typeof mapping] ?? {
      title: "Unknown Mark",
      description: "An obscure feat.",
      points: 10,
    };

    let secretNote: string | null = null;
    if (sourceEntryId) {
      const row = this.db
        .prepare("SELECT note FROM achievement_journal WHERE id = ?")
        .get(sourceEntryId) as { note: string } | undefined;
      secretNote = row?.note ?? null;
    }

    const info = this.db
      .prepare(
        `INSERT INTO user_achievements(user_id, code, title, description, points, secret_note)
         VALUES (?, ?, ?, ?, ?, ?)`
      )
      .run(userId, code, meta.title, meta.description, meta.points, secretNote);

    return Number(info.lastInsertRowid);
  }

  listAchievements(userId: number): Array<Record<string, unknown>> {
    return this.db
      .prepare(
        `SELECT id, code, title, description, points, progress, unlocked_at
         FROM user_achievements
         WHERE user_id = ?
         ORDER BY id DESC`
      )
      .all(userId) as Array<Record<string, unknown>>;
  }

  // Vulnerable by design: this function ignores board owner binding and leaks foreign secret_note by code.
  getAchievementDetailsVulnerable(
    _boardUsername: string,
    code: string,
    achievementId?: number
  ): Record<string, unknown> | undefined {
    if (achievementId) {
      return this.db
        .prepare(
          `SELECT ua.id, ua.code, ua.title, ua.description, ua.points, ua.secret_note AS secretNote,
                  u.username AS owner
           FROM user_achievements ua
           JOIN users u ON u.id = ua.user_id
           WHERE ua.id = ?
           LIMIT 1`
        )
        .get(achievementId) as Record<string, unknown> | undefined;
    }

    return this.db
      .prepare(
        `SELECT ua.id, ua.code, ua.title, ua.description, ua.points, ua.secret_note AS secretNote,
                u.username AS owner
         FROM user_achievements ua
         JOIN users u ON u.id = ua.user_id
         WHERE ua.code = ?
         ORDER BY ua.id DESC
         LIMIT 1`
      )
      .get(code) as Record<string, unknown> | undefined;
  }

  createPuzzleBoard(userId: number, title: string): number {
    const seed = randomBytes(8).toString("hex");
    const info = this.db
      .prepare(
        "INSERT INTO puzzle_boards(user_id, title, stego_payload, tiles_seed, solved) VALUES (?, ?, NULL, ?, 0)"
      )
      .run(userId, title, seed);
    return Number(info.lastInsertRowid);
  }

  savePuzzleStego(userId: number, boardId: number, payload: string): void {
    this.db
      .prepare(
        "UPDATE puzzle_boards SET stego_payload = ?, solved = 1 WHERE id = ? AND user_id = ?"
      )
      .run(payload, boardId, userId);
    this.addGameRun(userId, "puzzle", 100);
    this.unlockAchievement(userId, "PUZZLE_KNIGHT");
  }

  getPuzzleBoard(boardId: number): Record<string, unknown> | undefined {
    return this.db
      .prepare(
        "SELECT id, user_id AS userId, title, stego_payload AS stegoPayload, tiles_seed AS tilesSeed, solved FROM puzzle_boards WHERE id = ?"
      )
      .get(boardId) as Record<string, unknown> | undefined;
  }

  createPet(userId: number, name: string, tag: string): number {
    const info = this.db
      .prepare(
        `INSERT INTO pets(user_id, name, tag, bio, rarity, state_json)
         VALUES (?, ?, ?, 'A loyal stable friend.', 'common', '{"fed":0,"wins":0}')`
      )
      .run(userId, name, tag);
    this.addGameRun(userId, "petfarm", 60);
    this.unlockAchievement(userId, "BREEDER");
    return Number(info.lastInsertRowid);
  }

  createBooster(userId: number, payload: string): number {
    const info = this.db
      .prepare("INSERT INTO pet_boosters(user_id, payload, used) VALUES (?, ?, 0)")
      .run(userId, payload);
    return Number(info.lastInsertRowid);
  }

  // Vulnerable by design: validates booster ownership but does not check target pet owner.
  applyBoosterVulnerable(userId: number, boosterId: number, petId: number): Record<string, unknown> {
    const booster = this.db
      .prepare("SELECT id, payload, used FROM pet_boosters WHERE id = ? AND user_id = ?")
      .get(boosterId, userId) as { id: number; payload: string; used: number } | undefined;

    if (!booster || booster.used) {
      throw new Error("booster_not_available");
    }

    const pet = this.getPet(petId);
    if (!pet) {
      throw new Error("pet_not_found");
    }

    this.db
      .prepare("UPDATE pets SET bio = ? WHERE id = ?")
      .run(`Blessed by ${booster.payload}.`, petId);
    this.db.prepare("UPDATE pet_boosters SET used = 1 WHERE id = ?").run(boosterId);
    return {
      ...pet,
      bio: `Blessed by ${booster.payload}.`,
      boosterPayload: booster.payload,
    };
  }

  getPet(petId: number): Record<string, unknown> | undefined {
    return this.db
      .prepare(
        "SELECT id, user_id AS userId, name, tag, bio, rarity, state_json AS stateJson FROM pets WHERE id = ?"
      )
      .get(petId) as Record<string, unknown> | undefined;
  }

  createAlchemyRun(userId: number, recipe: string): number {
    const info = this.db
      .prepare(
        `INSERT INTO alchemy_runs(user_id, recipe, state, steps_json)
         VALUES (?, ?, 'draft', '["draft"]')`
      )
      .run(userId, recipe);
    return Number(info.lastInsertRowid);
  }

  // Vulnerable by design: allows finalize without validating prior transition sequence or owner.
  finalizeAlchemyRunVulnerable(_userId: number, runId: number, artifactNote: string): Record<string, unknown> {
    const existing = this.getAlchemyArtifact(runId);
    if (!existing) {
      throw new Error("run_not_found");
    }
    if (existing.state === "finalize" && typeof existing.artifactNote === "string") {
      return existing;
    }

    this.db
      .prepare("UPDATE alchemy_runs SET state = 'finalize', artifact_note = ? WHERE id = ?")
      .run(artifactNote, runId);
    this.addGameRun(_userId, "alchemy", 90);
    this.unlockAchievement(_userId, "ALCHEMIST");
    return this.getAlchemyArtifact(runId) ?? existing;
  }

  getAlchemyArtifact(runId: number): Record<string, unknown> | undefined {
    return this.db
      .prepare(
        "SELECT id, user_id AS userId, recipe, state, artifact_note AS artifactNote FROM alchemy_runs WHERE id = ?"
      )
      .get(runId) as Record<string, unknown> | undefined;
  }

  createCard(userId: number, customName: string, power: number): number {
    const info = this.db
      .prepare(
        `INSERT INTO cards(user_id, custom_name, power, metadata_json)
         VALUES (?, ?, ?, '{"edition":"royal"}')`
      )
      .run(userId, customName, power);
    this.addGameRun(userId, "cards", Math.min(100, Math.max(1, power)));
    this.unlockAchievement(userId, "CARD_KEEPER");
    return Number(info.lastInsertRowid);
  }

  createTrade(fromUserId: number, toUserId: number, cardId: number): number {
    const info = this.db
      .prepare("INSERT INTO trades(from_user_id, to_user_id, card_id, status) VALUES (?, ?, ?, 'pending')")
      .run(fromUserId, toUserId, cardId);
    return Number(info.lastInsertRowid);
  }

  // Vulnerable by design: accepts trade without strong state ownership guarantees and duplicates the card.
  acceptTradeVulnerable(_userId: number, tradeId: number): Record<string, unknown> {
    const trade = this.db
      .prepare("SELECT id, to_user_id AS toUserId, card_id AS cardId FROM trades WHERE id = ?")
      .get(tradeId) as { id: number; toUserId: number; cardId: number } | undefined;
    if (!trade) {
      throw new Error("trade_not_found");
    }
    const card = this.getCard(trade.cardId);
    if (!card) {
      throw new Error("card_not_found");
    }
    const info = this.db
      .prepare(
        `INSERT INTO cards(user_id, custom_name, power, metadata_json)
         VALUES (?, ?, ?, ?)`
      )
      .run(trade.toUserId, card.customName, card.power, card.metadataJson);
    this.db.prepare("UPDATE trades SET status = 'accepted' WHERE id = ?").run(tradeId);
    return {
      ok: true,
      cardId: Number(info.lastInsertRowid),
      sourceCardId: trade.cardId,
    };
  }

  getCard(cardId: number): Record<string, unknown> | undefined {
    return this.db
      .prepare(
        "SELECT id, user_id AS userId, custom_name AS customName, power, metadata_json AS metadataJson FROM cards WHERE id = ?"
      )
      .get(cardId) as Record<string, unknown> | undefined;
  }

  listRecentRuns(limit = 20): Array<Record<string, unknown>> {
    return this.db
      .prepare(
        `SELECT gr.id, gr.game, gr.score, gr.status, gr.created_at AS createdAt, u.username
         FROM game_runs gr
         JOIN users u ON u.id = gr.user_id
         ORDER BY gr.id DESC
         LIMIT ?`
      )
      .all(limit) as Array<Record<string, unknown>>;
  }
}
