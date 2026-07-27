import { createHash } from "node:crypto";

import { createRemoteJWKSet, jwtVerify } from "jose";

export type AppleIdentity = {
  subject: string;
  email?: string;
};

export type AppleIdentityVerifier = (
  identityToken: string,
  rawNonce: string
) => Promise<AppleIdentity>;

export class AppleIdentityError extends Error {}

export function createAppleIdentityVerifier(
  bundleIdentifier: string
): AppleIdentityVerifier {
  const appleKeys = createRemoteJWKSet(
    new URL("https://appleid.apple.com/auth/keys")
  );

  return async (identityToken, rawNonce) => {
    try {
      const { payload } = await jwtVerify(identityToken, appleKeys, {
        issuer: "https://appleid.apple.com",
        audience: bundleIdentifier
      });
      const expectedNonce = createHash("sha256").update(rawNonce).digest("hex");
      if (!payload.sub || payload.nonce !== expectedNonce) {
        throw new AppleIdentityError("Apple identity token is invalid");
      }
      return {
        subject: payload.sub,
        email: typeof payload.email === "string" ? payload.email : undefined
      };
    } catch (error) {
      if (error instanceof AppleIdentityError) throw error;
      throw new AppleIdentityError("Apple identity token verification failed");
    }
  };
}
