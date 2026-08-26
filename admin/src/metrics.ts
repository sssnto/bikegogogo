import type {
  AnalyticsEventRecord,
  AnalyticsFreshness,
  BusinessSnapshot,
  BusinessState,
  RideRecord,
  UserRecord
} from "./types.js";

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

const clientEvent = (event: AnalyticsEventRecord) =>
  event.platform === "iOS" || event.platform === "watchOS";

const eventFailed = (event: AnalyticsEventRecord) =>
  event.eventName.endsWith(".failed")
  || event.eventName.endsWith(".rejected")
  || event.properties.success === false
  || event.properties.result === "failure";

const propertyNumber = (event: AnalyticsEventRecord, name: string): number => {
  const value = event.properties[name];
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
};

const uniqueUsers = (events: AnalyticsEventRecord[]) =>
  new Set(events.flatMap((event) => event.userKey ? [event.userKey] : [])).size;

const dailyUniqueUsers = (period: Period, events: AnalyticsEventRecord[]) => {
  const usersByDay = new Map<string, Set<string>>();
  for (let index = 0; index < period.days; index += 1) {
    const day = new Date(period.from.getTime() + index * 86_400_000).toISOString().slice(0, 10);
    usersByDay.set(day, new Set());
  }
  for (const event of events) {
    if (!event.userKey || !inPeriod(event.occurredAt, period)) continue;
    const day = event.occurredAt.slice(0, 10);
    usersByDay.get(day)?.add(event.userKey);
  }
  return [...usersByDay].map(([date, users]) => ({ date, value: users.size }));
};

export const growthMetrics = (
  state: BusinessState,
  events: AnalyticsEventRecord[],
  period: Period,
  truncated = false
) => {
  const clients = events.filter((event) => clientEvent(event) && inPeriod(event.occurredAt, period));
  const newUsers = state.users.filter((user) => inPeriod(user.createdAt, period));
  const appleUsers = newUsers.filter((user) => Boolean(user.appleSubject));
  const namesFor = (names: string[]) => clients.filter((event) => names.includes(event.eventName));
  const funnelDefinitions = [
    ["打开 App", ["app.opened"]],
    ["建立账户", ["account.session_established", "account.guest_created", "account.apple_authenticated"]],
    ["授权定位", ["permission.location_authorized"]],
    ["连接 Watch", ["watch.connected"]],
    ["开始骑行", ["ride.started"]],
    ["完成骑行", ["ride.finished"]],
    ["云端保存", ["ride.cloud_sync_succeeded", "ride.cloud_saved"]]
  ] as const;
  const funnel = funnelDefinitions.map(([label, names]) => {
    const matching = namesFor([...names]);
    return { label, users: uniqueUsers(matching), events: matching.length };
  });
  return {
    period: { from: period.from.toISOString(), to: period.to.toISOString(), days: period.days },
    tracking: {
      available: clients.length > 0,
      clientEvents: clients.length,
      truncated,
      note: clients.length
        ? "漏斗按匿名用户标识去重，位置、健康和身份明细不会进入运营事件。"
        : "尚未收到新版客户端运营事件；注册数据仍来自业务数据库。"
    },
    acquisition: {
      totalUsers: state.users.length,
      newUsers: newUsers.length,
      guestUsers: newUsers.length - appleUsers.length,
      appleUsers: appleUsers.length,
      appleAccountPercent: percent(appleUsers.length, newUsers.length),
      activeUsers: uniqueUsers(clients)
    },
    funnel,
    series: {
      registrations: dailySeries(period, newUsers.map((user) => ({ at: user.createdAt }))),
      activeUsers: dailyUniqueUsers(period, clients)
    }
  };
};

const utcDay = (value: string) => Date.parse(`${value.slice(0, 10)}T00:00:00.000Z`);

export const retentionMetrics = (events: AnalyticsEventRecord[], period: Period) => {
  const clients = events.filter((event) => clientEvent(event) && event.userKey);
  const activityByUser = new Map<string, Set<number>>();
  const firstSeenByUser = new Map<string, string>();
  for (const event of clients) {
    const userKey = event.userKey!;
    if (event.firstSeenAt) firstSeenByUser.set(userKey, event.firstSeenAt);
    const days = activityByUser.get(userKey) ?? new Set<number>();
    days.add(utcDay(event.occurredAt));
    activityByUser.set(userKey, days);
  }
  const cohorts = [...firstSeenByUser].filter(([, firstSeenAt]) => inPeriod(firstSeenAt, period));
  const retentionFor = (offsetDays: number) => {
    const eligible = cohorts.filter(([, firstSeenAt]) =>
      utcDay(firstSeenAt) + offsetDays * 86_400_000 < period.to.getTime()
    );
    const retained = eligible.filter(([userKey, firstSeenAt]) =>
      activityByUser.get(userKey)?.has(utcDay(firstSeenAt) + offsetDays * 86_400_000)
    ).length;
    return { days: offsetDays, eligible: eligible.length, retained, percent: percent(retained, eligible.length) };
  };
  return {
    available: cohorts.length > 0,
    cohortUsers: cohorts.length,
    activityUsers: uniqueUsers(clients),
    retention: [retentionFor(1), retentionFor(7), retentionFor(30)],
    note: cohorts.length
      ? "留存以首次收到客户端事件的日期作为匿名用户首日，只统计已到观察日的用户。"
      : "客户端埋点开始累计后，才能计算 D1、D7 和 D30 留存。"
  };
};

export const voiceQualityMetrics = (
  state: BusinessState,
  events: AnalyticsEventRecord[],
  period: Period
) => {
  const invitations = state.voiceInvitations.filter((item) => inPeriod(item.createdAt, period));
  const responded = invitations.filter((item) => item.respondedRecipientIds.length > 0);
  const voiceEvents = events.filter((event) =>
    inPeriod(event.occurredAt, period)
    && (event.eventName.startsWith("voice.") || event.eventName.startsWith("livekit."))
  );
  const connected = voiceEvents.filter((event) =>
    event.eventName === "voice.room_connected"
    || event.eventName === "livekit.participant_joined"
  );
  const durations = voiceEvents
    .filter((event) => event.eventName === "voice.room_disconnected" || event.eventName === "livekit.participant_left")
    .map((event) => propertyNumber(event, "durationSeconds"))
    .filter((value) => value > 0);
  const failures = voiceEvents.filter(eventFailed);
  const trueConnectionAvailable = voiceEvents.some((event) => event.eventName.startsWith("livekit."))
    || connected.some((event) => event.eventName === "voice.room_connected");
  return {
    invitations: invitations.length,
    responded: responded.length,
    invitationResponsePercent: percent(responded.length, invitations.length),
    roomConnections: connected.length,
    connectionFailures: failures.length,
    connectionSuccessPercent: trueConnectionAvailable
      ? percent(connected.length, connected.length + failures.length)
      : undefined,
    averageDurationMinutes: durations.length
      ? round(durations.reduce((sum, value) => sum + value, 0) / durations.length / 60)
      : undefined,
    trueConnectionAvailable,
    eventDistribution: [...new Map(voiceEvents.map((event) => [event.eventName, 0]))].map(([name]) => ({
      name,
      count: voiceEvents.filter((event) => event.eventName === name).length
    })),
    note: trueConnectionAvailable
      ? "接通指标来自客户端房间状态或 LiveKit webhook。"
      : "目前只有邀请响应数据；配置 LiveKit webhook 后才可核验真实接通率与通话时长。"
  };
};

export const pushDeliveryMetrics = (
  state: BusinessState,
  events: AnalyticsEventRecord[],
  period: Period
) => {
  const pushEvents = events.filter((event) =>
    inPeriod(event.occurredAt, period) && event.eventName.startsWith("push.")
  );
  const submitted = pushEvents.reduce((sum, event) => sum + propertyNumber(event, "submittedCount"), 0);
  const failed = pushEvents.reduce((sum, event) => sum + propertyNumber(event, "failedCount"), 0);
  const invalid = pushEvents.reduce((sum, event) => sum + propertyNumber(event, "invalidCount"), 0);
  const byEvent = new Map<string, { submitted: number; failed: number }>();
  for (const event of pushEvents) {
    const name = String(event.properties.event ?? "unknown");
    const current = byEvent.get(name) ?? { submitted: 0, failed: 0 };
    current.submitted += propertyNumber(event, "submittedCount");
    current.failed += propertyNumber(event, "failedCount");
    byEvent.set(name, current);
  }
  return {
    devices: {
      total: state.pushTokens.length,
      production: state.pushTokens.filter((item) => item.environment === "production").length,
      sandbox: state.pushTokens.filter((item) => item.environment === "sandbox").length
    },
    delivery: {
      available: pushEvents.length > 0,
      attempts: pushEvents.length,
      submitted,
      accepted: Math.max(0, submitted - failed),
      failed,
      invalid,
      successPercent: submitted ? percent(Math.max(0, submitted - failed), submitted) : undefined
    },
    events: [...byEvent].map(([name, value]) => ({ name, ...value }))
  };
};

export const versionMetrics = (events: AnalyticsEventRecord[], period: Period) => {
  const clients = events.filter((event) => clientEvent(event) && inPeriod(event.occurredAt, period));
  const groups = new Map<string, AnalyticsEventRecord[]>();
  for (const event of clients) {
    const key = `${event.platform}|${event.appVersion ?? "未知"}|${event.buildNumber ?? "未知"}`;
    groups.set(key, [...(groups.get(key) ?? []), event]);
  }
  const versions = [...groups].map(([key, group]) => {
    const [platform, appVersion, buildNumber] = key.split("|");
    const errors = group.filter(eventFailed).length;
    return {
      platform,
      appVersion,
      buildNumber,
      users: uniqueUsers(group),
      events: group.length,
      errors,
      errorRatePercent: percent(errors, group.length)
    };
  }).sort((left, right) => right.users - left.users || right.events - left.events);
  return {
    available: clients.length > 0,
    totalClientEvents: clients.length,
    activeUsers: uniqueUsers(clients),
    versions,
    osVersions: [...new Set(clients.flatMap((event) => event.osVersion ? [event.osVersion] : []))].map((name) => ({
      name,
      users: uniqueUsers(clients.filter((event) => event.osVersion === name))
    })).sort((left, right) => right.users - left.users),
    devices: [...new Set(clients.flatMap((event) => event.deviceFamily ? [event.deviceFamily] : []))].map((name) => ({
      name,
      users: uniqueUsers(clients.filter((event) => event.deviceFamily === name))
    })).sort((left, right) => right.users - left.users)
  };
};

const freshnessState = (value: string | undefined, now: Date, staleHours: number) => {
  if (!value) return { state: "missing" as const, ageMinutes: undefined };
  const ageMinutes = Math.max(0, Math.round((now.getTime() - timestamp(value)) / 60_000));
  return {
    state: ageMinutes > staleHours * 60 ? "stale" as const : "fresh" as const,
    ageMinutes
  };
};

export const dataFreshnessMetrics = (
  businessUpdatedAt: string,
  analytics: AnalyticsFreshness,
  now = new Date()
) => ({
  generatedAt: now.toISOString(),
  sources: [
    { name: "业务数据库", updatedAt: businessUpdatedAt, ...freshnessState(businessUpdatedAt, now, 1) },
    { name: "服务端事件", updatedAt: analytics.latestServerAt, ...freshnessState(analytics.latestServerAt, now, 1) },
    { name: "iOS / watchOS 事件", updatedAt: analytics.latestClientAt, ...freshnessState(analytics.latestClientAt, now, 24) },
    { name: "APNs 推送回执", updatedAt: analytics.latestPushAt, ...freshnessState(analytics.latestPushAt, now, 72) },
    { name: "LiveKit webhook", updatedAt: analytics.latestLiveKitAt, ...freshnessState(analytics.latestLiveKitAt, now, 24) },
    { name: "App Store Connect", updatedAt: undefined, ...freshnessState(undefined, now, 24) }
  ],
  counts: { totalEvents: analytics.totalEvents, clientEvents: analytics.clientEvents }
});

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
