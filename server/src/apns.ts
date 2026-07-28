import {
  connect,
  constants,
  type ClientHttp2Session,
  type IncomingHttpHeaders
} from "node:http2";
import { readFile } from "node:fs/promises";

import { importPKCS8, SignJWT } from "jose";

export type APNsEnvironment = "sandbox" | "production";

export type PushNotification = {
  title: string;
  body: string;
  event:
    | "friend_request"
    | "friend_accepted"
    | "group_invitation"
    | "voice_invitation"
    | "voice_cancelled";
  entityId?: string;
  data?: Record<string, string>;
};

export type PushSendResult = {
  invalidTokens: string[];
  failedCount: number;
};

export interface NotificationSender {
  readonly environment: APNsEnvironment;
  send(
    tokens: string[],
    notification: PushNotification
  ): Promise<PushSendResult>;
}

type APNsConfig = {
  keyId: string;
  teamId: string;
  topic: string;
  environment: APNsEnvironment;
  privateKeyPath: string;
};

type APNsResponse = {
  status: number;
  reason?: string;
};

const invalidTokenReasons = new Set([
  "BadDeviceToken",
  "DeviceTokenNotForTopic",
  "Unregistered"
]);

class APNsSender implements NotificationSender {
  private cachedAuthorization?: { value: string; issuedAt: number };

  constructor(
    private readonly config: APNsConfig,
    private readonly privateKey: Awaited<ReturnType<typeof importPKCS8>>
  ) {}

  get environment(): APNsEnvironment {
    return this.config.environment;
  }

  async send(
    tokens: string[],
    notification: PushNotification
  ): Promise<PushSendResult> {
    if (tokens.length === 0) {
      return { invalidTokens: [], failedCount: 0 };
    }

    const authority = this.environment === "production"
      ? "https://api.push.apple.com"
      : "https://api.sandbox.push.apple.com";
    const session = connect(authority);
    session.setTimeout(10_000, () => {
      session.destroy(new Error("APNs connection timed out"));
    });
    const authorization = await this.authorization();
    const invalidTokens: string[] = [];
    let failedCount = 0;

    try {
      await waitForConnection(session);
      for (const token of tokens) {
        const response = await this.sendOne(
          session,
          token,
          authorization,
          notification
        );
        if (
          response.status === 410
          || (response.status === 400 && invalidTokenReasons.has(response.reason ?? ""))
        ) {
          invalidTokens.push(token);
        } else if (response.status < 200 || response.status >= 300) {
          failedCount += 1;
        }
      }
    } finally {
      session.close();
    }

    return { invalidTokens, failedCount };
  }

  private async authorization(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    if (
      this.cachedAuthorization
      && now - this.cachedAuthorization.issuedAt < 50 * 60
    ) {
      return this.cachedAuthorization.value;
    }

    const value = await new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: this.config.keyId })
      .setIssuer(this.config.teamId)
      .setIssuedAt(now)
      .sign(this.privateKey);
    this.cachedAuthorization = { value, issuedAt: now };
    return value;
  }

  private sendOne(
    session: ClientHttp2Session,
    token: string,
    authorization: string,
    notification: PushNotification
  ): Promise<APNsResponse> {
    const payload = JSON.stringify({
      aps: {
        alert: {
          title: notification.title,
          body: notification.body
        },
        sound: "default",
        "thread-id": notification.event
      },
      event: notification.event,
      entityId: notification.entityId,
      ...notification.data
    });

    return new Promise((resolve, reject) => {
      const request = session.request({
        [constants.HTTP2_HEADER_METHOD]: "POST",
        [constants.HTTP2_HEADER_PATH]: `/3/device/${token}`,
        authorization: `bearer ${authorization}`,
        "apns-topic": this.config.topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json"
      });
      let status = 0;
      let responseBody = "";

      request.setEncoding("utf8");
      request.on("response", (headers: IncomingHttpHeaders) => {
        status = Number(headers[constants.HTTP2_HEADER_STATUS] ?? 0);
      });
      request.on("data", (chunk: string) => {
        responseBody += chunk;
      });
      request.on("end", () => {
        let reason: string | undefined;
        if (responseBody) {
          try {
            reason = (JSON.parse(responseBody) as { reason?: string }).reason;
          } catch {
            reason = "InvalidAPNsResponse";
          }
        }
        resolve({ status, reason });
      });
      request.on("error", reject);
      request.setTimeout(10_000, () => {
        request.close(constants.NGHTTP2_CANCEL);
        reject(new Error("APNs request timed out"));
      });
      request.end(payload);
    });
  }
}

const waitForConnection = (session: ClientHttp2Session): Promise<void> =>
  new Promise((resolve, reject) => {
    if (!session.connecting) {
      resolve();
      return;
    }
    session.once("connect", resolve);
    session.once("error", reject);
  });

export async function createAPNsSender(
  config: APNsConfig
): Promise<NotificationSender> {
  const privateKeyPEM = await readFile(config.privateKeyPath, "utf8");
  const privateKey = await importPKCS8(privateKeyPEM, "ES256");
  return new APNsSender(config, privateKey);
}
