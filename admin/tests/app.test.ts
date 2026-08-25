import assert from "node:assert/strict";
import test from "node:test";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";

import { createAdminApp } from "../src/app.js";
import { hashPassword, totpCode } from "../src/security.js";

const databaseUrl = process.env.TEST_DATABASE_URL;
const integrationTest = databaseUrl ? test : test.skip;

const cookieHeader = (setCookie: string | string[] | undefined): string => {
  const values = Array.isArray(setCookie) ? setCookie : setCookie ? [setCookie] : [];
  return values.map((value) => value.split(";", 1)[0]).join("; ");
};

integrationTest("admin login, TOTP and overview work against PostgreSQL", async () => {
  assert.ok(databaseUrl);
  assert.match(new URL(databaseUrl).pathname, /test/i, "integration tests require a test database");

  const pool = new Pool({ connectionString: databaseUrl });
  await pool.query(`
    CREATE TABLE IF NOT EXISTS bikegogogo_app_state (
      singleton SMALLINT PRIMARY KEY CHECK (singleton = 1),
      payload JSONB NOT NULL,
      revision BIGINT NOT NULL DEFAULT 0,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await pool.query(
    `INSERT INTO bikegogogo_app_state (singleton, payload, revision, updated_at)
     VALUES (1, $1::jsonb, 7, NOW())
     ON CONFLICT (singleton) DO UPDATE
       SET payload = EXCLUDED.payload, revision = EXCLUDED.revision, updated_at = NOW()`,
    [JSON.stringify({
      users: [{
        id: "integration-user",
        displayName: "测试骑手",
        friendCode: "TEST01",
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      }],
      rides: [],
      sessions: [],
      friendRequests: [],
      friendships: [],
      groups: [],
      pushTokens: [],
      voiceInvitations: []
    })]
  );

  const password = "integration-password-2026";
  const username = `admin-${randomUUID()}`;
  const totpSecret = "JBSWY3DPEHPK3PXP";
  const app = await createAdminApp({
    databaseUrl,
    encryptionSecret: "a".repeat(64),
    initialUsername: username,
    initialPasswordHash: await hashPassword(password),
    initialTOTPSecret: totpSecret,
    cookieSecure: false
  });

  try {
    const passwordResponse = await app.inject({
      method: "POST",
      url: "/admin/api/v1/auth/login",
      payload: { username, password }
    });
    assert.equal(passwordResponse.statusCode, 200);
    const challengeToken = passwordResponse.json().challengeToken as string;

    const totpResponse = await app.inject({
      method: "POST",
      url: "/admin/api/v1/auth/totp/verify",
      payload: { challengeToken, code: totpCode(totpSecret) }
    });
    assert.equal(totpResponse.statusCode, 200);
    assert.equal(totpResponse.json().user.role, "admin");

    const cookies = cookieHeader(totpResponse.headers["set-cookie"]);
    assert.match(cookies, /bikegogogo_admin_session=/);
    const overviewResponse = await app.inject({
      method: "GET",
      url: "/admin/api/v1/overview?days=7",
      headers: { cookie: cookies }
    });
    assert.equal(overviewResponse.statusCode, 200);
    assert.equal(overviewResponse.json().kpis.totalUsers, 1);

    const meResponse = await app.inject({
      method: "GET",
      url: "/admin/api/v1/auth/me",
      headers: { cookie: cookies }
    });
    assert.equal(meResponse.statusCode, 200);
    assert.equal(meResponse.json().user.username, username.toLowerCase());
  } finally {
    await app.close();
    await pool.query("DELETE FROM admin_users WHERE username = $1", [username.toLowerCase()]);
    await pool.end();
  }
});
