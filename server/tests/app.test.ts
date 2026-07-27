import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { createApp } from "../src/app.js";

const configFor = (dataFile: string) => ({
  livekitUrl: "wss://example.livekit.cloud",
  livekitApiKey: "API_TEST_KEY",
  livekitApiSecret: "test-secret",
  allowedOrigins: "",
  dataFile,
  appleBundleId: "com.sssnto.BikeGoGo",
  sessionTTLDays: 30,
  appleIdentityVerifier: async (identityToken: string) => ({
    subject: identityToken.startsWith("b")
      ? "second-apple-user-subject"
      : "apple-user-subject",
    email: "rider@example.com"
  })
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
