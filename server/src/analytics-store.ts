import { createHmac, randomUUID } from "node:crypto";
import { Pool } from "pg";

export type AnalyticsEventInput = {
  eventId: string;
  eventName: string;
  occurredAt: string;
  sessionId?: string;
  appVersion?: string;
  buildNumber?: string;
  platform: "iOS" | "watchOS" | "server";
  osVersion?: string;
  deviceFamily?: string;
  properties: Record<string, string | number | boolean | null>;
};

export class AnalyticsStore {
  private pool?: Pool;

  constructor(
    private readonly databaseUrl?: string,
    private readonly hmacSecret = "development-analytics-secret"
  ) {}

  async initialize(): Promise<void> {
    if (!this.databaseUrl) return;
    this.pool = new Pool({ connectionString: this.databaseUrl, max: 4 });
    await this.pool.query(`
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
  }

  async close(): Promise<void> {
    await this.pool?.end();
  }

  userKey(userId: string): string {
    return createHmac("sha256", this.hmacSecret).update(userId).digest("hex");
  }

  async record(event: Omit<AnalyticsEventInput, "eventId"> & { eventId?: string }, userId?: string): Promise<void> {
    if (!this.pool) return;
    await this.pool.query(
      `INSERT INTO analytics_events (
         event_id, event_name, occurred_at, user_key, session_id, app_version,
         build_number, platform, os_version, device_family, properties
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
       ON CONFLICT (event_id) DO NOTHING`,
      [
        event.eventId ?? randomUUID(),
        event.eventName,
        event.occurredAt,
        userId ? this.userKey(userId) : null,
        event.sessionId ?? null,
        event.appVersion ?? null,
        event.buildNumber ?? null,
        event.platform,
        event.osVersion ?? null,
        event.deviceFamily ?? null,
        JSON.stringify(event.properties)
      ]
    );
  }

  async recordBatch(events: AnalyticsEventInput[], userId: string): Promise<void> {
    for (const event of events) await this.record(event, userId);
  }
}
