import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { createApp } from "../src/app.js";
import {
  AppleTokenClientError,
  type AppleTokenClient
} from "../src/apple-token-client.js";
import type {
  NotificationSender,
  PushNotification
} from "../src/apns.js";

const configFor = (
  dataFile: string,
  notificationSenders?: NotificationSender[]
) => ({
  livekitUrl: "wss://example.livekit.cloud",
  livekitApiKey: "API_TEST_KEY",
  livekitApiSecret: "test-secret",
  allowedOrigins: "",
  dataFile,
  appleBundleId: "com.sssnto.BikeGoGo",
  sessionTTLDays: 30,
  notificationSenders,
  appleIdentityVerifier: async (identityToken: string) => ({
    subject: identityToken.startsWith("b")
      ? "second-apple-user-subject"
      : "apple-user-subject",
    email: "rider@example.com"
  })
});

test("health responses expose a request ID and build revision", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-test-"));
  const dataFile = path.join(directory, "data.json");
  const app = await createApp({
    ...configFor(dataFile),
    revision: "test-revision"
  });

  try {
    const response = await app.inject({ method: "GET", url: "/health" });
    assert.equal(response.statusCode, 200);
    assert.match(response.headers["x-request-id"] ?? "", /^req-/);
    assert.equal(response.json().revision, "test-revision");
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("authenticated clients can submit a bounded telemetry batch", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-test-"));
  const dataFile = path.join(directory, "data.json");
  const app = await createApp(configFor(dataFile));

  try {
    const session = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "telemetry-device-id", displayName: "Telemetry Rider" }
    })).json();
    const unauthorized = await app.inject({
      method: "POST",
      url: "/v1/telemetry/events",
      payload: { events: [] }
    });
    assert.equal(unauthorized.statusCode, 401);

    const accepted = await app.inject({
      method: "POST",
      url: "/v1/telemetry/events",
      headers: { authorization: `Bearer ${session.accessToken}` },
      payload: {
        events: [{
          eventId: "7b9a8b28-f924-4704-a6e2-3729ebdd95d1",
          eventName: "ride.sync_succeeded",
          occurredAt: "2026-08-25T12:00:00.000Z",
          platform: "iOS",
          appVersion: "1.0",
          buildNumber: "33",
          properties: { source: "appleWatch", retryCount: 0 }
        }]
      }
    });
    assert.equal(accepted.statusCode, 202);
    assert.equal(accepted.json().accepted, 1);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("rate limits distinguish clients behind one trusted proxy", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-test-"));
  const dataFile = path.join(directory, "data.json");
  const app = await createApp({
    ...configFor(dataFile),
    trustProxy: 1
  });

  try {
    for (let index = 0; index < 10; index += 1) {
      const response = await app.inject({
        method: "POST",
        url: "/v1/auth/guest",
        headers: { "x-forwarded-for": "198.51.100.10" },
        payload: {
          deviceId: `trusted-proxy-client-a-${index}`,
          displayName: "Proxy Rider A"
        }
      });
      assert.equal(response.statusCode, 200);
    }

    const limitedResponse = await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      headers: { "x-forwarded-for": "198.51.100.10" },
      payload: {
        deviceId: "trusted-proxy-client-a-limited",
        displayName: "Proxy Rider A"
      }
    });
    assert.equal(limitedResponse.statusCode, 429);
    assert.equal(limitedResponse.json().error, "rate_limit_exceeded");
    assert.equal(
      limitedResponse.json().requestId,
      limitedResponse.headers["x-request-id"]
    );

    const otherClientResponse = await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      headers: { "x-forwarded-for": "203.0.113.20" },
      payload: {
        deviceId: "trusted-proxy-client-b-first",
        displayName: "Proxy Rider B"
      }
    });
    assert.equal(otherClientResponse.statusCode, 200);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("push tokens receive friend and group notifications for their account", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-test-"));
  const dataFile = path.join(directory, "data.json");
  const deliveries: Array<{
    environment: "sandbox" | "production";
    tokens: string[];
    notification: PushNotification;
  }> = [];
  const sender = (
    environment: "sandbox" | "production"
  ): NotificationSender => ({
    environment,
    async send(tokens, notification) {
      deliveries.push({ environment, tokens, notification });
      return { invalidTokens: [], failedCount: 0 };
    }
  });
  const app = await createApp(configFor(dataFile, [
    sender("sandbox"),
    sender("production")
  ]));

  try {
    const owner = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "push-owner-device-id", displayName: "Push Owner" }
    })).json();
    const member = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "push-member-device-id", displayName: "Push Member" }
    })).json();
    const ownerToken = "a".repeat(64);
    const memberToken = "b".repeat(64);

    for (const registration of [
      { session: owner, token: ownerToken, environment: "sandbox" },
      { session: member, token: memberToken, environment: "sandbox" },
      { session: member, token: "c".repeat(64), environment: "production" }
    ]) {
      const response = await app.inject({
        method: "PUT",
        url: "/v1/devices/push-token",
        headers: { authorization: `Bearer ${registration.session.accessToken}` },
        payload: {
          token: registration.token,
          environment: registration.environment
        }
      });
      assert.equal(response.statusCode, 204);
    }

    const friendRequest = await app.inject({
      method: "POST",
      url: "/v1/friends/requests",
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: { friendCode: member.user.friendCode }
    });
    assert.equal(friendRequest.statusCode, 201);
    assert.deepEqual(deliveries[0].tokens, [memberToken]);
    assert.equal(deliveries[0].notification.event, "friend_request");
    assert.equal(deliveries[0].environment, "sandbox");
    assert.deepEqual(deliveries[1].tokens, ["c".repeat(64)]);
    assert.equal(deliveries[1].environment, "production");

    const accepted = await app.inject({
      method: "POST",
      url: `/v1/friends/requests/${friendRequest.json().request.id}/accept`,
      headers: { authorization: `Bearer ${member.accessToken}` }
    });
    assert.equal(accepted.statusCode, 200);
    assert.deepEqual(deliveries[2].tokens, [ownerToken]);
    assert.equal(deliveries[2].notification.event, "friend_accepted");

    const group = await app.inject({
      method: "POST",
      url: "/v1/groups",
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: { name: "Push Riders" }
    });
    const added = await app.inject({
      method: "POST",
      url: `/v1/groups/${group.json().group.id}/members`,
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: { userId: member.user.id }
    });
    assert.equal(added.statusCode, 200);
    assert.deepEqual(deliveries[3].tokens, [memberToken]);
    assert.equal(deliveries[3].notification.event, "group_invitation");
    assert.deepEqual(deliveries[4].tokens, ["c".repeat(64)]);
    assert.equal(deliveries[4].environment, "production");

    const unregistered = await app.inject({
      method: "DELETE",
      url: "/v1/devices/push-token",
      headers: { authorization: `Bearer ${member.accessToken}` },
      payload: { token: memberToken, environment: "sandbox" }
    });
    assert.equal(unregistered.statusCode, 204);

    const secondGroup = await app.inject({
      method: "POST",
      url: "/v1/groups",
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: { name: "Silent Riders" }
    });
    await app.inject({
      method: "POST",
      url: `/v1/groups/${secondGroup.json().group.id}/members`,
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: { userId: member.user.id }
    });
    assert.equal(deliveries.length, 6);
    assert.equal(deliveries[5].environment, "production");
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("guest users can request and accept friendship", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-test-"));
  const dataFile = path.join(directory, "data.json");
  const app = await createApp(configFor(dataFile));

  try {
    const firstLogin = await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: {
        deviceId: "device-identifier-alpha",
        displayName: "Alpha Rider"
      }
    });
    const secondLogin = await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: {
        deviceId: "device-identifier-bravo",
        displayName: "Bravo Rider"
      }
    });

    assert.equal(firstLogin.statusCode, 200);
    assert.equal(secondLogin.statusCode, 200);

    const firstSession = firstLogin.json();
    const secondSession = secondLogin.json();
    assert.notEqual(firstSession.user.friendCode, secondSession.user.friendCode);

    const requestResponse = await app.inject({
      method: "POST",
      url: "/v1/friends/requests",
      headers: { authorization: `Bearer ${firstSession.accessToken}` },
      payload: { friendCode: secondSession.user.friendCode }
    });
    assert.equal(requestResponse.statusCode, 201);

    const incomingResponse = await app.inject({
      method: "GET",
      url: "/v1/friends/requests",
      headers: { authorization: `Bearer ${secondSession.accessToken}` }
    });
    assert.equal(incomingResponse.statusCode, 200);
    assert.equal(incomingResponse.json().incoming[0].user.id, firstSession.user.id);

    const requestId = requestResponse.json().request.id;
    const acceptResponse = await app.inject({
      method: "POST",
      url: `/v1/friends/requests/${requestId}/accept`,
      headers: { authorization: `Bearer ${secondSession.accessToken}` }
    });
    assert.equal(acceptResponse.statusCode, 200);

    const friendsResponse = await app.inject({
      method: "GET",
      url: "/v1/friends",
      headers: { authorization: `Bearer ${firstSession.accessToken}` }
    });
    assert.equal(friendsResponse.statusCode, 200);
    assert.equal(friendsResponse.json().friends[0].id, secondSession.user.id);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("profile and friendships survive store reload", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-test-"));
  const dataFile = path.join(directory, "data.json");
  const deviceId = "persistent-device-identifier";
  let app = await createApp(configFor(dataFile));

  try {
    const login = await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId, displayName: "Original Name" }
    });
    const session = login.json();

    const update = await app.inject({
      method: "PATCH",
      url: "/v1/me",
      headers: { authorization: `Bearer ${session.accessToken}` },
      payload: { displayName: "Updated Rider" }
    });
    assert.equal(update.statusCode, 200);
    assert.equal(update.json().user.displayName, "Updated Rider");

    await app.close();
    app = await createApp(configFor(dataFile));

    const secondLogin = await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId, displayName: "Ignored Name" }
    });
    assert.equal(secondLogin.statusCode, 200);
    assert.equal(secondLogin.json().user.displayName, "Updated Rider");
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("Apple sign in binds the guest account and supports logout", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-test-"));
  const dataFile = path.join(directory, "data.json");
  const app = await createApp(configFor(dataFile));

  try {
    const guestLogin = await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: {
        deviceId: "apple-link-device-identifier",
        displayName: "Apple Rider"
      }
    });
    const guestSession = guestLogin.json();

    const appleLogin = await app.inject({
      method: "POST",
      url: "/v1/auth/apple",
      headers: { authorization: `Bearer ${guestSession.accessToken}` },
      payload: {
        identityToken: "a".repeat(120),
        rawNonce: "test-raw-nonce-value",
        deviceId: "apple-link-device-identifier",
        displayName: "Apple Rider"
      }
    });
    assert.equal(appleLogin.statusCode, 200);
    const appleSession = appleLogin.json();
    assert.equal(appleSession.user.id, guestSession.user.id);
    assert.equal(appleSession.user.friendCode, guestSession.user.friendCode);
    assert.equal(appleSession.user.authProvider, "apple");

    const mismatchedAppleLogin = await app.inject({
      method: "POST",
      url: "/v1/auth/apple",
      headers: { authorization: `Bearer ${appleSession.accessToken}` },
      payload: {
        identityToken: "b".repeat(120),
        rawNonce: "test-raw-nonce-value",
        deviceId: "apple-link-device-identifier"
      }
    });
    assert.equal(mismatchedAppleLogin.statusCode, 409);
    assert.equal(mismatchedAppleLogin.json().error, "apple_account_mismatch");

    const guestRelogin = await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: {
        deviceId: "apple-link-device-identifier",
        displayName: "Apple Rider"
      }
    });
    assert.equal(guestRelogin.statusCode, 409);
    assert.equal(guestRelogin.json().error, "apple_sign_in_required");

    const logout = await app.inject({
      method: "DELETE",
      url: "/v1/session",
      headers: { authorization: `Bearer ${appleSession.accessToken}` }
    });
    assert.equal(logout.statusCode, 204);

    const me = await app.inject({
      method: "GET",
      url: "/v1/me",
      headers: { authorization: `Bearer ${appleSession.accessToken}` }
    });
    assert.equal(me.statusCode, 401);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("Apple account deletion requires reauthentication and revokes Apple tokens", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-test-"));
  const dataFile = path.join(directory, "data.json");
  const revoked: Array<{ token: string; tokenType: string }> = [];
  const appleTokenClient: AppleTokenClient = {
    async exchangeAuthorizationCode(code) {
      return {
        accessToken: `access-${code}`,
        refreshToken: `refresh-${code}`,
        identityToken: code === "mismatched-code"
          ? "b".repeat(120)
          : "a".repeat(120)
      };
    },
    async revoke(token, tokenType) {
      revoked.push({ token, tokenType });
    }
  };
  const app = await createApp({
    ...configFor(dataFile),
    appleTokenClient
  });

  try {
    const guest = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: {
        deviceId: "apple-delete-device-identifier",
        displayName: "Apple Delete Rider"
      }
    })).json();
    const apple = (await app.inject({
      method: "POST",
      url: "/v1/auth/apple",
      headers: { authorization: `Bearer ${guest.accessToken}` },
      payload: {
        identityToken: "a".repeat(120),
        rawNonce: "apple-delete-login-nonce",
        deviceId: "apple-delete-device-identifier"
      }
    })).json();

    const missingReauthentication = await app.inject({
      method: "DELETE",
      url: "/v1/me",
      headers: { authorization: `Bearer ${apple.accessToken}` },
      payload: { confirmation: "DELETE" }
    });
    assert.equal(missingReauthentication.statusCode, 400);
    assert.equal(
      missingReauthentication.json().error,
      "apple_reauthentication_required"
    );

    const mismatchedAccount = await app.inject({
      method: "DELETE",
      url: "/v1/me",
      headers: { authorization: `Bearer ${apple.accessToken}` },
      payload: {
        confirmation: "DELETE",
        appleAuthorizationCode: "mismatched-code",
        appleRawNonce: "apple-delete-request-nonce"
      }
    });
    assert.equal(mismatchedAccount.statusCode, 409);
    assert.equal(mismatchedAccount.json().error, "apple_account_mismatch");
    assert.deepEqual(revoked, []);

    const deleted = await app.inject({
      method: "DELETE",
      url: "/v1/me",
      headers: { authorization: `Bearer ${apple.accessToken}` },
      payload: {
        confirmation: "DELETE",
        appleAuthorizationCode: "matching-code",
        appleRawNonce: "apple-delete-request-nonce"
      }
    });
    assert.equal(deleted.statusCode, 204);
    assert.deepEqual(revoked, [{
      token: "refresh-matching-code",
      tokenType: "refresh_token"
    }]);

    const deletedSession = await app.inject({
      method: "GET",
      url: "/v1/me",
      headers: { authorization: `Bearer ${apple.accessToken}` }
    });
    assert.equal(deletedSession.statusCode, 401);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("Apple token revocation failure leaves the account intact", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-test-"));
  const dataFile = path.join(directory, "data.json");
  const appleTokenClient: AppleTokenClient = {
    async exchangeAuthorizationCode() {
      return {
        accessToken: "access-token",
        refreshToken: "refresh-token",
        identityToken: "a".repeat(120)
      };
    },
    async revoke() {
      throw new AppleTokenClientError(
        "service_unavailable",
        "Apple token service is unavailable"
      );
    }
  };
  const app = await createApp({
    ...configFor(dataFile),
    appleTokenClient
  });

  try {
    const guest = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: {
        deviceId: "apple-revoke-failure-device",
        displayName: "Apple Revoke Rider"
      }
    })).json();
    const apple = (await app.inject({
      method: "POST",
      url: "/v1/auth/apple",
      headers: { authorization: `Bearer ${guest.accessToken}` },
      payload: {
        identityToken: "a".repeat(120),
        rawNonce: "apple-revoke-login-nonce",
        deviceId: "apple-revoke-failure-device"
      }
    })).json();

    const deletion = await app.inject({
      method: "DELETE",
      url: "/v1/me",
      headers: { authorization: `Bearer ${apple.accessToken}` },
      payload: {
        confirmation: "DELETE",
        appleAuthorizationCode: "matching-code",
        appleRawNonce: "apple-revoke-request-nonce"
      }
    });
    assert.equal(deletion.statusCode, 503);
    assert.equal(
      deletion.json().error,
      "apple_token_service_unavailable"
    );

    const me = await app.inject({
      method: "GET",
      url: "/v1/me",
      headers: { authorization: `Bearer ${apple.accessToken}` }
    });
    assert.equal(me.statusCode, 200);
    assert.equal(me.json().user.id, apple.user.id);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("version 1 device records migrate without losing the guest account", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-test-"));
  const dataFile = path.join(directory, "data.json");
  const deviceId = "legacy-device-identifier";
  const now = new Date().toISOString();
  await writeFile(dataFile, JSON.stringify({
    version: 1,
    users: [{
      id: "usr_legacy",
      deviceIdHash: createHash("sha256").update(deviceId).digest("hex"),
      displayName: "Legacy Rider",
      friendCode: "LEGACY88",
      createdAt: now,
      updatedAt: now
    }],
    sessions: [],
    friendRequests: [],
    friendships: []
  }));
  const app = await createApp(configFor(dataFile));

  try {
    const login = await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId, displayName: "Ignored Name" }
    });
    assert.equal(login.statusCode, 200);
    assert.equal(login.json().user.id, "usr_legacy");
    assert.equal(login.json().user.displayName, "Legacy Rider");
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("voice token endpoint requires an authenticated account", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-test-"));
  const dataFile = path.join(directory, "data.json");
  const app = await createApp(configFor(dataFile));

  try {
    const anonymous = await app.inject({
      method: "POST",
      url: "/v1/voice/rooms/weekend/token",
      payload: {}
    });
    assert.equal(anonymous.statusCode, 401);

    const login = await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: {
        deviceId: "voice-auth-device-identifier",
        displayName: "Voice Rider"
      }
    });
    const session = login.json();
    const peerLogin = await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: {
        deviceId: "voice-peer-device-identifier",
        displayName: "Voice Peer"
      }
    });
    const peerSession = peerLogin.json();

    const beforeFriendship = await app.inject({
      method: "POST",
      url: `/v1/voice/rooms/${peerSession.user.id}/token`,
      headers: { authorization: `Bearer ${session.accessToken}` },
      payload: {}
    });
    assert.equal(beforeFriendship.statusCode, 403);

    const request = await app.inject({
      method: "POST",
      url: "/v1/friends/requests",
      headers: { authorization: `Bearer ${session.accessToken}` },
      payload: { friendCode: peerSession.user.friendCode }
    });
    await app.inject({
      method: "POST",
      url: `/v1/friends/requests/${request.json().request.id}/accept`,
      headers: { authorization: `Bearer ${peerSession.accessToken}` }
    });

    const authenticated = await app.inject({
      method: "POST",
      url: `/v1/voice/rooms/${peerSession.user.id}/token`,
      headers: { authorization: `Bearer ${session.accessToken}` },
      payload: {}
    });
    assert.equal(authenticated.statusCode, 200);
    assert.match(authenticated.json().roomName, /^friends-[a-f0-9]{32}$/);

    const peerAuthenticated = await app.inject({
      method: "POST",
      url: `/v1/voice/rooms/${session.user.id}/token`,
      headers: { authorization: `Bearer ${peerSession.accessToken}` },
      payload: {}
    });
    assert.equal(peerAuthenticated.json().roomName, authenticated.json().roomName);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("voice invitations notify friends and support pending, accept, and cancel", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-test-"));
  const dataFile = path.join(directory, "data.json");
  const deliveries: Array<{
    tokens: string[];
    notification: PushNotification;
  }> = [];
  const sender: NotificationSender = {
    environment: "sandbox",
    async send(tokens, notification) {
      deliveries.push({ tokens, notification });
      return { invalidTokens: [], failedCount: 0 };
    }
  };
  const app = await createApp(configFor(dataFile, [sender]));

  try {
    const caller = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "voice-invite-caller-device", displayName: "Caller" }
    })).json();
    const recipient = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "voice-invite-recipient-device", displayName: "Recipient" }
    })).json();
    const outsider = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "voice-invite-outsider-device", displayName: "Outsider" }
    })).json();

    await app.inject({
      method: "PUT",
      url: "/v1/devices/push-token",
      headers: { authorization: `Bearer ${recipient.accessToken}` },
      payload: { token: "d".repeat(64), environment: "sandbox" }
    });
    const friendRequest = await app.inject({
      method: "POST",
      url: "/v1/friends/requests",
      headers: { authorization: `Bearer ${caller.accessToken}` },
      payload: { friendCode: recipient.user.friendCode }
    });
    await app.inject({
      method: "POST",
      url: `/v1/friends/requests/${friendRequest.json().request.id}/accept`,
      headers: { authorization: `Bearer ${recipient.accessToken}` }
    });
    deliveries.length = 0;

    const created = await app.inject({
      method: "POST",
      url: "/v1/voice/invitations",
      headers: { authorization: `Bearer ${caller.accessToken}` },
      payload: { targetId: recipient.user.id }
    });
    assert.equal(created.statusCode, 201);
    const invitation = created.json().invitation;
    assert.match(invitation.id, /^vin_/);
    assert.equal(invitation.targetKind, "friend");
    assert.equal(deliveries.length, 1);
    assert.deepEqual(deliveries[0].tokens, ["d".repeat(64)]);
    assert.equal(deliveries[0].notification.event, "voice_invitation");
    assert.equal(deliveries[0].notification.data?.targetId, recipient.user.id);

    const pending = await app.inject({
      method: "GET",
      url: "/v1/voice/invitations",
      headers: { authorization: `Bearer ${recipient.accessToken}` }
    });
    assert.equal(pending.statusCode, 200);
    assert.equal(pending.json().invitations[0].id, invitation.id);

    const forbidden = await app.inject({
      method: "POST",
      url: `/v1/voice/invitations/${invitation.id}/respond`,
      headers: { authorization: `Bearer ${outsider.accessToken}` },
      payload: { action: "accept" }
    });
    assert.equal(forbidden.statusCode, 403);

    const accepted = await app.inject({
      method: "POST",
      url: `/v1/voice/invitations/${invitation.id}/respond`,
      headers: { authorization: `Bearer ${recipient.accessToken}` },
      payload: { action: "accept" }
    });
    assert.equal(accepted.statusCode, 200);
    assert.equal(accepted.json().action, "accept");

    const noLongerPending = await app.inject({
      method: "GET",
      url: "/v1/voice/invitations",
      headers: { authorization: `Bearer ${recipient.accessToken}` }
    });
    assert.deepEqual(noLongerPending.json().invitations, []);

    const second = await app.inject({
      method: "POST",
      url: "/v1/voice/invitations",
      headers: { authorization: `Bearer ${caller.accessToken}` },
      payload: { targetId: recipient.user.id }
    });
    const cancelled = await app.inject({
      method: "DELETE",
      url: `/v1/voice/invitations/${second.json().invitation.id}`,
      headers: { authorization: `Bearer ${caller.accessToken}` }
    });
    assert.equal(cancelled.statusCode, 204);
    assert.equal(deliveries.at(-1)?.notification.event, "voice_cancelled");

    const groupResponse = await app.inject({
      method: "POST",
      url: "/v1/groups",
      headers: { authorization: `Bearer ${caller.accessToken}` },
      payload: { name: "Voice Riders" }
    });
    const groupId = groupResponse.json().group.id;
    await app.inject({
      method: "POST",
      url: `/v1/groups/${groupId}/members`,
      headers: { authorization: `Bearer ${caller.accessToken}` },
      payload: { userId: recipient.user.id }
    });
    deliveries.length = 0;

    const groupInvitationResponse = await app.inject({
      method: "POST",
      url: "/v1/voice/invitations",
      headers: { authorization: `Bearer ${caller.accessToken}` },
      payload: { targetId: groupId }
    });
    assert.equal(groupInvitationResponse.statusCode, 201);
    assert.equal(groupInvitationResponse.json().invitation.targetKind, "group");
    assert.equal(groupInvitationResponse.json().invitation.targetName, "Voice Riders");
    assert.equal(deliveries.length, 1);
    assert.equal(deliveries[0].notification.event, "voice_invitation");
    assert.equal(deliveries[0].notification.data?.targetKind, "group");
    assert.equal(deliveries[0].notification.data?.targetId, groupId);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("group membership controls management and group voice access", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-test-"));
  const dataFile = path.join(directory, "data.json");
  const app = await createApp(configFor(dataFile));

  try {
    const owner = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "group-owner-device-id", displayName: "Group Owner" }
    })).json();
    const member = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "group-member-device-id", displayName: "Group Member" }
    })).json();
    const outsider = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "group-outsider-device", displayName: "Group Outsider" }
    })).json();

    const createGroup = await app.inject({
      method: "POST",
      url: "/v1/groups",
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: { name: "Weekend Riders" }
    });
    assert.equal(createGroup.statusCode, 201);
    const groupId = createGroup.json().group.id;

    const addBeforeFriendship = await app.inject({
      method: "POST",
      url: `/v1/groups/${groupId}/members`,
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: { userId: member.user.id }
    });
    assert.equal(addBeforeFriendship.statusCode, 403);

    const friendRequest = await app.inject({
      method: "POST",
      url: "/v1/friends/requests",
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: { friendCode: member.user.friendCode }
    });
    await app.inject({
      method: "POST",
      url: `/v1/friends/requests/${friendRequest.json().request.id}/accept`,
      headers: { authorization: `Bearer ${member.accessToken}` }
    });

    const addMember = await app.inject({
      method: "POST",
      url: `/v1/groups/${groupId}/members`,
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: { userId: member.user.id }
    });
    assert.equal(addMember.statusCode, 200);
    assert.equal(addMember.json().group.members.length, 2);

    const memberGroups = await app.inject({
      method: "GET",
      url: "/v1/groups",
      headers: { authorization: `Bearer ${member.accessToken}` }
    });
    assert.equal(memberGroups.json().groups[0].id, groupId);
    assert.equal(memberGroups.json().groups[0].isOwner, false);

    const ownerVoice = await app.inject({
      method: "POST",
      url: `/v1/voice/rooms/${groupId}/token`,
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: {}
    });
    const memberVoice = await app.inject({
      method: "POST",
      url: `/v1/voice/rooms/${groupId}/token`,
      headers: { authorization: `Bearer ${member.accessToken}` },
      payload: {}
    });
    assert.equal(ownerVoice.statusCode, 200);
    assert.equal(memberVoice.statusCode, 200);
    assert.equal(ownerVoice.json().roomName, memberVoice.json().roomName);
    assert.match(ownerVoice.json().roomName, /^group-[a-f0-9]{32}$/);

    const outsiderVoice = await app.inject({
      method: "POST",
      url: `/v1/voice/rooms/${groupId}/token`,
      headers: { authorization: `Bearer ${outsider.accessToken}` },
      payload: {}
    });
    assert.equal(outsiderVoice.statusCode, 403);

    const memberAddsOutsider = await app.inject({
      method: "POST",
      url: `/v1/groups/${groupId}/members`,
      headers: { authorization: `Bearer ${member.accessToken}` },
      payload: { userId: outsider.user.id }
    });
    assert.equal(memberAddsOutsider.statusCode, 403);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("group members can share temporary ride locations", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-test-"));
  const dataFile = path.join(directory, "data.json");
  const app = await createApp(configFor(dataFile));

  try {
    const owner = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "location-owner-device", displayName: "Location Owner" }
    })).json();
    const member = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "location-member-device", displayName: "Location Member" }
    })).json();
    const outsider = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "location-outsider-device", displayName: "Outsider" }
    })).json();

    const friendRequest = await app.inject({
      method: "POST",
      url: "/v1/friends/requests",
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: { friendCode: member.user.friendCode }
    });
    await app.inject({
      method: "POST",
      url: `/v1/friends/requests/${friendRequest.json().request.id}/accept`,
      headers: { authorization: `Bearer ${member.accessToken}` }
    });
    const group = (await app.inject({
      method: "POST",
      url: "/v1/groups",
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: { name: "Location Riders" }
    })).json().group;
    await app.inject({
      method: "POST",
      url: `/v1/groups/${group.id}/members`,
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: { userId: member.user.id }
    });

    const forbidden = await app.inject({
      method: "GET",
      url: `/v1/groups/${group.id}/live-locations`,
      headers: { authorization: `Bearer ${outsider.accessToken}` }
    });
    assert.equal(forbidden.statusCode, 403);

    const shared = await app.inject({
      method: "PUT",
      url: `/v1/groups/${group.id}/live-location`,
      headers: { authorization: `Bearer ${member.accessToken}` },
      payload: {
        latitude: 39.9042,
        longitude: 116.4074,
        horizontalAccuracyMeters: 8,
        speedMetersPerSecond: 5.5,
        courseDegrees: 120,
        capturedAt: "2026-07-28T00:00:00.000Z"
      }
    });
    assert.equal(shared.statusCode, 200);
    assert.equal(shared.json().location.user.id, member.user.id);

    const visible = await app.inject({
      method: "GET",
      url: `/v1/groups/${group.id}/live-locations`,
      headers: { authorization: `Bearer ${owner.accessToken}` }
    });
    assert.equal(visible.statusCode, 200);
    assert.equal(visible.json().locations.length, 1);
    assert.equal(visible.json().locations[0].latitude, 39.9042);

    const stopped = await app.inject({
      method: "DELETE",
      url: `/v1/groups/${group.id}/live-location`,
      headers: { authorization: `Bearer ${member.accessToken}` }
    });
    assert.equal(stopped.statusCode, 204);

    const afterStop = await app.inject({
      method: "GET",
      url: `/v1/groups/${group.id}/live-locations`,
      headers: { authorization: `Bearer ${owner.accessToken}` }
    });
    assert.deepEqual(afterStop.json().locations, []);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("group owners can set a temporary meeting point for members", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-test-"));
  const dataFile = path.join(directory, "data.json");
  const deliveries: Array<{
    tokens: string[];
    notification: PushNotification;
  }> = [];
  const sender: NotificationSender = {
    environment: "sandbox",
    async send(tokens, notification) {
      deliveries.push({ tokens, notification });
      return { invalidTokens: [], failedCount: 0 };
    }
  };
  const app = await createApp(configFor(dataFile, [sender]));

  try {
    const owner = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "meeting-owner-device", displayName: "Meeting Owner" }
    })).json();
    const member = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "meeting-member-device", displayName: "Meeting Member" }
    })).json();
    const outsider = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "meeting-outsider-device", displayName: "Meeting Outsider" }
    })).json();

    await app.inject({
      method: "PUT",
      url: "/v1/devices/push-token",
      headers: { authorization: `Bearer ${member.accessToken}` },
      payload: { token: "f".repeat(64), environment: "sandbox" }
    });
    const friendRequest = await app.inject({
      method: "POST",
      url: "/v1/friends/requests",
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: { friendCode: member.user.friendCode }
    });
    await app.inject({
      method: "POST",
      url: `/v1/friends/requests/${friendRequest.json().request.id}/accept`,
      headers: { authorization: `Bearer ${member.accessToken}` }
    });
    const group = (await app.inject({
      method: "POST",
      url: "/v1/groups",
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: { name: "Meeting Riders" }
    })).json().group;
    await app.inject({
      method: "POST",
      url: `/v1/groups/${group.id}/members`,
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: { userId: member.user.id }
    });
    deliveries.length = 0;

    const forbiddenRead = await app.inject({
      method: "GET",
      url: `/v1/groups/${group.id}/meeting-point`,
      headers: { authorization: `Bearer ${outsider.accessToken}` }
    });
    assert.equal(forbiddenRead.statusCode, 403);

    const forbiddenSet = await app.inject({
      method: "PUT",
      url: `/v1/groups/${group.id}/meeting-point`,
      headers: { authorization: `Bearer ${member.accessToken}` },
      payload: {
        latitude: 39.9042,
        longitude: 116.4074,
        title: "东门",
        capturedAt: "2026-07-28T03:00:00.000Z"
      }
    });
    assert.equal(forbiddenSet.statusCode, 403);

    const set = await app.inject({
      method: "PUT",
      url: `/v1/groups/${group.id}/meeting-point`,
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: {
        latitude: 39.9042,
        longitude: 116.4074,
        title: "东门",
        horizontalAccuracyMeters: 6,
        capturedAt: "2026-07-28T03:00:00.000Z"
      }
    });
    assert.equal(set.statusCode, 200);
    assert.equal(set.json().meetingPoint.title, "东门");
    assert.equal(set.json().meetingPoint.setBy.id, owner.user.id);
    assert.equal(deliveries.length, 1);
    assert.equal(
      deliveries[0].notification.event,
      "group_meeting_point_updated"
    );
    assert.deepEqual(deliveries[0].tokens, ["f".repeat(64)]);

    const visible = await app.inject({
      method: "GET",
      url: `/v1/groups/${group.id}/meeting-point`,
      headers: { authorization: `Bearer ${member.accessToken}` }
    });
    assert.equal(visible.statusCode, 200);
    assert.equal(visible.json().meetingPoint.latitude, 39.9042);

    const cleared = await app.inject({
      method: "DELETE",
      url: `/v1/groups/${group.id}/meeting-point`,
      headers: { authorization: `Bearer ${owner.accessToken}` }
    });
    assert.equal(cleared.statusCode, 204);

    const afterClear = await app.inject({
      method: "GET",
      url: `/v1/groups/${group.id}/meeting-point`,
      headers: { authorization: `Bearer ${member.accessToken}` }
    });
    assert.equal(afterClear.json().meetingPoint, null);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("group SOS refreshes the rider location and notifies teammates", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-test-"));
  const dataFile = path.join(directory, "data.json");
  const deliveries: Array<{
    tokens: string[];
    notification: PushNotification;
  }> = [];
  const sender: NotificationSender = {
    environment: "sandbox",
    async send(tokens, notification) {
      deliveries.push({ tokens, notification });
      return { invalidTokens: [], failedCount: 0 };
    }
  };
  const app = await createApp(configFor(dataFile, [sender]));

  try {
    const owner = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "sos-owner-device", displayName: "SOS Owner" }
    })).json();
    const member = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "sos-member-device", displayName: "SOS Member" }
    })).json();
    const outsider = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "sos-outsider-device", displayName: "SOS Outsider" }
    })).json();

    await app.inject({
      method: "PUT",
      url: "/v1/devices/push-token",
      headers: { authorization: `Bearer ${member.accessToken}` },
      payload: { token: "e".repeat(64), environment: "sandbox" }
    });
    const friendRequest = await app.inject({
      method: "POST",
      url: "/v1/friends/requests",
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: { friendCode: member.user.friendCode }
    });
    await app.inject({
      method: "POST",
      url: `/v1/friends/requests/${friendRequest.json().request.id}/accept`,
      headers: { authorization: `Bearer ${member.accessToken}` }
    });
    const group = (await app.inject({
      method: "POST",
      url: "/v1/groups",
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: { name: "Safety Riders" }
    })).json().group;
    await app.inject({
      method: "POST",
      url: `/v1/groups/${group.id}/members`,
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: { userId: member.user.id }
    });
    deliveries.length = 0;

    const forbidden = await app.inject({
      method: "POST",
      url: `/v1/groups/${group.id}/sos`,
      headers: { authorization: `Bearer ${outsider.accessToken}` },
      payload: {
        latitude: 39.9042,
        longitude: 116.4074,
        capturedAt: "2026-07-28T02:00:00.000Z"
      }
    });
    assert.equal(forbidden.statusCode, 403);

    const sent = await app.inject({
      method: "POST",
      url: `/v1/groups/${group.id}/sos`,
      headers: { authorization: `Bearer ${owner.accessToken}` },
      payload: {
        latitude: 39.9042,
        longitude: 116.4074,
        horizontalAccuracyMeters: 7,
        speedMetersPerSecond: 0,
        capturedAt: "2026-07-28T02:00:00.000Z"
      }
    });
    assert.equal(sent.statusCode, 200);
    assert.equal(sent.json().sent, true);
    assert.equal(sent.json().recipientCount, 1);
    assert.equal(sent.json().location.user.id, owner.user.id);
    assert.equal(deliveries.length, 1);
    assert.deepEqual(deliveries[0].tokens, ["e".repeat(64)]);
    assert.equal(deliveries[0].notification.event, "group_sos");
    assert.equal(deliveries[0].notification.data?.groupId, group.id);
    assert.equal(deliveries[0].notification.data?.senderName, "SOS Owner");
    assert.equal(deliveries[0].notification.data?.latitude, "39.9042");

    const locations = await app.inject({
      method: "GET",
      url: `/v1/groups/${group.id}/live-locations`,
      headers: { authorization: `Bearer ${member.accessToken}` }
    });
    assert.equal(locations.json().locations[0].user.id, owner.user.id);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("finished rides sync per account and survive reload", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-test-"));
  const dataFile = path.join(directory, "data.json");
  let app = await createApp(configFor(dataFile));

  try {
    const rider = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "ride-sync-device-id", displayName: "Cloud Rider" }
    })).json();
    const other = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId: "ride-other-device-id", displayName: "Other Rider" }
    })).json();
    const rideId = "61af5aa8-3b97-4538-b2dd-da986b183142";
    const ride = {
      id: rideId.toUpperCase(),
      title: "Morning Ride",
      state: "finished",
      source: "merged",
      startedAt: "2026-07-27T01:00:00.000Z",
      endedAt: "2026-07-27T02:00:00.000Z",
      points: [{
        latitude: 31.2304,
        longitude: 121.4737,
        speedMetersPerSecond: 6.5,
        heartRateBeatsPerMinute: 128,
        cadenceRPM: 82,
        cyclingPowerWatts: 176,
        timestamp: "2026-07-27T01:00:00.000Z"
      }],
      metrics: {
        distanceMeters: 18_000,
        movingDurationSeconds: 3_400,
        elapsedDurationSeconds: 3_600,
        averageSpeedMetersPerSecond: 5.29,
        maxSpeedMetersPerSecond: 12.4,
        elevationGainMeters: 86,
        averageHeartRate: 128,
        maxHeartRate: 151,
        activeEnergyKilocalories: 712,
        totalEnergyKilocalories: 934,
        averageCadenceRPM: 81,
        maxCadenceRPM: 104,
        averageCyclingPowerWatts: 168,
        maxCyclingPowerWatts: 412
      },
      weather: {
        temperatureCelsius: 27.4,
        apparentTemperatureCelsius: 29.1,
        relativeHumidityPercent: 62,
        windSpeedKilometersPerHour: 13.5,
        windDirectionDegrees: 90,
        conditionText: "局部多云",
        symbolName: "cloud.sun.fill",
        capturedAt: "2026-07-27T01:00:00.000Z",
        latitude: 31.2304,
        longitude: 121.4737
      }
    };

    const upload = await app.inject({
      method: "PUT",
      url: `/v1/rides/${rideId}`,
      headers: { authorization: `Bearer ${rider.accessToken}` },
      payload: ride
    });
    assert.equal(upload.statusCode, 200);
    assert.equal(upload.json().ride.metrics.distanceMeters, 18_000);
    assert.equal(upload.json().ride.weather.conditionText, "局部多云");

    const otherRead = await app.inject({
      method: "GET",
      url: `/v1/rides/${rideId}`,
      headers: { authorization: `Bearer ${other.accessToken}` }
    });
    assert.equal(otherRead.statusCode, 404);

    await app.close();
    app = await createApp(configFor(dataFile));

    const list = await app.inject({
      method: "GET",
      url: "/v1/rides",
      headers: { authorization: `Bearer ${rider.accessToken}` }
    });
    assert.equal(list.statusCode, 200);
    assert.equal(list.json().rides[0].id, rideId);
    assert.equal(list.json().rides[0].points.length, 1);
    assert.equal(list.json().rides[0].points[0].cyclingPowerWatts, 176);
    assert.equal(list.json().rides[0].metrics.activeEnergyKilocalories, 712);
    assert.equal(list.json().rides[0].metrics.averageCadenceRPM, 81);
    assert.equal(list.json().rides[0].metrics.maxCyclingPowerWatts, 412);
    assert.equal(list.json().rides[0].weather.temperatureCelsius, 27.4);

    const deletion = await app.inject({
      method: "DELETE",
      url: `/v1/rides/${rideId}`,
      headers: { authorization: `Bearer ${rider.accessToken}` }
    });
    assert.equal(deletion.statusCode, 204);

    const deletedRead = await app.inject({
      method: "GET",
      url: `/v1/rides/${rideId}`,
      headers: { authorization: `Bearer ${rider.accessToken}` }
    });
    assert.equal(deletedRead.statusCode, 404);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("account export is private and account deletion removes owned data", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-test-"));
  const dataFile = path.join(directory, "data.json");
  const app = await createApp(configFor(dataFile));

  try {
    const rider = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: {
        deviceId: "account-delete-rider-device",
        displayName: "Delete Rider"
      }
    })).json();
    const teammate = (await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: {
        deviceId: "account-delete-teammate-device",
        displayName: "Keep Rider"
      }
    })).json();

    const friendRequest = (await app.inject({
      method: "POST",
      url: "/v1/friends/requests",
      headers: { authorization: `Bearer ${rider.accessToken}` },
      payload: { friendCode: teammate.user.friendCode }
    })).json();
    await app.inject({
      method: "POST",
      url: `/v1/friends/requests/${friendRequest.request.id}/accept`,
      headers: { authorization: `Bearer ${teammate.accessToken}` }
    });

    const ownedGroup = (await app.inject({
      method: "POST",
      url: "/v1/groups",
      headers: { authorization: `Bearer ${rider.accessToken}` },
      payload: { name: "Deleted Owner Group" }
    })).json().group;
    const retainedGroup = (await app.inject({
      method: "POST",
      url: "/v1/groups",
      headers: { authorization: `Bearer ${teammate.accessToken}` },
      payload: { name: "Retained Owner Group" }
    })).json().group;
    await app.inject({
      method: "POST",
      url: `/v1/groups/${retainedGroup.id}/members`,
      headers: { authorization: `Bearer ${teammate.accessToken}` },
      payload: { userId: rider.user.id }
    });

    const rideId = "dc8ee174-1f4a-42d3-b5ce-69d705e7ed5f";
    await app.inject({
      method: "PUT",
      url: `/v1/rides/${rideId}`,
      headers: { authorization: `Bearer ${rider.accessToken}` },
      payload: {
        id: rideId,
        title: "Exported Ride",
        state: "finished",
        source: "iPhone",
        startedAt: "2026-07-28T01:00:00.000Z",
        endedAt: "2026-07-28T02:00:00.000Z",
        points: [{
          latitude: 39.9042,
          longitude: 116.4074,
          timestamp: "2026-07-28T01:00:00.000Z"
        }],
        metrics: {
          distanceMeters: 12_000,
          movingDurationSeconds: 3_000,
          elapsedDurationSeconds: 3_600,
          averageSpeedMetersPerSecond: 4,
          maxSpeedMetersPerSecond: 10,
          elevationGainMeters: 50
        }
      }
    });
    const pushToken = "f".repeat(64);
    await app.inject({
      method: "PUT",
      url: "/v1/devices/push-token",
      headers: { authorization: `Bearer ${rider.accessToken}` },
      payload: { token: pushToken, environment: "sandbox" }
    });
    await app.inject({
      method: "PUT",
      url: `/v1/groups/${retainedGroup.id}/live-location`,
      headers: { authorization: `Bearer ${rider.accessToken}` },
      payload: {
        latitude: 39.9042,
        longitude: 116.4074,
        capturedAt: "2026-07-28T01:30:00.000Z"
      }
    });

    const unauthenticatedExport = await app.inject({
      method: "GET",
      url: "/v1/me/export"
    });
    assert.equal(unauthenticatedExport.statusCode, 401);

    const exportResponse = await app.inject({
      method: "GET",
      url: "/v1/me/export",
      headers: { authorization: `Bearer ${rider.accessToken}` }
    });
    assert.equal(exportResponse.statusCode, 200);
    const exported = exportResponse.json();
    assert.equal(exported.formatVersion, 1);
    assert.equal(exported.account.id, rider.user.id);
    assert.equal(exported.friends[0].id, teammate.user.id);
    assert.deepEqual(
      exported.groups.map((group: { id: string }) => group.id).sort(),
      [ownedGroup.id, retainedGroup.id].sort()
    );
    assert.equal(exported.rides[0].id, rideId);
    assert.equal("deviceIdHashes" in exported.account, false);
    assert.equal(JSON.stringify(exported).includes(pushToken), false);

    const missingConfirmation = await app.inject({
      method: "DELETE",
      url: "/v1/me",
      headers: { authorization: `Bearer ${rider.accessToken}` },
      payload: {}
    });
    assert.equal(missingConfirmation.statusCode, 400);

    const deleted = await app.inject({
      method: "DELETE",
      url: "/v1/me",
      headers: { authorization: `Bearer ${rider.accessToken}` },
      payload: { confirmation: "DELETE" }
    });
    assert.equal(deleted.statusCode, 204);

    const deletedSession = await app.inject({
      method: "GET",
      url: "/v1/me",
      headers: { authorization: `Bearer ${rider.accessToken}` }
    });
    assert.equal(deletedSession.statusCode, 401);

    const teammateFriends = await app.inject({
      method: "GET",
      url: "/v1/friends",
      headers: { authorization: `Bearer ${teammate.accessToken}` }
    });
    assert.deepEqual(teammateFriends.json().friends, []);

    const teammateGroups = await app.inject({
      method: "GET",
      url: "/v1/groups",
      headers: { authorization: `Bearer ${teammate.accessToken}` }
    });
    assert.equal(teammateGroups.json().groups.length, 1);
    assert.equal(teammateGroups.json().groups[0].id, retainedGroup.id);
    assert.deepEqual(
      teammateGroups.json().groups[0].members.map(
        (member: { id: string }) => member.id
      ),
      [teammate.user.id]
    );

    const ownedGroupToken = await app.inject({
      method: "POST",
      url: `/v1/voice/rooms/${ownedGroup.id}/token`,
      headers: { authorization: `Bearer ${teammate.accessToken}` },
      payload: { canPublish: true, canSubscribe: true }
    });
    assert.equal(ownedGroupToken.statusCode, 404);

    const remainingLocations = await app.inject({
      method: "GET",
      url: `/v1/groups/${retainedGroup.id}/live-locations`,
      headers: { authorization: `Bearer ${teammate.accessToken}` }
    });
    assert.deepEqual(remainingLocations.json().locations, []);

    const persistedState = await readFile(dataFile, "utf8");
    assert.equal(persistedState.includes(rider.user.id), false);
    assert.equal(persistedState.includes(rideId), false);
    assert.equal(persistedState.includes(pushToken), false);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});
