import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { Pool } from "pg";

import { createApp } from "../src/app.js";

const databaseUrl = process.env.TEST_DATABASE_URL;

test("PostgreSQL imports JSON once and remains the source of truth", {
  skip: !databaseUrl
}, async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-pg-test-"));
  const dataFile = path.join(directory, "bikegogogo.json");
  const deviceId = "postgres-import-device";
  const now = new Date().toISOString();
  const legacyState = {
    version: 1,
    users: [{
      id: "usr_imported",
      deviceIdHash: createHash("sha256").update(deviceId).digest("hex"),
      displayName: "Imported Rider",
      friendCode: "IMPORT88",
      createdAt: now,
      updatedAt: now
    }],
    sessions: [],
    friendRequests: [],
    friendships: [],
    groups: []
  };
  const adminPool = new Pool({ connectionString: databaseUrl });
  let app: Awaited<ReturnType<typeof createApp>> | undefined;

  try {
    await adminPool.query("DROP TABLE IF EXISTS bikegogogo_app_state");
    await writeFile(dataFile, JSON.stringify(legacyState), "utf8");

    const config = {
      livekitUrl: "wss://example.livekit.cloud",
      livekitApiKey: "API_TEST_KEY",
      livekitApiSecret: "test-secret",
      allowedOrigins: "",
      dataFile,
      databaseUrl,
      appleBundleId: "com.sssnto.BikeGoGo",
      sessionTTLDays: 30,
      appleIdentityVerifier: async () => ({ subject: "test-apple-subject" })
    };

    app = await createApp(config);
    const health = await app.inject({ method: "GET", url: "/health" });
    assert.equal(health.statusCode, 200);
    assert.equal(health.json().storage, "postgresql");

    const login = await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId, displayName: "Ignored Name" }
    });
    assert.equal(login.statusCode, 200);
    assert.equal(login.json().user.id, "usr_imported");

    const updated = await app.inject({
      method: "PATCH",
      url: "/v1/me",
      headers: { authorization: `Bearer ${login.json().accessToken}` },
      payload: { displayName: "Database Rider" }
    });
    assert.equal(updated.statusCode, 200);
    assert.equal(updated.json().user.displayName, "Database Rider");

    await app.close();
    app = undefined;

    const mirror = JSON.parse(await readFile(dataFile, "utf8"));
    assert.equal(mirror.version, 5);
    assert.equal(mirror.users[0].displayName, "Database Rider");
    const backup = JSON.parse(
      await readFile(`${dataFile}.pre-postgresql.json`, "utf8")
    );
    assert.equal(backup.version, 1);

    await writeFile(dataFile, JSON.stringify({
      version: 4,
      users: [],
      sessions: [],
      friendRequests: [],
      friendships: [],
      groups: [],
      rides: [],
      pushTokens: []
    }), "utf8");

    app = await createApp(config);
    const restartedLogin = await app.inject({
      method: "POST",
      url: "/v1/auth/guest",
      payload: { deviceId, displayName: "Wrong JSON Name" }
    });
    assert.equal(restartedLogin.statusCode, 200);
    assert.equal(restartedLogin.json().user.id, "usr_imported");
    assert.equal(restartedLogin.json().user.displayName, "Database Rider");

    const databaseState = await adminPool.query<{
      payload: { users: Array<{ displayName: string }> };
    }>("SELECT payload FROM bikegogogo_app_state WHERE singleton = 1");
    assert.equal(
      databaseState.rows[0].payload.users[0].displayName,
      "Database Rider"
    );
  } finally {
    await app?.close();
    await adminPool.query("DROP TABLE IF EXISTS bikegogogo_app_state");
    await adminPool.end();
    await rm(directory, { recursive: true, force: true });
  }
});
