import cors from "@fastify/cors";
import rateLimit from "@fastify/rate-limit";
import { createHash } from "node:crypto";
import Fastify, { type FastifyRequest } from "fastify";
import { AccessToken } from "livekit-server-sdk";
import { z } from "zod";

import {
  AppleIdentityError,
  createAppleIdentityVerifier,
  type AppleIdentityVerifier
} from "./apple-auth.js";
import {
  DataStore,
  StoreError,
  type FriendRequestRecord,
  type UserRecord
} from "./data-store.js";

export type AppConfig = {
  livekitUrl: string;
  livekitApiKey: string;
  livekitApiSecret: string;
  allowedOrigins: string;
  dataFile: string;
  appleBundleId: string;
  sessionTTLDays: number;
  appleIdentityVerifier?: AppleIdentityVerifier;
};

const publicUser = (user: UserRecord) => ({
  id: user.id,
  displayName: user.displayName,
  friendCode: user.friendCode,
  createdAt: user.createdAt,
  updatedAt: user.updatedAt,
  authProvider: user.appleSubject ? "apple" : "guest"
});

const publicFriendRequest = (
  request: FriendRequestRecord,
  otherUser: UserRecord
) => ({
  id: request.id,
  status: request.status,
  createdAt: request.createdAt,
  updatedAt: request.updatedAt,
  user: publicUser(otherUser)
});

export async function createApp(config: AppConfig) {
  const app = Fastify({ logger: true });
  const store = new DataStore(
    config.dataFile,
    config.sessionTTLDays * 24 * 60 * 60 * 1000
  );
  const verifyAppleIdentity = config.appleIdentityVerifier
    ?? createAppleIdentityVerifier(config.appleBundleId);
  await store.initialize();

  await app.register(cors, {
    origin: config.allowedOrigins
      ? config.allowedOrigins.split(",").map((origin) => origin.trim())
      : false
  });
  await app.register(rateLimit, {
    global: true,
    max: 120,
    timeWindow: "1 minute"
  });

  const authenticatedUser = (request: FastifyRequest): UserRecord => {
    const authorization = request.headers.authorization;
    if (!authorization?.startsWith("Bearer ")) {
      throw new StoreError("unauthorized", 401, "Authentication required");
    }
    const user = store.userForAccessToken(authorization.slice(7));
    if (!user) {
      throw new StoreError("invalid_session", 401, "Session is invalid");
    }
    return user;
  };

  const optionalAuthenticatedUser = (
    request: FastifyRequest
  ): UserRecord | undefined => {
    const authorization = request.headers.authorization;
    if (!authorization) return undefined;
    return authenticatedUser(request);
  };

  app.get("/health", async () => ({
    ok: true,
    service: "bikegogogo-server"
  }));

  const guestAuthSchema = z.object({
    deviceId: z.string().min(16).max(128),
    displayName: z.string().trim().min(2).max(30)
  });

  app.post("/v1/auth/guest", {
    config: { rateLimit: { max: 10, timeWindow: "1 minute" } }
  }, async (request) => {
    const body = guestAuthSchema.parse(request.body);
    const session = await store.signInGuest(body.deviceId, body.displayName);
    return {
      accessToken: session.accessToken,
      user: publicUser(session.user)
    };
  });

  const appleAuthSchema = z.object({
    identityToken: z.string().min(100).max(10_000),
    rawNonce: z.string().min(16).max(128),
    deviceId: z.string().min(16).max(128),
    displayName: z.string().trim().min(2).max(30).optional()
  });

  app.post("/v1/auth/apple", {
    config: { rateLimit: { max: 10, timeWindow: "1 minute" } }
  }, async (request) => {
    const body = appleAuthSchema.parse(request.body);
    const currentUser = optionalAuthenticatedUser(request);
    const identity = await verifyAppleIdentity(body.identityToken, body.rawNonce);
    const session = await store.signInWithApple({
      subject: identity.subject,
      email: identity.email,
      displayName: body.displayName,
      deviceId: body.deviceId,
      currentUserId: currentUser?.id
    });
    return {
      accessToken: session.accessToken,
      user: publicUser(session.user)
    };
  });

  app.delete("/v1/session", async (request, reply) => {
    authenticatedUser(request);
    const accessToken = request.headers.authorization!.slice(7);
    await store.revokeSession(accessToken);
    return reply.status(204).send();
  });

  app.get("/v1/me", async (request) => ({
    user: publicUser(authenticatedUser(request))
  }));

  const updateProfileSchema = z.object({
    displayName: z.string().trim().min(2).max(30)
  });

  app.patch("/v1/me", async (request) => {
    const currentUser = authenticatedUser(request);
    const body = updateProfileSchema.parse(request.body);
    const user = await store.updateProfile(currentUser.id, body.displayName);
    return { user: publicUser(user) };
  });

  app.get("/v1/friends", async (request) => {
    const currentUser = authenticatedUser(request);
    return { friends: store.friendsFor(currentUser.id).map(publicUser) };
  });

  app.get("/v1/friends/requests", async (request) => {
    const currentUser = authenticatedUser(request);
    const requests = store.friendRequestsFor(currentUser.id);

    return {
      incoming: requests.incoming.map((friendRequest) =>
        publicFriendRequest(
          friendRequest,
          store.userById(friendRequest.fromUserId)!
        )
      ),
      outgoing: requests.outgoing.map((friendRequest) =>
        publicFriendRequest(
          friendRequest,
          store.userById(friendRequest.toUserId)!
        )
      )
    };
  });

  const friendCodeSchema = z.object({
    friendCode: z.string().trim().length(8).transform((value) => value.toUpperCase())
  });

  app.post("/v1/friends/requests", async (request, reply) => {
    const currentUser = authenticatedUser(request);
    const body = friendCodeSchema.parse(request.body);
    const friendRequest = await store.createFriendRequest(
      currentUser.id,
      body.friendCode
    );
    const otherUserId = friendRequest.fromUserId === currentUser.id
      ? friendRequest.toUserId
      : friendRequest.fromUserId;
    return reply.status(friendRequest.status === "accepted" ? 200 : 201).send({
      request: publicFriendRequest(
        friendRequest,
        store.userById(otherUserId)!
      )
    });
  });

  const friendRequestParamsSchema = z.object({
    requestId: z.string().startsWith("frq_")
  });

  for (const action of ["accept", "reject"] as const) {
    app.post(
      `/v1/friends/requests/:requestId/${action}`,
      async (request) => {
        const currentUser = authenticatedUser(request);
        const params = friendRequestParamsSchema.parse(request.params);
        const friendRequest = await store.respondToFriendRequest(
          params.requestId,
          currentUser.id,
          action
        );
        return { request: { id: friendRequest.id, status: friendRequest.status } };
      }
    );
  }

  const tokenRequestSchema = z.object({
    canPublish: z.boolean().default(true),
    canSubscribe: z.boolean().default(true)
  });

  app.post("/v1/voice/rooms/:groupId/token", {
    config: { rateLimit: { max: 30, timeWindow: "1 minute" } }
  }, async (request, reply) => {
    const currentUser = authenticatedUser(request);
    const params = z.object({
      groupId: z.string().startsWith("usr_").max(80)
    }).parse(request.params);
    const body = tokenRequestSchema.parse(request.body);
    if (!store.userById(params.groupId)) {
      throw new StoreError("voice_peer_not_found", 404, "Voice peer not found");
    }
    if (!store.areFriends(currentUser.id, params.groupId)) {
      throw new StoreError(
        "voice_room_forbidden",
        403,
        "Both users must accept the friendship before joining voice"
      );
    }

    const pair = [currentUser.id, params.groupId].sort().join(":");
    const roomName = `friends-${createHash("sha256").update(pair).digest("hex").slice(0, 32)}`;
    const token = new AccessToken(config.livekitApiKey, config.livekitApiSecret, {
      identity: currentUser.id,
      name: currentUser.displayName,
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
      url: config.livekitUrl,
      token: await token.toJwt(),
      roomName
    });
  });

  app.setErrorHandler((error, request, reply) => {
    if (error instanceof z.ZodError) {
      request.log.warn({ validationErrors: error.issues }, "Request validation failed");
      return reply.status(400).send({
        error: "invalid_request",
        message: "Request validation failed",
        details: error.flatten()
      });
    }

    if (error instanceof StoreError) {
      request.log.warn({ code: error.code }, error.message);
      return reply.status(error.statusCode).send({
        error: error.code,
        message: error.message
      });
    }

    if (error instanceof AppleIdentityError) {
      request.log.warn({ code: "invalid_apple_identity" }, error.message);
      return reply.status(401).send({
        error: "invalid_apple_identity",
        message: error.message
      });
    }

    request.log.error(error);
    return reply.status(500).send({
      error: "internal_server_error",
      message: "Internal server error"
    });
  });

  return app;
}
