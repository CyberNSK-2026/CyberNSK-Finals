import type { Db } from "./services/db.js";
import type { User } from "./types.js";

declare module "fastify" {
  interface FastifyInstance {
    db: Db;
  }

  interface FastifyRequest {
    currentUser?: User;
  }
}