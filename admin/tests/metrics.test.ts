import assert from "node:assert/strict";
import test from "node:test";

import { overviewMetrics, periodForDays, rideMetrics, socialMetrics } from "../src/metrics.js";
import type { BusinessSnapshot } from "../src/types.js";

const now = new Date("2026-08-25T12:00:00.000Z");
const snapshot: BusinessSnapshot = {
  revision: 12,
  updatedAt: "2026-08-25T11:55:00.000Z",
  state: {
    users: [
      { id: "u1", displayName: "骑手一", friendCode: "RIDE01", createdAt: "2026-08-25T08:00:00.000Z", updatedAt: "2026-08-25T11:00:00.000Z" },
      { id: "u2", displayName: "骑手二", friendCode: "RIDE02", appleSubject: "hidden", createdAt: "2026-08-20T08:00:00.000Z", updatedAt: "2026-08-24T11:00:00.000Z" }
    ],
    sessions: [{ userId: "u1", expiresAt: "2026-08-26T00:00:00.000Z" }],
    friendRequests: [{ id: "f1", fromUserId: "u1", toUserId: "u2", status: "accepted", createdAt: "2026-08-25T09:00:00.000Z", updatedAt: "2026-08-25T09:05:00.000Z" }],
    friendships: [{ userAId: "u1", userBId: "u2", createdAt: "2026-08-25T09:05:00.000Z" }],
    groups: [{ id: "g1", ownerId: "u1", memberIds: ["u1", "u2"], createdAt: "2026-08-25T09:10:00.000Z", updatedAt: "2026-08-25T09:10:00.000Z" }],
    rides: [
      {
        id: "r1", userId: "u1", title: "晨骑", source: "appleWatch",
        startedAt: "2026-08-25T10:00:00.000Z", endedAt: "2026-08-25T11:00:00.000Z",
        createdAt: "2026-08-25T11:01:00.000Z", updatedAt: "2026-08-25T11:01:00.000Z",
        points: [{ heartRateBeatsPerMinute: 128 }, {}], weather: { temperature: 25 },
        metrics: { distanceMeters: 20_000, movingDurationSeconds: 3_600, elapsedDurationSeconds: 3_700, averageHeartRate: 128 }
      },
      {
        id: "r2", userId: "u2", title: "误触", source: "iPhone",
        startedAt: "2026-08-25T10:00:00.000Z", endedAt: "2026-08-25T10:01:00.000Z",
        createdAt: "2026-08-25T10:01:00.000Z", updatedAt: "2026-08-25T10:01:00.000Z",
        metrics: { distanceMeters: 20, movingDurationSeconds: 20, elapsedDurationSeconds: 60 }
      }
    ],
    pushTokens: [{ userId: "u1", environment: "production", createdAt: "2026-08-25T08:00:00.000Z", updatedAt: "2026-08-25T08:00:00.000Z" }],
    voiceInvitations: [{ id: "v1", callerId: "u1", targetKind: "group", recipientIds: ["u2"], respondedRecipientIds: ["u2"], createdAt: "2026-08-25T10:30:00.000Z", expiresAt: "2026-08-25T11:30:00.000Z" }]
  }
};

test("overview excludes short accidental rides from effective ride KPIs", () => {
  const result = overviewMetrics(snapshot, periodForDays(7, now));

  assert.equal(result.kpis.totalUsers, 2);
  assert.equal(result.kpis.newUsers, 2);
  assert.equal(result.kpis.validRides, 1);
  assert.equal(result.kpis.totalDistanceKilometers, 20);
  assert.equal(result.kpis.watchRidePercent, 100);
  assert.equal(result.kpis.voiceResponsePercent, 100);
});

test("ride and social summaries preserve product metric definitions", () => {
  const period = periodForDays(7, now);
  const rides = rideMetrics(snapshot.state, period);
  const social = socialMetrics(snapshot.state, period);

  assert.equal(rides.totals.uploaded, 2);
  assert.equal(rides.totals.valid, 1);
  assert.equal(rides.coverage.trackPercent, 100);
  assert.equal(rides.coverage.weatherPercent, 100);
  assert.equal(social.friends.relationships, 1);
  assert.equal(social.groups.averageMembers, 2);
  assert.equal(social.voice.responsePercent, 100);
  assert.equal(social.push.production, 1);
});
