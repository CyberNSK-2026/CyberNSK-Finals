import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from "fastify";

function redirectToLogin(reply: FastifyReply): never {
  reply.redirect("/login");
  throw new Error("redirect_login");
}

function ensureUser(request: FastifyRequest, reply: FastifyReply) {
  if (!request.currentUser) {
    redirectToLogin(reply);
  }
  return request.currentUser;
}

export const webRoutes: FastifyPluginAsync = async (app) => {
  app.get("/", async (request, reply) => {
    const recentRuns = app.db.listRecentRuns(18);
    return reply.view("pages/index.njk", {
      title: "VIP Games",
      user: request.currentUser,
      recentRuns,
    });
  });

  app.get("/login", async (request, reply) => {
    if (request.currentUser) {
      return reply.redirect("/portal");
    }
    return reply.view("pages/login.njk", { title: "Login" });
  });

  app.get("/register", async (request, reply) => {
    if (request.currentUser) {
      return reply.redirect("/portal");
    }
    return reply.view("pages/register.njk", { title: "Register" });
  });

  app.get("/portal", async (request, reply) => {
    const user = ensureUser(request, reply);
    const stats = app.db.getUserStats(user.id);
    const achievements = app.db.listAchievements(user.id);
    return reply.view("pages/portal.njk", {
      title: "Player Portal",
      user,
      stats,
      achievements,
    });
  });

  app.get("/games/puzzle", async (request, reply) => {
    const user = ensureUser(request, reply);
    return reply.view("pages/game-puzzle.njk", { title: "Puzzle Forge", user });
  });

  app.get("/games/petfarm", async (request, reply) => {
    const user = ensureUser(request, reply);
    return reply.view("pages/game-petfarm.njk", { title: "Pet Farm", user });
  });

  app.get("/games/alchemy", async (request, reply) => {
    const user = ensureUser(request, reply);
    return reply.view("pages/game-alchemy.njk", { title: "Alchemy Lab", user });
  });

  app.get("/games/cards", async (request, reply) => {
    const user = ensureUser(request, reply);
    return reply.view("pages/game-cards.njk", { title: "Card Hall", user });
  });

  app.get("/achievements", async (request, reply) => {
    const user = ensureUser(request, reply);
    const achievements = app.db.listAchievements(user.id);
    return reply.view("pages/achievements.njk", {
      title: "Achievement Board",
      user,
      achievements,
    });
  });
};
