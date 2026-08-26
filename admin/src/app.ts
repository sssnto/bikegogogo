import rateLimit from "@fastify/rate-limit";
import { readFile } from "node:fs/promises";
import path from "node:path";
import Fastify, { type FastifyRequest } from "fastify";
import { z } from "zod";

import { AdminDatabase, type AdminSession } from "./database.js";
import {
  dataFreshnessMetrics,
  growthMetrics,
  overviewMetrics,
  periodForDays,
  pushDeliveryMetrics,
  retentionMetrics,
  rideMetrics,
  searchUsers,
  socialMetrics,
  userSummary,
  versionMetrics,
  voiceQualityMetrics
} from "./metrics.js";
import {
  cookie,
  parseCookies,
  randomToken,
  sha256,
  verifyPassword,
  verifyTOTP
} from "./security.js";
import type { AdminRole } from "./types.js";

export type AdminAppConfig = {
  databaseUrl: string;
  encryptionSecret: string;
  initialUsername?: string;
  initialPasswordHash?: string;
  initialTOTPSecret?: string;
  cookieSecure: boolean;
  trustProxy?: boolean | number | string;
  revision?: string;
  publicDirectory?: string;
};

const sessionCookieName = "bikegogogo_admin_session";
const csrfCookieName = "bikegogogo_admin_csrf";

const daysSchema = z.object({
  days: z.coerce.number().int().min(1).max(90).default(7)
});

export async function createAdminApp(config: AdminAppConfig) {
  const app = Fastify({
    logger: true,
    trustProxy: (config.trustProxy ?? false) as boolean | string
  });
  const database = new AdminDatabase(config.databaseUrl, config.encryptionSecret);
  await database.initialize();

  if (config.initialUsername && config.initialPasswordHash && config.initialTOTPSecret) {
    const created = await database.bootstrapAdmin({
      username: config.initialUsername,
      passwordHash: config.initialPasswordHash,
      totpSecret: config.initialTOTPSecret,
      role: "admin"
    });
    if (created) app.log.info({ username: config.initialUsername }, "Initial admin created");
  }

  await app.register(rateLimit, { global: true, max: 180, timeWindow: "1 minute" });
  app.addHook("onRequest", async (request, reply) => {
    reply.header("x-request-id", request.id);
    reply.header("x-content-type-options", "nosniff");
    reply.header("x-frame-options", "DENY");
    reply.header("referrer-policy", "no-referrer");
    reply.header("permissions-policy", "camera=(), microphone=(), geolocation=()");
    reply.header(
      "content-security-policy",
      "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
    );
    if (request.url.startsWith("/admin/api/")) reply.header("cache-control", "no-store");
  });
  app.addHook("onClose", async () => database.close());

  const sessionFor = async (request: FastifyRequest): Promise<AdminSession> => {
    const token = parseCookies(request.headers.cookie)[sessionCookieName];
    if (!token) throw Object.assign(new Error("Authentication required"), { statusCode: 401 });
    const session = await database.sessionFor(token);
    if (!session) throw Object.assign(new Error("Session expired"), { statusCode: 401 });
    return session;
  };

  const requireRole = (session: AdminSession, roles: AdminRole[]) => {
    if (!roles.includes(session.role)) {
      throw Object.assign(new Error("Insufficient permission"), { statusCode: 403 });
    }
  };

  const requireCSRF = (request: FastifyRequest, session: AdminSession) => {
    const token = request.headers["x-csrf-token"];
    if (typeof token !== "string" || sha256(token) !== session.csrfTokenHash) {
      throw Object.assign(new Error("Invalid CSRF token"), { statusCode: 403 });
    }
  };

  app.get("/health", async (_request, reply) => {
    try {
      await database.healthCheck();
      return {
        ok: true,
        service: "bikegogogo-admin",
        revision: config.revision ?? "development"
      };
    } catch (error) {
      app.log.error({ err: error }, "Admin database health check failed");
      return reply.status(503).send({ ok: false, service: "bikegogogo-admin" });
    }
  });

  const loginSchema = z.object({
    username: z.string().trim().min(3).max(80),
    password: z.string().min(12).max(256)
  });
  app.post("/admin/api/v1/auth/login", {
    config: { rateLimit: { max: 8, timeWindow: "15 minutes" } }
  }, async (request, reply) => {
    const body = loginSchema.parse(request.body);
    const credentials = await database.credentialsFor(body.username);
    const locked = credentials?.lockedUntil
      && new Date(credentials.lockedUntil).getTime() > Date.now();
    const valid = credentials
      && !credentials.disabled
      && !locked
      && await verifyPassword(credentials.passwordHash, body.password);
    if (!valid) {
      if (credentials && !credentials.disabled) await database.recordLoginFailure(credentials.id);
      await database.audit({
        adminId: credentials?.id,
        action: "admin.login.password",
        result: "failure",
        ip: request.ip
      });
      return reply.status(401).send({
        error: "invalid_credentials",
        message: "用户名或密码错误，连续失败 5 次会锁定 15 分钟。"
      });
    }
    const challengeToken = randomToken();
    await database.createLoginChallenge(credentials.id, challengeToken);
    return { challengeToken, requiresTOTP: true };
  });

  const totpSchema = z.object({
    challengeToken: z.string().min(30).max(200),
    code: z.string().regex(/^\d{6}$/)
  });
  app.post("/admin/api/v1/auth/totp/verify", {
    config: { rateLimit: { max: 10, timeWindow: "10 minutes" } }
  }, async (request, reply) => {
    const body = totpSchema.parse(request.body);
    const credentials = await database.consumeLoginChallenge(body.challengeToken);
    const valid = credentials
      && !credentials.disabled
      && verifyTOTP(database.decryptTOTPSecret(credentials.encryptedTOTPSecret), body.code);
    if (!valid) {
      await database.audit({
        adminId: credentials?.id,
        action: "admin.login.totp",
        result: "failure",
        ip: request.ip
      });
      return reply.status(401).send({ error: "invalid_totp", message: "验证码无效或已过期。" });
    }
    const sessionToken = randomToken();
    const csrfToken = randomToken();
    await database.createSession({
      adminId: credentials.id,
      token: sessionToken,
      csrfToken,
      ip: request.ip,
      userAgent: request.headers["user-agent"]
    });
    await database.audit({
      adminId: credentials.id,
      action: "admin.login",
      result: "success",
      ip: request.ip
    });
    reply.header("set-cookie", [
      cookie(sessionCookieName, sessionToken, {
        httpOnly: true,
        secure: config.cookieSecure,
        maxAge: 8 * 60 * 60
      }),
      cookie(csrfCookieName, csrfToken, {
        secure: config.cookieSecure,
        maxAge: 8 * 60 * 60
      })
    ]);
    return { user: { username: credentials.username, role: credentials.role } };
  });

  app.get("/admin/api/v1/auth/me", async (request) => {
    const session = await sessionFor(request);
    return { user: { username: session.username, role: session.role }, expiresAt: session.expiresAt };
  });

  app.delete("/admin/api/v1/auth/session", async (request, reply) => {
    const session = await sessionFor(request);
    requireCSRF(request, session);
    const token = parseCookies(request.headers.cookie)[sessionCookieName]!;
    await database.revokeSession(token);
    await database.audit({
      adminId: session.adminId,
      action: "admin.logout",
      result: "success",
      ip: request.ip
    });
    reply.header("set-cookie", [
      cookie(sessionCookieName, "", { httpOnly: true, secure: config.cookieSecure, maxAge: 0 }),
      cookie(csrfCookieName, "", { secure: config.cookieSecure, maxAge: 0 })
    ]);
    return reply.status(204).send();
  });

  app.get("/admin/api/v1/overview", async (request) => {
    await sessionFor(request);
    const query = daysSchema.parse(request.query);
    const period = periodForDays(query.days);
    const [snapshot, quality] = await Promise.all([
      database.businessSnapshot(),
      database.analyticsSummary(period.from, period.to)
    ]);
    return { ...overviewMetrics(snapshot, period), quality };
  });

  app.get("/admin/api/v1/rides", async (request) => {
    await sessionFor(request);
    const period = periodForDays(daysSchema.parse(request.query).days);
    const snapshot = await database.businessSnapshot();
    return { ...rideMetrics(snapshot.state, period), freshness: snapshot.updatedAt };
  });

  app.get("/admin/api/v1/social", async (request) => {
    await sessionFor(request);
    const period = periodForDays(daysSchema.parse(request.query).days);
    const snapshot = await database.businessSnapshot();
    return { ...socialMetrics(snapshot.state, period), freshness: snapshot.updatedAt };
  });

  app.get("/admin/api/v1/growth", async (request) => {
    await sessionFor(request);
    const period = periodForDays(daysSchema.parse(request.query).days);
    const [snapshot, analytics] = await Promise.all([
      database.businessSnapshot(),
      database.analyticsEvents(period.from, period.to)
    ]);
    return growthMetrics(snapshot.state, analytics.events, period, analytics.truncated);
  });

  app.get("/admin/api/v1/retention", async (request) => {
    await sessionFor(request);
    const period = periodForDays(daysSchema.parse(request.query).days);
    const analytics = await database.analyticsEvents(period.from, period.to);
    return {
      ...retentionMetrics(analytics.events, period),
      truncated: analytics.truncated
    };
  });

  app.get("/admin/api/v1/voice", async (request) => {
    await sessionFor(request);
    const period = periodForDays(daysSchema.parse(request.query).days);
    const [snapshot, analytics] = await Promise.all([
      database.businessSnapshot(),
      database.analyticsEvents(period.from, period.to)
    ]);
    return {
      ...voiceQualityMetrics(snapshot.state, analytics.events, period),
      freshness: snapshot.updatedAt,
      truncated: analytics.truncated
    };
  });

  app.get("/admin/api/v1/push", async (request) => {
    await sessionFor(request);
    const period = periodForDays(daysSchema.parse(request.query).days);
    const [snapshot, analytics] = await Promise.all([
      database.businessSnapshot(),
      database.analyticsEvents(period.from, period.to)
    ]);
    return {
      ...pushDeliveryMetrics(snapshot.state, analytics.events, period),
      freshness: snapshot.updatedAt,
      truncated: analytics.truncated
    };
  });

  app.get("/admin/api/v1/versions", async (request) => {
    await sessionFor(request);
    const period = periodForDays(daysSchema.parse(request.query).days);
    const analytics = await database.analyticsEvents(period.from, period.to);
    return { ...versionMetrics(analytics.events, period), truncated: analytics.truncated };
  });

  app.get("/admin/api/v1/data-freshness", async (request) => {
    await sessionFor(request);
    const [snapshot, analytics] = await Promise.all([
      database.businessSnapshot(),
      database.analyticsFreshness()
    ]);
    return dataFreshnessMetrics(snapshot.updatedAt, analytics);
  });

  app.get("/admin/api/v1/quality", async (request) => {
    await sessionFor(request);
    const period = periodForDays(daysSchema.parse(request.query).days);
    const [quality, snapshot] = await Promise.all([
      database.analyticsSummary(period.from, period.to),
      database.businessSnapshot()
    ]);
    return {
      ...quality,
      errorRatePercent: quality.total ? Number((quality.errors / quality.total * 100).toFixed(2)) : 0,
      businessStateUpdatedAt: snapshot.updatedAt,
      note: "API 与客户端运营事件从本版本开始累计，历史日志不会自动补录。"
    };
  });

  const usersQuerySchema = z.object({
    q: z.string().max(100).default(""),
    page: z.coerce.number().int().min(1).default(1),
    pageSize: z.coerce.number().int().min(10).max(100).default(30)
  });
  app.get("/admin/api/v1/users", async (request) => {
    const session = await sessionFor(request);
    const query = usersQuerySchema.parse(request.query);
    const snapshot = await database.businessSnapshot();
    await database.audit({
      adminId: session.adminId,
      action: "support.user.search",
      result: "success",
      ip: request.ip,
      metadata: { queryLength: query.q.length, page: query.page }
    });
    return searchUsers(snapshot.state, query.q, query.page, query.pageSize);
  });

  app.get("/admin/api/v1/users/:userId", async (request, reply) => {
    const session = await sessionFor(request);
    const params = z.object({ userId: z.string().min(1).max(100) }).parse(request.params);
    const snapshot = await database.businessSnapshot();
    const user = userSummary(snapshot.state, params.userId);
    await database.audit({
      adminId: session.adminId,
      action: "support.user.view",
      result: user ? "success" : "failure",
      ip: request.ip,
      targetType: "user",
      targetId: params.userId
    });
    return user ? { user } : reply.status(404).send({ error: "user_not_found" });
  });

  app.get("/admin/api/v1/audit-logs", async (request) => {
    const session = await sessionFor(request);
    requireRole(session, ["admin"]);
    return { logs: await database.auditLogs() };
  });

  const publicDirectory = path.resolve(config.publicDirectory ?? "./public");
  const staticFiles = new Map<string, { type: string; body: Buffer }>();
  for (const [url, filename, type] of [
    ["/", "index.html", "text/html; charset=utf-8"],
    ["/index.html", "index.html", "text/html; charset=utf-8"],
    ["/styles.css", "styles.css", "text/css; charset=utf-8"],
    ["/app.js", "app.js", "text/javascript; charset=utf-8"]
  ] as const) {
    staticFiles.set(url, { type, body: await readFile(path.join(publicDirectory, filename)) });
  }
  app.get("/", async (_request, reply) => {
    const file = staticFiles.get("/")!;
    return reply.type(file.type).send(file.body);
  });
  app.get("/index.html", async (_request, reply) => {
    const file = staticFiles.get("/index.html")!;
    return reply.type(file.type).send(file.body);
  });
  app.get("/styles.css", async (_request, reply) => {
    const file = staticFiles.get("/styles.css")!;
    return reply.type(file.type).send(file.body);
  });
  app.get("/app.js", async (_request, reply) => {
    const file = staticFiles.get("/app.js")!;
    return reply.type(file.type).send(file.body);
  });

  app.setErrorHandler((error, request, reply) => {
    if (error instanceof z.ZodError) {
      return reply.status(400).send({ error: "invalid_request", details: error.flatten() });
    }
    const statusCode = typeof error === "object" && error !== null && "statusCode" in error
      && typeof error.statusCode === "number" ? error.statusCode : 500;
    const message = error instanceof Error ? error.message : "Request failed";
    if (statusCode >= 500) request.log.error(error);
    return reply.status(statusCode).send({
      error: statusCode === 401 ? "unauthorized" : statusCode === 403 ? "forbidden" : "internal_error",
      message: statusCode >= 500 ? "后台服务暂时不可用。" : message
    });
  });

  return app;
}
