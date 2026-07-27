import dotenv from "dotenv";
import { z } from "zod";

import { createApp } from "./app.js";

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
  SESSION_TTL_DAYS: z.coerce.number().int().min(1).max(365).default(30)
});

const env = envSchema.parse(process.env);
const app = await createApp({
  livekitUrl: env.LIVEKIT_URL,
  livekitApiKey: env.LIVEKIT_API_KEY,
  livekitApiSecret: env.LIVEKIT_API_SECRET,
  allowedOrigins: env.ALLOWED_ORIGINS,
  dataFile: env.DATA_FILE,
  appleBundleId: env.APPLE_BUNDLE_ID,
  sessionTTLDays: env.SESSION_TTL_DAYS
});

await app.listen({ port: env.PORT, host: "0.0.0.0" });
