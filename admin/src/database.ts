import { randomUUID } from "node:crypto";
import { Pool } from "pg";

import { decryptSecret, encryptSecret, sha256 } from "./security.js";
import type {
  AdminRole,
  AnalyticsEventRecord,
  AnalyticsEventSnapshot,
  AnalyticsFreshness,
  BusinessSnapshot,
  BusinessState
} from "./types.js";

type AdminCredentials = {
  id: string;
  username: string;
  passwordHash: string;
  encryptedTOTPSecret: string;
  role: AdminRole;
  failedLoginCount: number;
  lockedUntil?: string;
  disabled: boolean;
};

export type AdminSession = {
  id: string;
  adminId: string;
  username: string;
  role: AdminRole;
  csrfTokenHash: string;
  expiresAt: string;
  idleExpiresAt: string;
};

const emptyBusinessState = (): BusinessState => ({
  users: [],
  sessions: [],
  friendRequests: [],
  friendships: [],
  groups: [],
  rides: [],
  pushTokens: [],
  voiceInvitations: []
});

export class AdminDatabase {
  private readonly pool: Pool;

  constructor(
    databaseUrl: string,
    private readonly encryptionSecret: string
  ) {
    this.pool = new Pool({ connectionString: databaseUrl, max: 8 });
  }

  async initialize(): Promise<void> {
    await this.pool.query(`
      CREATE TABLE IF NOT EXISTS admin_users (
        id UUID PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        totp_secret_encrypted TEXT NOT NULL,
        role TEXT NOT NULL CHECK (role IN ('viewer', 'admin')),
        disabled BOOLEAN NOT NULL DEFAULT FALSE,
        failed_login_count INTEGER NOT NULL DEFAULT 0,
        locked_until TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        last_login_at TIMESTAMPTZ
      );

      CREATE TABLE IF NOT EXISTS admin_login_challenges (
        token_hash TEXT PRIMARY KEY,
        admin_id UUID NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
        expires_at TIMESTAMPTZ NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS admin_sessions (
        id UUID PRIMARY KEY,
        token_hash TEXT NOT NULL UNIQUE,
        csrf_token_hash TEXT NOT NULL,
        admin_id UUID NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
        expires_at TIMESTAMPTZ NOT NULL,
        idle_expires_at TIMESTAMPTZ NOT NULL,
        last_activity_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        ip_hash TEXT,
        user_agent TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS admin_audit_logs (
        id BIGSERIAL PRIMARY KEY,
        admin_id UUID REFERENCES admin_users(id) ON DELETE SET NULL,
        action TEXT NOT NULL,
        target_type TEXT,
        target_id TEXT,
        result TEXT NOT NULL,
        ip_hash TEXT,
        metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS admin_audit_logs_created_idx
        ON admin_audit_logs (created_at DESC);

      CREATE TABLE IF NOT EXISTS analytics_events (
        event_id UUID PRIMARY KEY,
        event_name TEXT NOT NULL,
        occurred_at TIMESTAMPTZ NOT NULL,
        received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        user_key TEXT,
        session_id UUID,
        app_version TEXT,
        build_number TEXT,
        platform TEXT NOT NULL,
        os_version TEXT,
        device_family TEXT,
        properties JSONB NOT NULL DEFAULT '{}'::jsonb
      );

      CREATE INDEX IF NOT EXISTS analytics_events_occurred_idx
        ON analytics_events (occurred_at DESC);
      CREATE INDEX IF NOT EXISTS analytics_events_name_time_idx
        ON analytics_events (event_name, occurred_at DESC);
      CREATE INDEX IF NOT EXISTS analytics_events_user_time_idx
        ON analytics_events (user_key, occurred_at DESC);
    `);

    await this.pool.query(`
      DELETE FROM admin_login_challenges WHERE expires_at <= NOW();
      DELETE FROM admin_sessions
        WHERE expires_at <= NOW() OR idle_expires_at <= NOW();
      DELETE FROM analytics_events
        WHERE occurred_at < NOW() - INTERVAL '90 days';
      DELETE FROM admin_audit_logs
        WHERE created_at < NOW() - INTERVAL '1 year';
    `);
  }

  async close(): Promise<void> {
    await this.pool.end();
  }

  async healthCheck(): Promise<void> {
    await this.pool.query("SELECT 1");
  }

  async bootstrapAdmin(input: {
    username: string;
    passwordHash: string;
    totpSecret: string;
    role: AdminRole;
  }): Promise<boolean> {
    const result = await this.pool.query(
      `INSERT INTO admin_users (
         id, username, password_hash, totp_secret_encrypted, role
       ) VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (username) DO NOTHING`,
      [
        randomUUID(),
        input.username.toLowerCase(),
        input.passwordHash,
        encryptSecret(input.totpSecret, this.encryptionSecret),
        input.role
      ]
    );
    return result.rowCount === 1;
  }

  async credentialsFor(username: string): Promise<AdminCredentials | undefined> {
    const result = await this.pool.query<{
      id: string;
      username: string;
      password_hash: string;
      totp_secret_encrypted: string;
      role: AdminRole;
      failed_login_count: number;
      locked_until: Date | null;
      disabled: boolean;
    }>(
      `SELECT id, username, password_hash, totp_secret_encrypted, role,
              failed_login_count, locked_until, disabled
         FROM admin_users WHERE username = $1`,
      [username.toLowerCase()]
    );
    const row = result.rows[0];
    if (!row) return undefined;
    return {
      id: row.id,
      username: row.username,
      passwordHash: row.password_hash,
      encryptedTOTPSecret: row.totp_secret_encrypted,
      role: row.role,
      failedLoginCount: row.failed_login_count,
      lockedUntil: row.locked_until?.toISOString(),
      disabled: row.disabled
    };
  }

  decryptTOTPSecret(encrypted: string): string {
    return decryptSecret(encrypted, this.encryptionSecret);
  }

  async recordLoginFailure(adminId: string): Promise<void> {
    await this.pool.query(
      `UPDATE admin_users
          SET failed_login_count = failed_login_count + 1,
              locked_until = CASE
                WHEN failed_login_count + 1 >= 5 THEN NOW() + INTERVAL '15 minutes'
                ELSE locked_until
              END,
              updated_at = NOW()
        WHERE id = $1`,
      [adminId]
    );
  }

  async createLoginChallenge(adminId: string, token: string): Promise<void> {
    await this.pool.query("DELETE FROM admin_login_challenges WHERE expires_at <= NOW()");
    await this.pool.query(
      `INSERT INTO admin_login_challenges (token_hash, admin_id, expires_at)
       VALUES ($1, $2, NOW() + INTERVAL '5 minutes')`,
      [sha256(token), adminId]
    );
  }

  async consumeLoginChallenge(token: string): Promise<AdminCredentials | undefined> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const challenge = await client.query<{ admin_id: string }>(
        `DELETE FROM admin_login_challenges
          WHERE token_hash = $1 AND expires_at > NOW()
          RETURNING admin_id`,
        [sha256(token)]
      );
      if (!challenge.rows[0]) {
        await client.query("ROLLBACK");
        return undefined;
      }
      const result = await client.query<{
        id: string;
        username: string;
        password_hash: string;
        totp_secret_encrypted: string;
        role: AdminRole;
        failed_login_count: number;
        locked_until: Date | null;
        disabled: boolean;
      }>(
        `SELECT id, username, password_hash, totp_secret_encrypted, role,
                failed_login_count, locked_until, disabled
           FROM admin_users WHERE id = $1 FOR UPDATE`,
        [challenge.rows[0].admin_id]
      );
      await client.query("COMMIT");
      const row = result.rows[0];
      if (!row) return undefined;
      return {
        id: row.id,
        username: row.username,
        passwordHash: row.password_hash,
        encryptedTOTPSecret: row.totp_secret_encrypted,
        role: row.role,
        failedLoginCount: row.failed_login_count,
        lockedUntil: row.locked_until?.toISOString(),
        disabled: row.disabled
      };
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async createSession(input: {
    adminId: string;
    token: string;
    csrfToken: string;
    ip?: string;
    userAgent?: string;
  }): Promise<void> {
    await this.pool.query(
      `INSERT INTO admin_sessions (
         id, token_hash, csrf_token_hash, admin_id, expires_at, idle_expires_at,
         ip_hash, user_agent
       ) VALUES ($1, $2, $3, $4, NOW() + INTERVAL '8 hours',
                 NOW() + INTERVAL '30 minutes', $5, $6)`,
      [
        randomUUID(),
        sha256(input.token),
        sha256(input.csrfToken),
        input.adminId,
        input.ip ? sha256(input.ip) : null,
        input.userAgent?.slice(0, 300) ?? null
      ]
    );
    await this.pool.query(
      `UPDATE admin_users SET failed_login_count = 0, locked_until = NULL,
              last_login_at = NOW(), updated_at = NOW() WHERE id = $1`,
      [input.adminId]
    );
  }

  async sessionFor(token: string): Promise<AdminSession | undefined> {
    const result = await this.pool.query<{
      id: string;
      admin_id: string;
      username: string;
      role: AdminRole;
      csrf_token_hash: string;
      expires_at: Date;
      idle_expires_at: Date;
    }>(
      `SELECT s.id, s.admin_id, u.username, u.role, s.csrf_token_hash,
              s.expires_at, s.idle_expires_at
         FROM admin_sessions s
         JOIN admin_users u ON u.id = s.admin_id
        WHERE s.token_hash = $1 AND s.expires_at > NOW()
          AND s.idle_expires_at > NOW() AND u.disabled = FALSE`,
      [sha256(token)]
    );
    const row = result.rows[0];
    if (!row) return undefined;
    await this.pool.query(
      `UPDATE admin_sessions SET last_activity_at = NOW(),
              idle_expires_at = LEAST(expires_at, NOW() + INTERVAL '30 minutes')
        WHERE id = $1`,
      [row.id]
    );
    return {
      id: row.id,
      adminId: row.admin_id,
      username: row.username,
      role: row.role,
      csrfTokenHash: row.csrf_token_hash,
      expiresAt: row.expires_at.toISOString(),
      idleExpiresAt: row.idle_expires_at.toISOString()
    };
  }

  async revokeSession(token: string): Promise<void> {
    await this.pool.query("DELETE FROM admin_sessions WHERE token_hash = $1", [sha256(token)]);
  }

  async audit(input: {
    adminId?: string;
    action: string;
    result: "success" | "failure";
    ip?: string;
    targetType?: string;
    targetId?: string;
    metadata?: Record<string, unknown>;
  }): Promise<void> {
    await this.pool.query(
      `INSERT INTO admin_audit_logs (
         admin_id, action, target_type, target_id, result, ip_hash, metadata
       ) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        input.adminId ?? null,
        input.action,
        input.targetType ?? null,
        input.targetId ?? null,
        input.result,
        input.ip ? sha256(input.ip) : null,
        JSON.stringify(input.metadata ?? {})
      ]
    );
  }

  async businessSnapshot(): Promise<BusinessSnapshot> {
    const result = await this.pool.query<{
      payload: Partial<BusinessState>;
      revision: string;
      updated_at: Date;
    }>(
      `SELECT payload, revision, updated_at
         FROM bikegogogo_app_state WHERE singleton = 1`
    );
    const row = result.rows[0];
    const base = emptyBusinessState();
    const payload = row?.payload ?? {};
    return {
      state: {
        ...base,
        ...payload,
        users: Array.isArray(payload.users) ? payload.users : [],
        sessions: Array.isArray(payload.sessions) ? payload.sessions : [],
        friendRequests: Array.isArray(payload.friendRequests) ? payload.friendRequests : [],
        friendships: Array.isArray(payload.friendships) ? payload.friendships : [],
        groups: Array.isArray(payload.groups) ? payload.groups : [],
        rides: Array.isArray(payload.rides) ? payload.rides : [],
        pushTokens: Array.isArray(payload.pushTokens) ? payload.pushTokens : [],
        voiceInvitations: Array.isArray(payload.voiceInvitations)
          ? payload.voiceInvitations
          : []
      },
      revision: Number(row?.revision ?? 0),
      updatedAt: row?.updated_at?.toISOString() ?? new Date(0).toISOString()
    };
  }

  async analyticsSummary(from: Date, to: Date): Promise<{
    total: number;
    errors: number;
    p95Milliseconds?: number;
    events: Array<{ name: string; count: number }>;
  }> {
    const result = await this.pool.query<{
      event_name: string;
      count: string;
      error_count: string;
      p95: string | null;
    }>(
      `SELECT event_name, COUNT(*)::text AS count,
              COUNT(*) FILTER (
                WHERE CASE
                        WHEN properties->>'statusCode' ~ '^[0-9]+$'
                          THEN (properties->>'statusCode')::int >= 500
                        ELSE FALSE
                      END
                   OR event_name LIKE '%.failed'
                   OR event_name LIKE '%.rejected'
              )::text AS error_count,
              percentile_cont(0.95) WITHIN GROUP (
                ORDER BY CASE
                  WHEN properties->>'durationMilliseconds'
                    ~ '^[0-9]+([.][0-9]+)?$'
                    THEN (properties->>'durationMilliseconds')::double precision
                  ELSE NULL
                END
              )::text AS p95
         FROM analytics_events
        WHERE occurred_at >= $1 AND occurred_at < $2
        GROUP BY event_name
        ORDER BY COUNT(*) DESC`,
      [from, to]
    );
    const total = result.rows.reduce((sum, row) => sum + Number(row.count), 0);
    const errors = result.rows.reduce((sum, row) => sum + Number(row.error_count), 0);
    const p95Values = result.rows.flatMap((row) => row.p95 ? [Number(row.p95)] : []);
    return {
      total,
      errors,
      p95Milliseconds: p95Values.length ? Math.max(...p95Values) : undefined,
      events: result.rows.map((row) => ({ name: row.event_name, count: Number(row.count) }))
    };
  }

  async analyticsEvents(from: Date, to: Date, limit = 100_000): Promise<AnalyticsEventSnapshot> {
    const safeLimit = Math.min(200_000, Math.max(1_000, Math.floor(limit)));
    const result = await this.pool.query<{
      event_name: string;
      occurred_at: Date;
      received_at: Date;
      user_key: string | null;
      session_id: string | null;
      app_version: string | null;
      build_number: string | null;
      platform: string;
      os_version: string | null;
      device_family: string | null;
      properties: Record<string, unknown>;
      first_seen_at: Date | null;
      total_count: string;
    }>(
      `WITH first_seen AS (
         SELECT user_key, MIN(occurred_at) AS first_seen_at
           FROM analytics_events
          WHERE user_key IS NOT NULL AND platform IN ('iOS', 'watchOS')
          GROUP BY user_key
       )
       SELECT e.event_name, e.occurred_at, e.received_at, e.user_key,
              e.session_id, e.app_version, e.build_number, e.platform,
              e.os_version, e.device_family, e.properties, f.first_seen_at,
              COUNT(*) OVER()::text AS total_count
         FROM analytics_events e
         LEFT JOIN first_seen f ON f.user_key = e.user_key
        WHERE e.occurred_at >= $1 AND e.occurred_at < $2
          AND e.event_name <> 'api.request_completed'
        ORDER BY e.occurred_at ASC
        LIMIT $3`,
      [from, to, safeLimit + 1]
    );
    const total = Number(result.rows[0]?.total_count ?? 0);
    const rows = result.rows.slice(0, safeLimit);
    const events: AnalyticsEventRecord[] = rows.map((row) => ({
      eventName: row.event_name,
      occurredAt: row.occurred_at.toISOString(),
      receivedAt: row.received_at.toISOString(),
      userKey: row.user_key ?? undefined,
      sessionId: row.session_id ?? undefined,
      appVersion: row.app_version ?? undefined,
      buildNumber: row.build_number ?? undefined,
      platform: row.platform,
      osVersion: row.os_version ?? undefined,
      deviceFamily: row.device_family ?? undefined,
      properties: row.properties ?? {},
      firstSeenAt: row.first_seen_at?.toISOString()
    }));
    return {
      events,
      total,
      truncated: total > safeLimit,
      latestReceivedAt: events.length
        ? events.reduce((latest, event) => event.receivedAt > latest ? event.receivedAt : latest, events[0].receivedAt)
        : undefined
    };
  }

  async analyticsFreshness(): Promise<AnalyticsFreshness> {
    const result = await this.pool.query<{
      latest_received_at: Date | null;
      latest_client_at: Date | null;
      latest_server_at: Date | null;
      latest_push_at: Date | null;
      latest_livekit_at: Date | null;
      total_events: string;
      client_events: string;
    }>(
      `SELECT MAX(received_at) AS latest_received_at,
              MAX(received_at) FILTER (WHERE platform IN ('iOS', 'watchOS')) AS latest_client_at,
              MAX(received_at) FILTER (WHERE platform = 'server') AS latest_server_at,
              MAX(received_at) FILTER (WHERE event_name LIKE 'push.%') AS latest_push_at,
              MAX(received_at) FILTER (WHERE event_name LIKE 'livekit.%') AS latest_livekit_at,
              COUNT(*)::text AS total_events,
              COUNT(*) FILTER (WHERE platform IN ('iOS', 'watchOS'))::text AS client_events
         FROM analytics_events`
    );
    const row = result.rows[0];
    return {
      latestReceivedAt: row?.latest_received_at?.toISOString(),
      latestClientAt: row?.latest_client_at?.toISOString(),
      latestServerAt: row?.latest_server_at?.toISOString(),
      latestPushAt: row?.latest_push_at?.toISOString(),
      latestLiveKitAt: row?.latest_livekit_at?.toISOString(),
      totalEvents: Number(row?.total_events ?? 0),
      clientEvents: Number(row?.client_events ?? 0)
    };
  }

  async auditLogs(limit = 100): Promise<Array<Record<string, unknown>>> {
    const result = await this.pool.query(
      `SELECT l.id, u.username, l.action, l.target_type AS "targetType",
              l.target_id AS "targetId", l.result, l.metadata,
              l.created_at AS "createdAt"
         FROM admin_audit_logs l
         LEFT JOIN admin_users u ON u.id = l.admin_id
        ORDER BY l.created_at DESC LIMIT $1`,
      [limit]
    );
    return result.rows;
  }
}
