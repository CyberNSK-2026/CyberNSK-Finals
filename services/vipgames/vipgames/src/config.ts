import path from "node:path";

export const config = {
  host: process.env.HOST ?? "0.0.0.0",
  port: Number(process.env.PORT ?? "3000"),
  dbPath: process.env.DB_PATH ?? path.join(process.cwd(), "data", "vipgames.db"),
  cookieName: "vip_sid",
  cookieSecret: process.env.COOKIE_SECRET ?? "vip-cookie-secret-change-me",
};