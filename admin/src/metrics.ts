import type { BusinessSnapshot, BusinessState, RideRecord, UserRecord } from "./types.js";

export type Period = { from: Date; to: Date; days: number };

const timestamp = (value?: string): number => value ? new Date(value).getTime() : 0;
const inPeriod = (value: string | undefined, period: Period) => {
  const time = timestamp(value);
  return time >= period.from.getTime() && time < period.to.getTime();
};
const round = (value: number, digits = 1) => Number(value.toFixed(digits));
const percent = (value: number, total: number) => total ? round(value / total * 100) : 0;

export const periodForDays = (days: number, now = new Date()): Period => {
  const safeDays = Math.min(90, Math.max(1, Math.floor(days)));
  const to = new Date(now);
  const from = new Date(to.getTime() - safeDays * 24 * 60 * 60 * 1000);
  return { from, to, days: safeDays };
};

const validRide = (ride: RideRecord) =>
  ride.metrics.distanceMeters >= 500 || ride.metrics.movingDurationSeconds >= 600;

const latestActivityByUser = (state: BusinessState): Map<string, number> => {
  const result = new Map<string, number>();
  const update = (userId: string, value?: string) => {
    const time = timestamp(value);
    if (time > (result.get(userId) ?? 0)) result.set(userId, time);
  };
  for (const user of state.users) update(user.id, user.updatedAt);
  for (const ride of state.rides) update(ride.userId, ride.updatedAt || ride.startedAt);
  for (const request of state.friendRequests) {
    update(request.fromUserId, request.updatedAt);
    update(request.toUserId, request.updatedAt);
  }
  for (const group of state.groups) {
    for (const memberId of group.memberIds) update(memberId, group.updatedAt);
  }
  for (const invitation of state.voiceInvitations) {
    update(invitation.callerId, invitation.createdAt);
    for (const recipientId of invitation.recipientIds) update(recipientId, invitation.createdAt);
  }
  return result;
};

const dailySeries = (
  period: Period,
  values: Array<{ at: string; value?: number }>
) => {
  const buckets = new Map<string, number>();
  for (let index = 0; index < period.days; index += 1) {
    const day = new Date(period.from.getTime() + index * 86_400_000)
      .toISOString().slice(0, 10);
    buckets.set(day, 0);
  }
  for (const item of values) {
    if (!inPeriod(item.at, period)) continue;
    const day = new Date(item.at).toISOString().slice(0, 10);
    buckets.set(day, (buckets.get(day) ?? 0) + (item.value ?? 1));
  }
  return [...buckets].map(([date, value]) => ({ date, value: round(value, 2) }));
};

export const overviewMetrics = (snapshot: BusinessSnapshot, period: Period) => {
  const { state } = snapshot;
  const rides = state.rides.filter((ride) => inPeriod(ride.startedAt, period));
  const validRides = rides.filter(validRide);
  const newUsers = state.users.filter((user) => inPeriod(user.createdAt, period));
  const activity = latestActivityByUser(state);
  const activeSince = (days: number) => {
    const threshold = period.to.getTime() - days * 86_400_000;
    return [...activity.values()].filter((value) => value >= threshold && value < period.to.getTime()).length;
  };
  const invitations = state.voiceInvitations.filter((item) => inPeriod(item.createdAt, period));
  const connectedInvitations = invitations.filter((item) => item.respondedRecipientIds.length > 0);
  const totalDistanceMeters = validRides.reduce((sum, ride) => sum + ride.metrics.distanceMeters, 0);
  const totalDurationSeconds = validRides.reduce(
    (sum, ride) => sum + ride.metrics.movingDurationSeconds,
    0
  );
  const watchRides = validRides.filter((ride) => ride.source !== "iPhone").length;
  const heartRateRides = validRides.filter((ride) =>
    ride.metrics.averageHeartRate !== undefined
    || ride.points?.some((point) => point.heartRateBeatsPerMinute !== undefined)
  ).length;

  return {
    period: {
      from: period.from.toISOString(),
      to: period.to.toISOString(),
      days: period.days
    },
    freshness: {
      businessStateUpdatedAt: snapshot.updatedAt,
      revision: snapshot.revision
    },
    kpis: {
      totalUsers: state.users.length,
      newUsers: newUsers.length,
      dau: activeSince(1),
      wau: activeSince(7),
      mau: activeSince(30),
      validRides: validRides.length,
      totalDistanceKilometers: round(totalDistanceMeters / 1000),
      totalMovingHours: round(totalDurationSeconds / 3600),
      watchRidePercent: percent(watchRides, validRides.length),
      heartRateCoveragePercent: percent(heartRateRides, validRides.length),
      voiceInvitations: invitations.length,
      voiceResponsePercent: percent(connectedInvitations.length, invitations.length)
    },
    series: {
      registrations: dailySeries(period, state.users.map((user) => ({ at: user.createdAt }))),
      rides: dailySeries(period, validRides.map((ride) => ({ at: ride.startedAt }))),
      distanceKilometers: dailySeries(period, validRides.map((ride) => ({
        at: ride.startedAt,
        value: ride.metrics.distanceMeters / 1000
      })))
    }
  };
};

export const rideMetrics = (state: BusinessState, period: Period) => {
  const rides = state.rides.filter((ride) => inPeriod(ride.startedAt, period));
  const valid = rides.filter(validRide);
  const totalDistance = valid.reduce((sum, ride) => sum + ride.metrics.distanceMeters, 0);
  const totalDuration = valid.reduce((sum, ride) => sum + ride.metrics.movingDurationSeconds, 0);
  const source = (name: RideRecord["source"]) => valid.filter((ride) => ride.source === name).length;
  const buckets = [
    { label: "< 1 km", count: valid.filter((ride) => ride.metrics.distanceMeters < 1_000).length },
    { label: "1-10 km", count: valid.filter((ride) => ride.metrics.distanceMeters >= 1_000 && ride.metrics.distanceMeters < 10_000).length },
    { label: "10-30 km", count: valid.filter((ride) => ride.metrics.distanceMeters >= 10_000 && ride.metrics.distanceMeters < 30_000).length },
    { label: "30-60 km", count: valid.filter((ride) => ride.metrics.distanceMeters >= 30_000 && ride.metrics.distanceMeters < 60_000).length },
    { label: "> 60 km", count: valid.filter((ride) => ride.metrics.distanceMeters >= 60_000).length }
  ];
  return {
    totals: {
      uploaded: rides.length,
      valid: valid.length,
      totalDistanceKilometers: round(totalDistance / 1000),
      totalMovingHours: round(totalDuration / 3600),
      averageDistanceKilometers: valid.length ? round(totalDistance / valid.length / 1000) : 0,
      averageMovingMinutes: valid.length ? round(totalDuration / valid.length / 60) : 0
    },
    coverage: {
      trackPercent: percent(valid.filter((ride) => (ride.points?.length ?? 0) > 1).length, valid.length),
      heartRatePercent: percent(valid.filter((ride) => ride.metrics.averageHeartRate !== undefined).length, valid.length),
      weatherPercent: percent(valid.filter((ride) => ride.weather !== undefined).length, valid.length)
    },
    sources: [
      { label: "iPhone", count: source("iPhone") },
      { label: "Apple Watch", count: source("appleWatch") },
      { label: "合并记录", count: source("merged") }
    ],
    distanceBuckets: buckets,
    series: dailySeries(period, valid.map((ride) => ({ at: ride.startedAt })))
  };
};

export const socialMetrics = (state: BusinessState, period: Period) => {
  const requests = state.friendRequests.filter((item) => inPeriod(item.createdAt, period));
  const groups = state.groups.filter((item) => inPeriod(item.createdAt, period));
  const invitations = state.voiceInvitations.filter((item) => inPeriod(item.createdAt, period));
  return {
    friends: {
      relationships: state.friendships.length,
      sent: requests.length,
      accepted: requests.filter((item) => item.status === "accepted").length,
      rejected: requests.filter((item) => item.status === "rejected").length,
      pending: requests.filter((item) => item.status === "pending").length
    },
    groups: {
      total: state.groups.length,
      created: groups.length,
      averageMembers: state.groups.length
        ? round(state.groups.reduce((sum, group) => sum + group.memberIds.length, 0) / state.groups.length)
        : 0
    },
    voice: {
      invitations: invitations.length,
      friendInvitations: invitations.filter((item) => item.targetKind === "friend").length,
      groupInvitations: invitations.filter((item) => item.targetKind === "group").length,
      responded: invitations.filter((item) => item.respondedRecipientIds.length > 0).length,
      cancelled: invitations.filter((item) => item.cancelledAt).length,
      responsePercent: percent(
        invitations.filter((item) => item.respondedRecipientIds.length > 0).length,
        invitations.length
      )
    },
    push: {
      totalTokens: state.pushTokens.length,
      production: state.pushTokens.filter((item) => item.environment === "production").length,
      sandbox: state.pushTokens.filter((item) => item.environment === "sandbox").length
    }
  };
};

const publicUserSummary = (state: BusinessState, user: UserRecord) => {
  const rides = state.rides.filter((ride) => ride.userId === user.id);
  return {
    id: user.id,
    displayName: user.displayName,
    friendCode: user.friendCode,
    authProvider: user.appleSubject ? "apple" : "guest",
    createdAt: user.createdAt,
    updatedAt: user.updatedAt,
    rideCount: rides.length,
    totalDistanceKilometers: round(
      rides.reduce((sum, ride) => sum + ride.metrics.distanceMeters, 0) / 1000
    ),
    friendCount: state.friendships.filter((friendship) =>
      friendship.userAId === user.id || friendship.userBId === user.id
    ).length,
    groupCount: state.groups.filter((group) => group.memberIds.includes(user.id)).length,
    activeSessionCount: state.sessions.filter((session) =>
      session.userId === user.id && timestamp(session.expiresAt) > Date.now()
    ).length
  };
};

export const searchUsers = (
  state: BusinessState,
  query: string,
  page: number,
  pageSize: number
) => {
  const normalized = query.trim().toLocaleLowerCase();
  const matches = state.users.filter((user) => !normalized
    || user.id.toLocaleLowerCase().includes(normalized)
    || user.friendCode.toLocaleLowerCase().includes(normalized)
    || user.displayName.toLocaleLowerCase().includes(normalized));
  const start = (page - 1) * pageSize;
  return {
    page,
    pageSize,
    total: matches.length,
    users: matches.slice(start, start + pageSize).map((user) => publicUserSummary(state, user))
  };
};

export const userSummary = (state: BusinessState, userId: string) => {
  const user = state.users.find((candidate) => candidate.id === userId);
  return user ? publicUserSummary(state, user) : undefined;
};
