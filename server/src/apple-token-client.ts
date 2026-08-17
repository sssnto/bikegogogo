import { readFile } from "node:fs/promises";

import { importPKCS8, SignJWT } from "jose";
import { z } from "zod";

const appleIssuer = "https://appleid.apple.com";

const tokenResponseSchema = z.object({
  access_token: z.string().min(1),
  refresh_token: z.string().min(1).optional(),
  id_token: z.string().min(1)
});

const appleErrorSchema = z.object({
  error: z.string().optional()
});

export type AppleTokenExchange = {
  accessToken: string;
  refreshToken?: string;
  identityToken: string;
};

export type AppleTokenClient = {
  exchangeAuthorizationCode(code: string): Promise<AppleTokenExchange>;
  revoke(token: string, tokenType: "access_token" | "refresh_token"): Promise<void>;
};

export class AppleTokenClientError extends Error {
  constructor(
    public readonly code: "authorization_rejected" | "service_unavailable",
    message: string
  ) {
    super(message);
  }
}

export async function createAppleTokenClient(config: {
  teamId: string;
  keyId: string;
  clientId: string;
  privateKeyPath: string;
  fetchImplementation?: typeof fetch;
}): Promise<AppleTokenClient> {
  const privateKeyPEM = await readFile(config.privateKeyPath, "utf8");
  const privateKey = await importPKCS8(privateKeyPEM, "ES256");
  const request = config.fetchImplementation ?? fetch;

  const clientSecret = async (): Promise<string> => {
    const issuedAt = Math.floor(Date.now() / 1000);
    return new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: config.keyId })
      .setIssuer(config.teamId)
      .setSubject(config.clientId)
      .setAudience(appleIssuer)
      .setIssuedAt(issuedAt)
      .setExpirationTime(issuedAt + 5 * 60)
      .sign(privateKey);
  };

  const post = async (
    path: "/auth/token" | "/auth/revoke",
    parameters: Record<string, string>
  ): Promise<Response> => {
    try {
      return await request(`${appleIssuer}${path}`, {
        method: "POST",
        headers: {
          accept: "application/json",
          "content-type": "application/x-www-form-urlencoded"
        },
        body: new URLSearchParams({
          ...parameters,
          client_id: config.clientId,
          client_secret: await clientSecret()
        })
      });
    } catch {
      throw new AppleTokenClientError(
        "service_unavailable",
        "Apple token service is unavailable"
      );
    }
  };

  const errorFor = async (response: Response): Promise<AppleTokenClientError> => {
    const payload = appleErrorSchema.safeParse(
      await response.json().catch(() => ({}))
    );
    const reason = payload.success ? payload.data.error : undefined;
    if (response.status >= 400 && response.status < 500) {
      return new AppleTokenClientError(
        "authorization_rejected",
        reason ?? "Apple rejected the authorization code"
      );
    }
    return new AppleTokenClientError(
      "service_unavailable",
      reason ?? "Apple token service is unavailable"
    );
  };

  return {
    async exchangeAuthorizationCode(code) {
      const response = await post("/auth/token", {
        code,
        grant_type: "authorization_code"
      });
      if (!response.ok) throw await errorFor(response);

      const payload = await response.json().catch(() => undefined);
      const parsed = tokenResponseSchema.safeParse(payload);
      if (!parsed.success) {
        throw new AppleTokenClientError(
          "service_unavailable",
          "Apple returned an invalid token response"
        );
      }
      return {
        accessToken: parsed.data.access_token,
        refreshToken: parsed.data.refresh_token,
        identityToken: parsed.data.id_token
      };
    },

    async revoke(token, tokenType) {
      const response = await post("/auth/revoke", {
        token,
        token_type_hint: tokenType
      });
      if (!response.ok) throw await errorFor(response);
    }
  };
}
