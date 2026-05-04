import path from "node:path";
import Fastify from "fastify";
import fastifyCookie from "@fastify/cookie";
import fastifyFormbody from "@fastify/formbody";
import fastifyStatic from "@fastify/static";
import fastifyView from "@fastify/view";
import nunjucks from "nunjucks";
import { config } from "./config.js";
import { Db } from "./services/db.js";
import { apiRoutes } from "./routes/api.js";
import { webRoutes } from "./routes/web.js";

async function buildServer() {
  const app = Fastify({ logger: true });
  const db = new Db(config.dbPath);
  app.decorate("db", db);

  await app.register(fastifyCookie, {
    secret: config.cookieSecret,
  });

  await app.register(fastifyFormbody);

  await app.register(fastifyStatic, {
    root: path.join(process.cwd(), "src", "public"),
    prefix: "/public/",
  });

  await app.register(fastifyView, {
    engine: { nunjucks },
    root: path.join(process.cwd(), "src", "views"),
    viewExt: "njk",
    options: {
      autoescape: true,
      noCache: true,
    },
  });

  app.addHook("preHandler", async (request) => {
    const token = request.cookies[config.cookieName];
    if (!token || typeof token !== "string") {
      request.currentUser = undefined;
      return;
    }
    request.currentUser = app.db.getSessionUser(token);
  });

  app.setErrorHandler((error, _request, reply) => {
    const message =
      typeof error === "object" && error !== null && "message" in error
        ? String(error.message)
        : "";
    if (message === "redirect_login" || message === "unauthorized") {
      return;
    }
    if (message === "invalid_id") {
      reply.code(400).send({ error: "invalid_id" });
      return;
    }
    app.log.error(error);
    reply.code(500).send({ error: "internal_error" });
  });

  await app.register(webRoutes);
  await app.register(apiRoutes);

  return app;
}

async function main() {
  const app = await buildServer();
  try {
    await app.listen({ host: config.host, port: config.port });
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
}

void main();
