import cors from "@fastify/cors";
import Fastify, { type FastifyRequest } from "fastify";
import { AccessToken } from "livekit-server-sdk";
import { z } from "zod";

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
};

const publicUser = (user: UserRecord) => ({
  id: user.id,
  displayName: user.displayName,
  friendCode: user.friendCode,
  createdAt: user.createdAt,
  updatedAt: user.updatedAt
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
  const store = new DataStore(config.dataFile);
  await store.initialize();

  await app.register(cors, {
    origin: config.allowedOrigins
      ? config.allowedOrigins.split(",").map((origin) => origin.trim())
      : true
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

  app.post("/v1/auth/guest", async (request) => {
    const body = guestAuthSchema.parse(request.body);
    const session = await store.signInGuest(body.deviceId, body.displayName);
    return {
      accessToken: session.accessToken,
      user: publicUser(session.user)
    };
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
    identity: z.string().min(1).max(80).optional(),
    displayName: z.string().min(1).max(80).optional(),
    canPublish: z.boolean().default(true),
    canSubscribe: z.boolean().default(true)
  });

  app.post("/v1/voice/rooms/:groupId/token", async (request, reply) => {
    const params = z.object({ groupId: z.string().min(1).max(80) }).parse(request.params);
    const body = tokenRequestSchema.parse(request.body);
    const currentUser = optionalAuthenticatedUser(request);
    const identity = currentUser?.id ?? body.identity;
    const displayName = currentUser?.displayName ?? body.displayName;

    if (!identity || !displayName) {
      throw new StoreError(
        "missing_voice_identity",
        400,
        "Voice identity and display name are required"
      );
    }

    const roomName = `group-${params.groupId}`;
    const token = new AccessToken(config.livekitApiKey, config.livekitApiSecret, {
      identity,
      name: displayName,
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
    request.log.error(error);

    if (error instanceof z.ZodError) {
      return reply.status(400).send({
        error: "invalid_request",
        message: "Request validation failed",
        details: error.flatten()
      });
    }

    if (error instanceof StoreError) {
      return reply.status(error.statusCode).send({
        error: error.code,
        message: error.message
      });
    }

    return reply.status(500).send({
      error: "internal_server_error",
      message: "Internal server error"
    });
  });

  return app;
}
