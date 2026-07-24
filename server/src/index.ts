import cors from "@fastify/cors";
import dotenv from "dotenv";
import Fastify from "fastify";
import { AccessToken } from "livekit-server-sdk";
import { z } from "zod";

dotenv.config();

const envSchema = z.object({
  PORT: z.coerce.number().default(8080),
  LIVEKIT_URL: z.string().url(),
  LIVEKIT_API_KEY: z.string().min(1),
  LIVEKIT_API_SECRET: z.string().min(1),
  ALLOWED_ORIGINS: z.string().default("")
});

const env = envSchema.parse(process.env);
const app = Fastify({ logger: true });

await app.register(cors, {
  origin: env.ALLOWED_ORIGINS
    ? env.ALLOWED_ORIGINS.split(",").map((origin) => origin.trim())
    : true
});

app.get("/health", async () => ({
  ok: true,
  service: "bikegogogo-server"
}));

const tokenRequestSchema = z.object({
  identity: z.string().min(1).max(80),
  displayName: z.string().min(1).max(80),
  canPublish: z.boolean().default(true),
  canSubscribe: z.boolean().default(true)
});

app.post("/v1/voice/rooms/:groupId/token", async (request, reply) => {
  const params = z.object({ groupId: z.string().min(1).max(80) }).parse(request.params);
  const body = tokenRequestSchema.parse(request.body);
  const roomName = `group-${params.groupId}`;

  const token = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, {
    identity: body.identity,
    name: body.displayName,
    ttl: "2h"
  });

  token.addGrant({
    room: roomName,
    roomJoin: true,
    canPublish: body.canPublish,
    canSubscribe: body.canSubscribe,
    canPublishData: true,
    canUpdateOwnMetadata: true
  });

  return reply.send({
    url: env.LIVEKIT_URL,
    token: await token.toJwt(),
    roomName
  });
});

app.setErrorHandler((error, request, reply) => {
  request.log.error(error);

  if (error instanceof z.ZodError) {
    return reply.status(400).send({
      error: "invalid_request",
      details: error.flatten()
    });
  }

  return reply.status(500).send({
    error: "internal_server_error"
  });
});

await app.listen({ port: env.PORT, host: "0.0.0.0" });

