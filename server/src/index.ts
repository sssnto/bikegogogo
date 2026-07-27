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

const envSchema = z.object({
  PORT: z.coerce.number().default(8080),
  LIVEKIT_URL: z.string().url(),
  LIVEKIT_API_KEY: liveKitCredential("LIVEKIT_API_KEY"),
  LIVEKIT_API_SECRET: liveKitCredential("LIVEKIT_API_SECRET"),
  ALLOWED_ORIGINS: z.string().default(""),
  DATA_FILE: z.string().default("./data/bikegogogo.json"),
  APPLE_BUNDLE_ID: z.string().default("com.sssnto.BikeGoGo"),
  SESSION_TTL_DAYS: z.coerce.number().int().min(1).max(365).default(30),
  APNS_KEY_ID: z.string().min(1).optional(),
  APNS_TEAM_ID: z.string().min(1).optional(),
  APNS_TOPIC: z.string().min(1).optional(),
  APNS_KEY_PATH: z.string().min(1).optional(),
  APNS_ENVIRONMENT: z.enum(["sandbox", "production"]).default("sandbox")
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

let notificationSender: NotificationSender | undefined;
if (apnsConfigured) {
  notificationSender = await createAPNsSender({
    keyId: env.APNS_KEY_ID!,
    teamId: env.APNS_TEAM_ID!,
    topic: env.APNS_TOPIC!,
    privateKeyPath: env.APNS_KEY_PATH!,
    environment: env.APNS_ENVIRONMENT as APNsEnvironment
  });
}

const app = await createApp({
  livekitUrl: env.LIVEKIT_URL,
  livekitApiKey: env.LIVEKIT_API_KEY,
  livekitApiSecret: env.LIVEKIT_API_SECRET,
  allowedOrigins: env.ALLOWED_ORIGINS,
  dataFile: env.DATA_FILE,
  appleBundleId: env.APPLE_BUNDLE_ID,
  sessionTTLDays: env.SESSION_TTL_DAYS,
  notificationSender
});

await app.listen({ port: env.PORT, host: "0.0.0.0" });
