import dotenv from "dotenv";
import { z } from "zod";

import { createAdminApp } from "./app.js";

dotenv.config();

const optional = z.preprocess((value) => value === "" ? undefined : value, z.string().min(1).optional());
const env = z.object({
  PORT: z.coerce.number().int().min(1).max(65_535).default(8082),
  DATABASE_URL: z.string().min(1),
  ADMIN_ENCRYPTION_SECRET: z.string().min(32),
  ADMIN_INITIAL_USERNAME: optional,
  ADMIN_INITIAL_PASSWORD_HASH: optional,
  ADMIN_INITIAL_TOTP_SECRET: optional,
  ADMIN_COOKIE_SECURE: z.enum(["true", "false"]).default("true"),
  TRUST_PROXY_HOPS: z.coerce.number().int().min(0).max(10).default(1),
  APP_REVISION: z.string().default("development"),
  ADMIN_PUBLIC_DIR: z.string().default("./public")
}).parse(process.env);

const bootstrapValues = [
  env.ADMIN_INITIAL_USERNAME,
  env.ADMIN_INITIAL_PASSWORD_HASH,
  env.ADMIN_INITIAL_TOTP_SECRET
];
if (bootstrapValues.some(Boolean) && bootstrapValues.some((value) => !value)) {
  throw new Error("ADMIN_INITIAL_USERNAME, ADMIN_INITIAL_PASSWORD_HASH and ADMIN_INITIAL_TOTP_SECRET must be configured together");
}

const app = await createAdminApp({
  databaseUrl: env.DATABASE_URL,
  encryptionSecret: env.ADMIN_ENCRYPTION_SECRET,
  initialUsername: env.ADMIN_INITIAL_USERNAME,
  initialPasswordHash: env.ADMIN_INITIAL_PASSWORD_HASH,
  initialTOTPSecret: env.ADMIN_INITIAL_TOTP_SECRET,
  cookieSecure: env.ADMIN_COOKIE_SECURE === "true",
  trustProxy: env.TRUST_PROXY_HOPS === 0 ? false : env.TRUST_PROXY_HOPS,
  revision: env.APP_REVISION,
  publicDirectory: env.ADMIN_PUBLIC_DIR
});

await app.listen({ host: "0.0.0.0", port: env.PORT });

const shutdown = async () => {
  await app.close();
  process.exit(0);
};
process.once("SIGTERM", () => void shutdown());
process.once("SIGINT", () => void shutdown());
