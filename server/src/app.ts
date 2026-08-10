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
import type {
  NotificationSender,
  PushNotification
} from "./apns.js";
import {
  DataStore,
  StoreError,
  type FriendRequestRecord,
  type GroupRecord,
  type RideRecord,
  type UserRecord,
  type VoiceInvitationRecord
} from "./data-store.js";
import {
  LiveLocationStore,
  MeetingPointStore,
  type LiveLocationRecord,
  type MeetingPointRecord
} from "./live-location-store.js";

export type AppConfig = {
  livekitUrl: string;
  livekitApiKey: string;
  livekitApiSecret: string;
  allowedOrigins: string;
  dataFile: string;
  databaseUrl?: string;
  appleBundleId: string;
  sessionTTLDays: number;
  appleIdentityVerifier?: AppleIdentityVerifier;
  notificationSenders?: NotificationSender[];
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

const publicGroup = (store: DataStore, group: GroupRecord, currentUserId: string) => ({
  id: group.id,
  name: group.name,
  owner: publicUser(store.userById(group.ownerId)!),
  members: group.memberIds
    .map((memberId) => store.userById(memberId))
    .filter((member): member is UserRecord => Boolean(member))
    .map(publicUser),
  isOwner: group.ownerId === currentUserId,
  createdAt: group.createdAt,
  updatedAt: group.updatedAt
});

const publicRide = (ride: RideRecord) => ({
  id: ride.id,
  title: ride.title,
  state: ride.state,
  source: ride.source,
  startedAt: ride.startedAt,
  endedAt: ride.endedAt,
  points: ride.points,
  metrics: ride.metrics,
  weather: ride.weather
});

const publicVoiceInvitation = (
  store: DataStore,
  invitation: VoiceInvitationRecord
) => ({
  id: invitation.id,
  caller: publicUser(store.userById(invitation.callerId)!),
  targetId: invitation.targetId,
  targetKind: invitation.targetKind,
  targetName: invitation.targetName,
  createdAt: invitation.createdAt,
  expiresAt: invitation.expiresAt
});

const publicLiveLocation = (
  store: DataStore,
  location: LiveLocationRecord
) => ({
  user: publicUser(store.userById(location.userId)!),
  latitude: location.latitude,
  longitude: location.longitude,
  horizontalAccuracyMeters: location.horizontalAccuracyMeters,
  speedMetersPerSecond: location.speedMetersPerSecond,
  courseDegrees: location.courseDegrees,
  capturedAt: location.capturedAt,
  updatedAt: location.updatedAt
});

const publicMeetingPoint = (
  store: DataStore,
  meetingPoint: MeetingPointRecord
) => ({
  setBy: publicUser(store.userById(meetingPoint.setByUserId)!),
  latitude: meetingPoint.latitude,
  longitude: meetingPoint.longitude,
  title: meetingPoint.title,
  horizontalAccuracyMeters: meetingPoint.horizontalAccuracyMeters,
  capturedAt: meetingPoint.capturedAt,
  updatedAt: meetingPoint.updatedAt,
  expiresAt: meetingPoint.expiresAt
});

export async function createApp(config: AppConfig) {
  const app = Fastify({ logger: true, bodyLimit: 15 * 1024 * 1024 });
  const store = new DataStore(
    config.dataFile,
    config.sessionTTLDays * 24 * 60 * 60 * 1000,
    config.databaseUrl
  );
  const verifyAppleIdentity = config.appleIdentityVerifier
    ?? createAppleIdentityVerifier(config.appleBundleId);
  const notificationSenders = config.notificationSenders ?? [];
  const liveLocations = new LiveLocationStore();
  const meetingPoints = new MeetingPointStore();
  await store.initialize();
  app.log.info({ storage: store.storageBackend }, "Data store initialized");
  app.addHook("onClose", async () => {
    await store.close();
  });

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

  const notifyUser = async (
    userId: string,
    notification: PushNotification
  ): Promise<void> => {
    await Promise.all(notificationSenders.map(async (sender) => {
      const tokens = store.pushTokensFor(userId, sender.environment);
      if (tokens.length === 0) return;

      try {
        const result = await sender.send(tokens, notification);
        await store.removePushTokens(result.invalidTokens, sender.environment);
        if (result.failedCount > 0) {
          app.log.warn(
            {
              environment: sender.environment,
              failedCount: result.failedCount,
              event: notification.event
            },
            "Some push notifications were rejected by APNs"
          );
        }
      } catch (error) {
        app.log.error(
          {
            err: error,
            environment: sender.environment,
            event: notification.event
          },
          "Push notification delivery failed"
        );
      }
    }));
  };

  app.get("/health", async (_request, reply) => {
    try {
      await store.healthCheck();
      return {
        ok: true,
        service: "bikegogogo-server",
        storage: store.storageBackend
      };
    } catch (error) {
      app.log.error({ err: error }, "Data store health check failed");
      return reply.status(503).send({
        ok: false,
        service: "bikegogogo-server",
        storage: store.storageBackend
      });
    }
  });

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

  app.get("/v1/me/export", async (request) => {
    const currentUser = authenticatedUser(request);
    const requests = store.friendRequestsFor(currentUser.id);
    return {
      formatVersion: 1,
      exportedAt: new Date().toISOString(),
      account: {
        ...publicUser(currentUser),
        email: currentUser.email
      },
      friends: store.friendsFor(currentUser.id).map(publicUser),
      friendRequests: {
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
      },
      groups: store.groupsFor(currentUser.id).map(
        (group) => publicGroup(store, group, currentUser.id)
      ),
      rides: store.ridesFor(currentUser.id).map(publicRide)
    };
  });

  const deleteAccountSchema = z.object({
    confirmation: z.literal("DELETE")
  });

  app.delete("/v1/me", {
    config: { rateLimit: { max: 3, timeWindow: "1 hour" } }
  }, async (request, reply) => {
    const currentUser = authenticatedUser(request);
    deleteAccountSchema.parse(request.body);
    const result = await store.deleteAccount(currentUser.id);
    liveLocations.removeUser(currentUser.id);
    meetingPoints.removeUser(currentUser.id);
    result.deletedOwnedGroupIds.forEach((groupId) => {
      liveLocations.removeGroup(groupId);
      meetingPoints.removeGroup(groupId);
    });
    return reply.status(204).send();
  });

  const updateProfileSchema = z.object({
    displayName: z.string().trim().min(2).max(30)
  });

  app.patch("/v1/me", async (request) => {
    const currentUser = authenticatedUser(request);
    const body = updateProfileSchema.parse(request.body);
    const user = await store.updateProfile(currentUser.id, body.displayName);
    return { user: publicUser(user) };
  });

  const pushTokenSchema = z.object({
    token: z.string().trim().min(32).max(400).regex(/^[a-fA-F0-9]+$/),
    environment: z.enum(["sandbox", "production"])
  });

  app.put("/v1/devices/push-token", async (request, reply) => {
    const currentUser = authenticatedUser(request);
    const body = pushTokenSchema.parse(request.body);
    await store.registerPushToken(
      currentUser.id,
      body.token.toLowerCase(),
      body.environment
    );
    return reply.status(204).send();
  });

  app.delete("/v1/devices/push-token", async (request, reply) => {
    const currentUser = authenticatedUser(request);
    const body = pushTokenSchema.parse(request.body);
    await store.removePushToken(
      currentUser.id,
      body.token.toLowerCase(),
      body.environment
    );
    return reply.status(204).send();
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
    if (friendRequest.status === "accepted") {
      await notifyUser(friendRequest.fromUserId, {
        title: "好友申请已通过",
        body: `${currentUser.displayName} 已成为你的好友`,
        event: "friend_accepted",
        entityId: currentUser.id
      });
    } else {
      await notifyUser(friendRequest.toUserId, {
        title: "新的好友申请",
        body: `${currentUser.displayName} 想添加你为好友`,
        event: "friend_request",
        entityId: friendRequest.id
      });
    }
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
        if (action === "accept") {
          await notifyUser(friendRequest.fromUserId, {
            title: "好友申请已通过",
            body: `${currentUser.displayName} 已成为你的好友`,
            event: "friend_accepted",
            entityId: currentUser.id
          });
        }
        return { request: { id: friendRequest.id, status: friendRequest.status } };
      }
    );
  }

  const groupBodySchema = z.object({
    name: z.string().trim().min(2).max(40)
  });

  app.get("/v1/groups", async (request) => {
    const currentUser = authenticatedUser(request);
    return {
      groups: store.groupsFor(currentUser.id).map(
        (group) => publicGroup(store, group, currentUser.id)
      )
    };
  });

  app.post("/v1/groups", async (request, reply) => {
    const currentUser = authenticatedUser(request);
    const body = groupBodySchema.parse(request.body);
    const group = await store.createGroup(currentUser.id, body.name);
    return reply.status(201).send({
      group: publicGroup(store, group, currentUser.id)
    });
  });

  const groupParamsSchema = z.object({
    groupId: z.string().startsWith("grp_").max(80)
  });
  const groupMemberBodySchema = z.object({
    userId: z.string().startsWith("usr_").max(80)
  });
  const groupMemberParamsSchema = groupParamsSchema.extend({
    userId: z.string().startsWith("usr_").max(80)
  });

  app.post("/v1/groups/:groupId/members", async (request) => {
    const currentUser = authenticatedUser(request);
    const params = groupParamsSchema.parse(request.params);
    const body = groupMemberBodySchema.parse(request.body);
    const existingGroup = store.groupById(params.groupId);
    const wasAlreadyMember = existingGroup?.memberIds.includes(body.userId) ?? false;
    const group = await store.addGroupMember(
      params.groupId,
      currentUser.id,
      body.userId
    );
    if (!wasAlreadyMember) {
      await notifyUser(body.userId, {
        title: "小队邀请",
        body: `${currentUser.displayName} 邀请你加入「${group.name}」`,
        event: "group_invitation",
        entityId: group.id
      });
    }
    return { group: publicGroup(store, group, currentUser.id) };
  });

  app.delete("/v1/groups/:groupId/members/:userId", async (request) => {
    const currentUser = authenticatedUser(request);
    const params = groupMemberParamsSchema.parse(request.params);
    const group = await store.removeGroupMember(
      params.groupId,
      currentUser.id,
      params.userId
    );
    liveLocations.remove(params.groupId, params.userId);
    return { group: publicGroup(store, group, currentUser.id) };
  });

  app.delete("/v1/groups/:groupId", async (request, reply) => {
    const currentUser = authenticatedUser(request);
    const params = groupParamsSchema.parse(request.params);
    await store.deleteGroup(params.groupId, currentUser.id);
    liveLocations.removeGroup(params.groupId);
    meetingPoints.removeGroup(params.groupId);
    return reply.status(204).send();
  });

  const liveLocationBodySchema = z.object({
    latitude: z.number().min(-90).max(90),
    longitude: z.number().min(-180).max(180),
    horizontalAccuracyMeters: z.number().min(0).max(1_000).optional(),
    speedMetersPerSecond: z.number().min(0).max(100).optional(),
    courseDegrees: z.number().min(0).max(360).optional(),
    capturedAt: z.string().datetime()
  });
  const meetingPointBodySchema = z.object({
    latitude: z.number().min(-90).max(90),
    longitude: z.number().min(-180).max(180),
    title: z.string().trim().min(1).max(40).default("小队集合点"),
    horizontalAccuracyMeters: z.number().min(0).max(1_000).optional(),
    capturedAt: z.string().datetime()
  });

  const requireGroupMembership = (groupId: string, userId: string) => {
    const group = store.groupById(groupId);
    if (!group) {
      throw new StoreError("group_not_found", 404, "Group not found");
    }
    if (!group.memberIds.includes(userId)) {
      throw new StoreError(
        "group_membership_required",
        403,
        "Group membership required"
      );
    }
    return group;
  };

  const requireGroupOwnership = (groupId: string, userId: string) => {
    const group = requireGroupMembership(groupId, userId);
    if (group.ownerId !== userId) {
      throw new StoreError(
        "group_owner_required",
        403,
        "Group owner access required"
      );
    }
    return group;
  };

  app.get("/v1/groups/:groupId/live-locations", {
    config: { rateLimit: { max: 60, timeWindow: "1 minute" } }
  }, async (request) => {
    const currentUser = authenticatedUser(request);
    const params = groupParamsSchema.parse(request.params);
    requireGroupMembership(params.groupId, currentUser.id);
    return {
      locations: liveLocations.list(params.groupId)
        .filter((location) => store.userById(location.userId))
        .map((location) => publicLiveLocation(store, location))
    };
  });

  app.put("/v1/groups/:groupId/live-location", {
    config: { rateLimit: { max: 30, timeWindow: "1 minute" } }
  }, async (request) => {
    const currentUser = authenticatedUser(request);
    const params = groupParamsSchema.parse(request.params);
    const body = liveLocationBodySchema.parse(request.body);
    requireGroupMembership(params.groupId, currentUser.id);
    const location = liveLocations.upsert(
      params.groupId,
      currentUser.id,
      body
    );
    return { location: publicLiveLocation(store, location) };
  });

  app.delete("/v1/groups/:groupId/live-location", async (request, reply) => {
    const currentUser = authenticatedUser(request);
    const params = groupParamsSchema.parse(request.params);
    requireGroupMembership(params.groupId, currentUser.id);
    liveLocations.remove(params.groupId, currentUser.id);
    return reply.status(204).send();
  });

  app.get("/v1/groups/:groupId/meeting-point", async (request) => {
    const currentUser = authenticatedUser(request);
    const params = groupParamsSchema.parse(request.params);
    requireGroupMembership(params.groupId, currentUser.id);
    const meetingPoint = meetingPoints.get(params.groupId);
    return {
      meetingPoint: meetingPoint
        ? publicMeetingPoint(store, meetingPoint)
        : null
    };
  });

  app.put("/v1/groups/:groupId/meeting-point", async (request) => {
    const currentUser = authenticatedUser(request);
    const params = groupParamsSchema.parse(request.params);
    const body = meetingPointBodySchema.parse(request.body);
    const group = requireGroupOwnership(params.groupId, currentUser.id);
    const meetingPoint = meetingPoints.set(
      params.groupId,
      currentUser.id,
      body
    );
    const recipientIds = group.memberIds.filter(
      (memberId) => memberId !== currentUser.id
    );

    await Promise.all(recipientIds.map((recipientId) => notifyUser(
      recipientId,
      {
        title: "小队集合点已更新",
        body: `${currentUser.displayName} 将集合点设为「${meetingPoint.title}」`,
        event: "group_meeting_point_updated",
        entityId: params.groupId,
        data: {
          groupId: params.groupId,
          groupName: group.name,
          title: meetingPoint.title,
          latitude: String(meetingPoint.latitude),
          longitude: String(meetingPoint.longitude),
          expiresAt: meetingPoint.expiresAt
        }
      }
    )));

    return { meetingPoint: publicMeetingPoint(store, meetingPoint) };
  });

  app.delete("/v1/groups/:groupId/meeting-point", async (request, reply) => {
    const currentUser = authenticatedUser(request);
    const params = groupParamsSchema.parse(request.params);
    requireGroupOwnership(params.groupId, currentUser.id);
    meetingPoints.removeGroup(params.groupId);
    return reply.status(204).send();
  });

  app.post("/v1/groups/:groupId/sos", {
    config: { rateLimit: { max: 3, timeWindow: "10 minutes" } }
  }, async (request) => {
    const currentUser = authenticatedUser(request);
    const params = groupParamsSchema.parse(request.params);
    const body = liveLocationBodySchema.parse(request.body);
    const group = requireGroupMembership(params.groupId, currentUser.id);
    const location = liveLocations.upsert(
      params.groupId,
      currentUser.id,
      body
    );
    const recipientIds = group.memberIds.filter(
      (memberId) => memberId !== currentUser.id
    );

    await Promise.all(recipientIds.map((recipientId) => notifyUser(
      recipientId,
      {
        title: "小队紧急求助",
        body: `${currentUser.displayName} 在骑行中发出紧急求助，请尽快联系并查看位置。`,
        event: "group_sos",
        entityId: params.groupId,
        data: {
          groupId: params.groupId,
          groupName: group.name,
          senderUserId: currentUser.id,
          senderName: currentUser.displayName,
          latitude: String(location.latitude),
          longitude: String(location.longitude),
          capturedAt: location.capturedAt
        }
      }
    )));

    return {
      sent: true,
      recipientCount: recipientIds.length,
      location: publicLiveLocation(store, location)
    };
  });

  const tokenRequestSchema = z.object({
    canPublish: z.boolean().default(true),
    canSubscribe: z.boolean().default(true)
  });

  const voiceTargetSchema = z.object({
    targetId: z.string().max(80).refine(
      (value) => value.startsWith("usr_") || value.startsWith("grp_")
    )
  });
  const voiceInvitationParamsSchema = z.object({
    invitationId: z.string().startsWith("vin_").max(80)
  });
  const voiceInvitationResponseSchema = z.object({
    action: z.enum(["accept", "decline"])
  });

  app.get("/v1/voice/invitations", async (request) => {
    const currentUser = authenticatedUser(request);
    return {
      invitations: store.pendingVoiceInvitations(currentUser.id).map(
        (invitation) => publicVoiceInvitation(store, invitation)
      )
    };
  });

  app.post("/v1/voice/invitations", {
    config: { rateLimit: { max: 10, timeWindow: "1 minute" } }
  }, async (request, reply) => {
    const currentUser = authenticatedUser(request);
    const body = voiceTargetSchema.parse(request.body);
    const invitation = await store.createVoiceInvitation(
      currentUser.id,
      body.targetId
    );
    const notificationTitle = invitation.targetKind === "group"
      ? "小队语音邀请"
      : "好友语音邀请";
    const notificationBody = invitation.targetKind === "group"
      ? `${currentUser.displayName} 邀请你加入「${invitation.targetName}」语音`
      : `${currentUser.displayName} 正在呼叫你`;

    await Promise.all(invitation.recipientIds.map((recipientId) =>
      notifyUser(recipientId, {
        title: notificationTitle,
        body: notificationBody,
        event: "voice_invitation",
        entityId: invitation.id,
        data: {
          invitationId: invitation.id,
          callerId: currentUser.id,
          callerName: currentUser.displayName,
          targetId: invitation.targetId,
          targetKind: invitation.targetKind,
          targetName: invitation.targetName,
          expiresAt: invitation.expiresAt
        }
      })
    ));

    return reply.status(201).send({
      invitation: publicVoiceInvitation(store, invitation)
    });
  });

  app.post("/v1/voice/invitations/:invitationId/respond", async (request) => {
    const currentUser = authenticatedUser(request);
    const params = voiceInvitationParamsSchema.parse(request.params);
    const body = voiceInvitationResponseSchema.parse(request.body);
    const invitation = await store.respondToVoiceInvitation(
      params.invitationId,
      currentUser.id
    );
    return {
      invitation: publicVoiceInvitation(store, invitation),
      action: body.action
    };
  });

  app.delete("/v1/voice/invitations/:invitationId", async (request, reply) => {
    const currentUser = authenticatedUser(request);
    const params = voiceInvitationParamsSchema.parse(request.params);
    const invitation = await store.cancelVoiceInvitation(
      params.invitationId,
      currentUser.id
    );
    await Promise.all(invitation.recipientIds.map((recipientId) =>
      notifyUser(recipientId, {
        title: "语音邀请已取消",
        body: `${currentUser.displayName} 已结束本次呼叫`,
        event: "voice_cancelled",
        entityId: invitation.id,
        data: { invitationId: invitation.id }
      })
    ));
    return reply.status(204).send();
  });

  app.post("/v1/voice/rooms/:groupId/token", {
    config: { rateLimit: { max: 30, timeWindow: "1 minute" } }
  }, async (request, reply) => {
    const currentUser = authenticatedUser(request);
    const params = z.object({
      groupId: z.string().max(80).refine(
        (value) => value.startsWith("usr_") || value.startsWith("grp_")
      )
    }).parse(request.params);
    const body = tokenRequestSchema.parse(request.body);
    let roomName: string;

    if (params.groupId.startsWith("grp_")) {
      const group = store.groupById(params.groupId);
      if (!group) {
        throw new StoreError("group_not_found", 404, "Group not found");
      }
      if (!group.memberIds.includes(currentUser.id)) {
        throw new StoreError("group_membership_required", 403, "Group membership required");
      }
      roomName = `group-${createHash("sha256")
        .update(group.id)
        .digest("hex")
        .slice(0, 32)}`;
    } else {
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
      roomName = `friends-${createHash("sha256").update(pair).digest("hex").slice(0, 32)}`;
    }

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

  const isoDate = z.string().datetime({ offset: true });
  const ridePointSchema = z.object({
    latitude: z.number().min(-90).max(90),
    longitude: z.number().min(-180).max(180),
    elevationMeters: z.number().finite().optional(),
    speedMetersPerSecond: z.number().min(0).max(100).optional(),
    courseDegrees: z.number().min(-1).max(360).optional(),
    horizontalAccuracyMeters: z.number().min(0).max(10_000).optional(),
    heartRateBeatsPerMinute: z.number().int().min(20).max(260).optional(),
    cadenceRPM: z.number().int().min(0).max(300).optional(),
    cyclingPowerWatts: z.number().min(0).max(5_000).optional(),
    timestamp: isoDate
  });
  const rideMetricsSchema = z.object({
    distanceMeters: z.number().min(0),
    movingDurationSeconds: z.number().min(0),
    elapsedDurationSeconds: z.number().min(0),
    averageSpeedMetersPerSecond: z.number().min(0).max(100),
    maxSpeedMetersPerSecond: z.number().min(0).max(100),
    elevationGainMeters: z.number().min(0),
    averageHeartRate: z.number().int().min(20).max(260).optional(),
    maxHeartRate: z.number().int().min(20).max(260).optional(),
    activeEnergyKilocalories: z.number().min(0).optional(),
    totalEnergyKilocalories: z.number().min(0).optional(),
    averageCadenceRPM: z.number().min(0).max(300).optional(),
    maxCadenceRPM: z.number().min(0).max(300).optional(),
    averageCyclingPowerWatts: z.number().min(0).max(5_000).optional(),
    maxCyclingPowerWatts: z.number().min(0).max(5_000).optional()
  });
  const rideWeatherSchema = z.object({
    temperatureCelsius: z.number().min(-100).max(70),
    apparentTemperatureCelsius: z.number().min(-120).max(80).optional(),
    relativeHumidityPercent: z.number().min(0).max(100).optional(),
    windSpeedKilometersPerHour: z.number().min(0).max(500).optional(),
    windDirectionDegrees: z.number().min(0).max(360).optional(),
    conditionText: z.string().trim().min(1).max(80),
    symbolName: z.string().trim().min(1).max(100),
    capturedAt: isoDate,
    latitude: z.number().min(-90).max(90),
    longitude: z.number().min(-180).max(180)
  });
  const rideSchema = z.object({
    id: z.string().uuid(),
    title: z.string().trim().min(1).max(80),
    state: z.literal("finished"),
    source: z.enum(["iPhone", "appleWatch", "merged"]),
    startedAt: isoDate,
    endedAt: isoDate.optional(),
    points: z.array(ridePointSchema).max(100_000),
    metrics: rideMetricsSchema,
    weather: rideWeatherSchema.optional()
  });
  const rideParamsSchema = z.object({ rideId: z.string().uuid() });

  app.get("/v1/rides", async (request) => {
    const currentUser = authenticatedUser(request);
    return { rides: store.ridesFor(currentUser.id).map(publicRide) };
  });

  app.get("/v1/rides/:rideId", async (request) => {
    const currentUser = authenticatedUser(request);
    const params = rideParamsSchema.parse(request.params);
    const ride = store.rideFor(currentUser.id, params.rideId);
    if (!ride) {
      throw new StoreError("ride_not_found", 404, "Ride not found");
    }
    return { ride: publicRide(ride) };
  });

  app.put("/v1/rides/:rideId", async (request) => {
    const currentUser = authenticatedUser(request);
    const params = rideParamsSchema.parse(request.params);
    const body = rideSchema.parse(request.body);
    if (body.id !== params.rideId) {
      throw new StoreError("ride_id_mismatch", 400, "Ride ID does not match URL");
    }
    const ride = await store.upsertRide(currentUser.id, body);
    return { ride: publicRide(ride) };
  });

  app.delete("/v1/rides/:rideId", async (request, reply) => {
    const currentUser = authenticatedUser(request);
    const params = rideParamsSchema.parse(request.params);
    await store.deleteRide(currentUser.id, params.rideId);
    return reply.status(204).send();
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
