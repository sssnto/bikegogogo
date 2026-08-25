import assert from "node:assert/strict";
import test from "node:test";

import {
  decryptSecret,
  encryptSecret,
  generateTOTPSecret,
  hashPassword,
  totpCode,
  verifyPassword,
  verifyTOTP
} from "../src/security.js";

test("passwords use a verifiable Argon2id hash", async () => {
  const password = "correct-horse-battery-staple";
  const passwordHash = await hashPassword(password);

  assert.match(passwordHash, /^\$argon2id\$/);
  assert.equal(await verifyPassword(passwordHash, password), true);
  assert.equal(await verifyPassword(passwordHash, "incorrect-password"), false);
});

test("TOTP accepts the current window and rejects an unrelated code", () => {
  const secret = generateTOTPSecret();
  const now = Date.UTC(2026, 7, 25, 12, 0, 0);
  const code = totpCode(secret, now);

  assert.match(secret, /^[A-Z2-7]+$/);
  assert.equal(verifyTOTP(secret, code, now), true);
  assert.equal(verifyTOTP(secret, "000000", now), code === "000000");
});

test("encrypted TOTP secrets cannot be read without the server key", () => {
  const encrypted = encryptSecret("JBSWY3DPEHPK3PXP", "a".repeat(64));

  assert.notEqual(encrypted, "JBSWY3DPEHPK3PXP");
  assert.equal(decryptSecret(encrypted, "a".repeat(64)), "JBSWY3DPEHPK3PXP");
  assert.throws(() => decryptSecret(encrypted, "b".repeat(64)));
});
