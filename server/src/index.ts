import dotenv from "dotenv";
import { z } from "zod";

import { createApp } from "./app.js";
import {
  createAPNsSender,
  type APNsEnvironment,
  type NotificationSender
} from "./apns.js";

dotenv.config();

const liveKitCredential = (name: string) =>
  z.string()
    .min(1)
    .refine(
      (value) => !value.startsWith("your_"),
      `${name} still contains a placeholder value`
    );

const optionalNonEmptyString = z.preprocess(
  (value) => value === "" ? undefined : value,
  z.string().min(1).optional()
);

const envSchema = z.object({
  PORT: z.coerce.number().default(8080),
  LIVEKIT_URL: z.string().url(),
  LIVEKIT_API_KEY: liveKitCredential("LIVEKIT_API_KEY"),
  LIVEKIT_API_SECRET: liveKitCredential("LIVEKIT_API_SECRET"),
  ALLOWED_ORIGINS: z.string().default(""),
  DATA_FILE: z.string().default("./data/bikegogogo.json"),
  DATABASE_URL: z.string().min(1).optional(),
  APPLE_BUNDLE_ID: z.string().default("com.sssnto.BikeGoGo"),
  SESSION_TTL_DAYS: z.coerce.number().int().min(1).max(365).default(30),
  TRUST_PROXY_HOPS: z.coerce.number().int().min(0).max(10).default(1),
  APP_REVISION: z.string().min(1).default("development"),
  APNS_KEY_ID: z.string().min(1).optional(),
  APNS_TEAM_ID: z.string().min(1).optional(),
  APNS_TOPIC: z.string().min(1).optional(),
  APNS_KEY_PATH: z.string().min(1).optional(),
  APNS_ENVIRONMENT: z.enum(["sandbox", "production"]).default("sandbox"),
  APNS_PRODUCTION_KEY_ID: optionalNonEmptyString,
  APNS_PRODUCTION_KEY_PATH: z.string().min(1)
    .default("/run/secrets/apns-production-key.p8")
});

const env = envSchema.parse(process.env);
const apnsValues = [
  env.APNS_KEY_ID,
  env.APNS_TEAM_ID,
  env.APNS_TOPIC,
  env.APNS_KEY_PATH
];
const apnsConfigured = apnsValues.some(Boolean);
if (apnsConfigured && apnsValues.some((value) => !value)) {
  throw new Error(
    "APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC and APNS_KEY_PATH must be configured together"
  );
}

const notificationSenders: NotificationSender[] = [];
if (apnsConfigured) {
  notificationSenders.push(await createAPNsSender({
    keyId: env.APNS_KEY_ID!,
    teamId: env.APNS_TEAM_ID!,
    topic: env.APNS_TOPIC!,
    privateKeyPath: env.APNS_KEY_PATH!,
    environment: env.APNS_ENVIRONMENT as APNsEnvironment
  }));
}

if (env.APNS_PRODUCTION_KEY_ID) {
  if (!env.APNS_TEAM_ID || !env.APNS_TOPIC) {
    throw new Error(
      "APNS_TEAM_ID and APNS_TOPIC are required with APNS_PRODUCTION_KEY_ID"
    );
  }
  if (env.APNS_ENVIRONMENT === "production" && apnsConfigured) {
    throw new Error(
      "APNS_PRODUCTION_KEY_ID duplicates the production APNS_ENVIRONMENT"
    );
  }
  notificationSenders.push(await createAPNsSender({
    keyId: env.APNS_PRODUCTION_KEY_ID,
    teamId: env.APNS_TEAM_ID,
    topic: env.APNS_TOPIC,
    privateKeyPath: env.APNS_PRODUCTION_KEY_PATH,
    environment: "production"
  }));
}

const app = await createApp({
  livekitUrl: env.LIVEKIT_URL,
  livekitApiKey: env.LIVEKIT_API_KEY,
  livekitApiSecret: env.LIVEKIT_API_SECRET,
  allowedOrigins: env.ALLOWED_ORIGINS,
  dataFile: env.DATA_FILE,
  databaseUrl: env.DATABASE_URL,
  appleBundleId: env.APPLE_BUNDLE_ID,
  sessionTTLDays: env.SESSION_TTL_DAYS,
  trustProxy: env.TRUST_PROXY_HOPS === 0 ? false : env.TRUST_PROXY_HOPS,
  revision: env.APP_REVISION,
  notificationSenders
});

await app.listen({ port: env.PORT, host: "0.0.0.0" });

let isShuttingDown = false;
const shutdown = async (signal: NodeJS.Signals): Promise<void> => {
  if (isShuttingDown) return;
  isShuttingDown = true;
  app.log.info({ signal }, "Graceful shutdown started");

  const forcedExit = setTimeout(() => {
    app.log.error({ signal }, "Graceful shutdown timed out");
    process.exit(1);
  }, 25_000);
  forcedExit.unref();

  try {
    await app.close();
    clearTimeout(forcedExit);
    app.log.info({ signal }, "Graceful shutdown completed");
  } catch (error) {
    clearTimeout(forcedExit);
    app.log.error({ err: error, signal }, "Graceful shutdown failed");
    process.exitCode = 1;
  }
};

process.once("SIGTERM", () => void shutdown("SIGTERM"));
process.once("SIGINT", () => void shutdown("SIGINT"));
