import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { decodeProtectedHeader } from "jose";

import {
  AppleTokenClientError,
  createAppleTokenClient
} from "../src/apple-token-client.js";

const withPrivateKey = async (
  operation: (privateKeyPath: string) => Promise<void>
): Promise<void> => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "bikegogogo-apple-"));
  try {
    const { privateKey } = generateKeyPairSync("ec", {
      namedCurve: "P-256"
    });
    const privateKeyPath = path.join(directory, "AuthKey_TEST.p8");
    await writeFile(privateKeyPath, privateKey.export({
      type: "pkcs8",
      format: "pem"
    }));
    await operation(privateKeyPath);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
};

test("Apple token client exchanges a code and revokes the refresh token", async () => {
  await withPrivateKey(async (privateKeyPath) => {
    const requests: Array<{ url: string; body: URLSearchParams }> = [];
    const request: typeof fetch = async (input, init) => {
      const url = input.toString();
      const body = new URLSearchParams(init?.body?.toString());
      requests.push({ url, body });
      if (url.endsWith("/auth/token")) {
        return Response.json({
          access_token: "apple-access-token",
          refresh_token: "apple-refresh-token",
          id_token: "apple-identity-token"
        });
      }
      return new Response(null, { status: 200 });
    };
    const client = await createAppleTokenClient({
      teamId: "TESTTEAMID",
      keyId: "TESTKEYID",
      clientId: "com.example.BikeGoGo",
      privateKeyPath,
      fetchImplementation: request
    });

    const tokens = await client.exchangeAuthorizationCode("one-time-code");
    await client.revoke(tokens.refreshToken!, "refresh_token");

    assert.equal(tokens.identityToken, "apple-identity-token");
    assert.equal(requests[0].body.get("grant_type"), "authorization_code");
    assert.equal(requests[0].body.get("code"), "one-time-code");
    assert.equal(requests[0].body.get("client_id"), "com.example.BikeGoGo");
    assert.deepEqual(
      decodeProtectedHeader(requests[0].body.get("client_secret")!),
      { alg: "ES256", kid: "TESTKEYID" }
    );
    assert.equal(requests[1].body.get("token"), "apple-refresh-token");
    assert.equal(requests[1].body.get("token_type_hint"), "refresh_token");
  });
});

test("Apple token client distinguishes rejected codes from service failures", async () => {
  await withPrivateKey(async (privateKeyPath) => {
    const client = await createAppleTokenClient({
      teamId: "TESTTEAMID",
      keyId: "TESTKEYID",
      clientId: "com.example.BikeGoGo",
      privateKeyPath,
      fetchImplementation: async () => Response.json(
        { error: "invalid_grant" },
        { status: 400 }
      )
    });

    await assert.rejects(
      client.exchangeAuthorizationCode("expired-code"),
      (error: unknown) => (
        error instanceof AppleTokenClientError
        && error.code === "authorization_rejected"
      )
    );
  });
});
