import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { createApp } from "../src/app.js";

const configFor = (dataFile: string) => ({
  livekitUrl: "wss://example.livekit.cloud",
  livekitApiKey: "API_TEST_KEY",
  livekitApiSecret: "test-secret",
  allowedOrigins: "",
  dataFile
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
