import { createHash, randomBytes, randomUUID } from "node:crypto";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";

export type UserRecord = {
  id: string;
  deviceIdHashes: string[];
  appleSubject?: string;
  email?: string;
  displayName: string;
  friendCode: string;
  createdAt: string;
  updatedAt: string;
};

export type FriendRequestStatus = "pending" | "accepted" | "rejected";

export type FriendRequestRecord = {
  id: string;
  fromUserId: string;
  toUserId: string;
  status: FriendRequestStatus;
  createdAt: string;
  updatedAt: string;
};

type SessionRecord = {
  tokenHash: string;
  userId: string;
  createdAt: string;
  expiresAt: string;
};

type FriendshipRecord = {
  userAId: string;
  userBId: string;
  createdAt: string;
};

export type GroupRecord = {
  id: string;
  name: string;
  ownerId: string;
  memberIds: string[];
  createdAt: string;
  updatedAt: string;
};

export type RidePointRecord = {
  latitude: number;
  longitude: number;
  elevationMeters?: number;
  speedMetersPerSecond?: number;
  courseDegrees?: number;
  horizontalAccuracyMeters?: number;
  heartRateBeatsPerMinute?: number;
  cadenceRPM?: number;
  timestamp: string;
};

export type RideMetricsRecord = {
  distanceMeters: number;
  movingDurationSeconds: number;
  elapsedDurationSeconds: number;
  averageSpeedMetersPerSecond: number;
  maxSpeedMetersPerSecond: number;
  elevationGainMeters: number;
  averageHeartRate?: number;
  maxHeartRate?: number;
};

export type RideRecord = {
  id: string;
  userId: string;
  title: string;
  state: "finished";
  source: "iPhone" | "appleWatch" | "merged";
  startedAt: string;
  endedAt?: string;
  points: RidePointRecord[];
  metrics: RideMetricsRecord;
  createdAt: string;
  updatedAt: string;
};

export type PushTokenRecord = {
  token: string;
  userId: string;
  environment: "sandbox" | "production";
  createdAt: string;
  updatedAt: string;
};

type DatabaseState = {
  version: 4;
  users: UserRecord[];
  sessions: SessionRecord[];
  friendRequests: FriendRequestRecord[];
  friendships: FriendshipRecord[];
  groups: GroupRecord[];
  rides: RideRecord[];
  pushTokens: PushTokenRecord[];
};

const emptyState = (): DatabaseState => ({
  version: 4,
  users: [],
  sessions: [],
  friendRequests: [],
  friendships: [],
  groups: [],
  rides: [],
  pushTokens: []
});

const hash = (value: string) => createHash("sha256").update(value).digest("hex");

const normalizePair = (firstUserId: string, secondUserId: string) =>
  [firstUserId, secondUserId].sort() as [string, string];

export class StoreError extends Error {
  constructor(
    public readonly code: string,
    public readonly statusCode: number,
    message: string
  ) {
    super(message);
  }
}

export class DataStore {
  private state: DatabaseState = emptyState();
  private mutationQueue: Promise<void> = Promise.resolve();

  constructor(
    private readonly filePath: string,
    private readonly sessionTTLMilliseconds = 30 * 24 * 60 * 60 * 1000
  ) {}

  async initialize(): Promise<void> {
    try {
      const data = await readFile(this.filePath, "utf8");
      this.state = this.migrate(JSON.parse(data) as Record<string, unknown>);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") {
        throw error;
      }
      await this.persist();
    }
  }

  async signInGuest(
    deviceId: string,
    suggestedDisplayName: string
  ): Promise<{ accessToken: string; user: UserRecord }> {
    return this.mutate(async () => {
      const deviceIdHash = hash(deviceId);
      let user = this.state.users.find((candidate) =>
        candidate.deviceIdHashes.includes(deviceIdHash)
      );

      if (!user) {
        const now = new Date().toISOString();
        user = {
          id: `usr_${randomUUID()}`,
          deviceIdHashes: [deviceIdHash],
          displayName: suggestedDisplayName,
          friendCode: this.generateFriendCode(),
          createdAt: now,
          updatedAt: now
        };
        this.state.users.push(user);
      } else if (user.appleSubject) {
        throw new StoreError(
          "apple_sign_in_required",
          409,
          "This account requires Sign in with Apple"
        );
      }

      return { accessToken: this.createSession(user.id), user };
    });
  }

  async signInWithApple(input: {
    subject: string;
    email?: string;
    displayName?: string;
    deviceId: string;
    currentUserId?: string;
  }): Promise<{ accessToken: string; user: UserRecord }> {
    return this.mutate(async () => {
      const deviceIdHash = hash(input.deviceId);
      const currentUser = input.currentUserId
        ? this.userById(input.currentUserId)
        : undefined;
      let user = this.state.users.find(
        (candidate) => candidate.appleSubject === input.subject
      );

      if (currentUser?.appleSubject && currentUser.appleSubject !== input.subject) {
        throw new StoreError(
          "apple_account_mismatch",
          409,
          "The current account is already linked to another Apple account"
        );
      }

      if (user && currentUser && user.id !== currentUser.id) {
        user = this.mergeUsers(user, currentUser);
      } else if (!user && currentUser) {
        user = currentUser;
      } else if (!user) {
        const deviceUser = this.state.users.find((candidate) =>
          candidate.deviceIdHashes.includes(deviceIdHash) && !candidate.appleSubject
        );
        user = deviceUser ?? this.createUser(input.displayName ?? "骑行好友");
      }

      user.appleSubject = input.subject;
      if (input.email) user.email = input.email;
      if (input.displayName && !currentUser) user.displayName = input.displayName;
      if (!user.deviceIdHashes.includes(deviceIdHash)) {
        user.deviceIdHashes.push(deviceIdHash);
      }
      user.updatedAt = new Date().toISOString();

      return { accessToken: this.createSession(user.id), user };
    });
  }

  userForAccessToken(accessToken: string): UserRecord | undefined {
    const session = this.state.sessions.find(
      (candidate) =>
        candidate.tokenHash === hash(accessToken)
        && new Date(candidate.expiresAt).getTime() > Date.now()
    );
    return session
      ? this.state.users.find((candidate) => candidate.id === session.userId)
      : undefined;
  }

  async revokeSession(accessToken: string): Promise<void> {
    await this.mutate(async () => {
      const tokenHash = hash(accessToken);
      this.state.sessions = this.state.sessions.filter(
        (session) => session.tokenHash !== tokenHash
      );
    });
  }

  userById(userId: string): UserRecord | undefined {
    return this.state.users.find((candidate) => candidate.id === userId);
  }

  async updateProfile(userId: string, displayName: string): Promise<UserRecord> {
    return this.mutate(async () => {
      const user = this.requireUser(userId);
      user.displayName = displayName;
      user.updatedAt = new Date().toISOString();
      return user;
    });
  }

  async registerPushToken(
    userId: string,
    token: string,
    environment: PushTokenRecord["environment"]
  ): Promise<void> {
    await this.mutate(async () => {
      this.requireUser(userId);
      const now = new Date().toISOString();
      const existing = this.state.pushTokens.find(
        (record) => record.token === token && record.environment === environment
      );

      if (existing) {
        existing.userId = userId;
        existing.updatedAt = now;
        return;
      }

      this.state.pushTokens.push({
        token,
        userId,
        environment,
        createdAt: now,
        updatedAt: now
      });
    });
  }

  async removePushToken(
    userId: string,
    token: string,
    environment?: PushTokenRecord["environment"]
  ): Promise<void> {
    await this.mutate(async () => {
      this.state.pushTokens = this.state.pushTokens.filter(
        (record) =>
          record.userId !== userId
          || record.token !== token
          || (environment !== undefined && record.environment !== environment)
      );
    });
  }

  async removePushTokens(
    tokens: string[],
    environment: PushTokenRecord["environment"]
  ): Promise<void> {
    if (tokens.length === 0) return;
    const invalidTokens = new Set(tokens);
    await this.mutate(async () => {
      this.state.pushTokens = this.state.pushTokens.filter(
        (record) =>
          record.environment !== environment || !invalidTokens.has(record.token)
      );
    });
  }

  pushTokensFor(
    userId: string,
    environment: PushTokenRecord["environment"]
  ): string[] {
    return this.state.pushTokens
      .filter(
        (record) =>
          record.userId === userId && record.environment === environment
      )
      .map((record) => record.token);
  }

  friendsFor(userId: string): UserRecord[] {
    const friendIds = this.state.friendships.flatMap((friendship) => {
      if (friendship.userAId === userId) return [friendship.userBId];
      if (friendship.userBId === userId) return [friendship.userAId];
      return [];
    });

    return friendIds
      .map((friendId) => this.userById(friendId))
      .filter((user): user is UserRecord => Boolean(user))
      .sort((first, second) => first.displayName.localeCompare(second.displayName));
  }

  friendRequestsFor(userId: string): {
    incoming: FriendRequestRecord[];
    outgoing: FriendRequestRecord[];
  } {
    const pending = this.state.friendRequests.filter(
      (request) => request.status === "pending"
    );
    return {
      incoming: pending.filter((request) => request.toUserId === userId),
      outgoing: pending.filter((request) => request.fromUserId === userId)
    };
  }

  async createFriendRequest(
    fromUserId: string,
    friendCode: string
  ): Promise<FriendRequestRecord> {
    return this.mutate(async () => {
      const target = this.state.users.find(
        (user) => user.friendCode === friendCode.toUpperCase()
      );
      if (!target) {
        throw new StoreError("friend_code_not_found", 404, "Friend code not found");
      }
      if (target.id === fromUserId) {
        throw new StoreError("cannot_add_self", 409, "Cannot add yourself");
      }
      if (this.areFriends(fromUserId, target.id)) {
        throw new StoreError("already_friends", 409, "Users are already friends");
      }

      const reverseRequest = this.state.friendRequests.find(
        (request) =>
          request.status === "pending"
          && request.fromUserId === target.id
          && request.toUserId === fromUserId
      );
      if (reverseRequest) {
        return this.acceptRequest(reverseRequest, fromUserId);
      }

      const existing = this.state.friendRequests.find(
        (request) =>
          request.status === "pending"
          && request.fromUserId === fromUserId
          && request.toUserId === target.id
      );
      if (existing) return existing;

      const now = new Date().toISOString();
      const request: FriendRequestRecord = {
        id: `frq_${randomUUID()}`,
        fromUserId,
        toUserId: target.id,
        status: "pending",
        createdAt: now,
        updatedAt: now
      };
      this.state.friendRequests.push(request);
      return request;
    });
  }

  async respondToFriendRequest(
    requestId: string,
    userId: string,
    action: "accept" | "reject"
  ): Promise<FriendRequestRecord> {
    return this.mutate(async () => {
      const request = this.state.friendRequests.find(
        (candidate) => candidate.id === requestId
      );
      if (!request || request.toUserId !== userId) {
        throw new StoreError("request_not_found", 404, "Friend request not found");
      }
      if (request.status !== "pending") {
        throw new StoreError("request_already_resolved", 409, "Request already resolved");
      }

      if (action === "accept") {
        return this.acceptRequest(request, userId);
      }

      request.status = "rejected";
      request.updatedAt = new Date().toISOString();
      return request;
    });
  }

  private acceptRequest(
    request: FriendRequestRecord,
    userId: string
  ): FriendRequestRecord {
    if (request.toUserId !== userId) {
      throw new StoreError("request_not_found", 404, "Friend request not found");
    }
    request.status = "accepted";
    request.updatedAt = new Date().toISOString();

    const [userAId, userBId] = normalizePair(request.fromUserId, request.toUserId);
    if (!this.areFriends(userAId, userBId)) {
      this.state.friendships.push({
        userAId,
        userBId,
        createdAt: new Date().toISOString()
      });
    }
    return request;
  }

  areFriends(firstUserId: string, secondUserId: string): boolean {
    const [userAId, userBId] = normalizePair(firstUserId, secondUserId);
    return this.state.friendships.some(
      (friendship) =>
        friendship.userAId === userAId && friendship.userBId === userBId
    );
  }

  groupsFor(userId: string): GroupRecord[] {
    return this.state.groups
      .filter((group) => group.memberIds.includes(userId))
      .sort((first, second) => second.updatedAt.localeCompare(first.updatedAt));
  }

  groupById(groupId: string): GroupRecord | undefined {
    return this.state.groups.find((group) => group.id === groupId);
  }

  async createGroup(ownerId: string, name: string): Promise<GroupRecord> {
    return this.mutate(async () => {
      this.requireUser(ownerId);
      const now = new Date().toISOString();
      const group: GroupRecord = {
        id: `grp_${randomUUID()}`,
        name,
        ownerId,
        memberIds: [ownerId],
        createdAt: now,
        updatedAt: now
      };
      this.state.groups.push(group);
      return group;
    });
  }

  async addGroupMember(
    groupId: string,
    requestingUserId: string,
    memberId: string
  ): Promise<GroupRecord> {
    return this.mutate(async () => {
      const group = this.requireGroup(groupId);
      if (group.ownerId !== requestingUserId) {
        throw new StoreError("group_owner_required", 403, "Only the group owner can add members");
      }
      this.requireUser(memberId);
      if (!this.areFriends(requestingUserId, memberId)) {
        throw new StoreError("group_member_must_be_friend", 403, "Group members must be friends");
      }
      if (group.memberIds.length >= 20 && !group.memberIds.includes(memberId)) {
        throw new StoreError("group_member_limit", 409, "Group member limit reached");
      }
      if (!group.memberIds.includes(memberId)) {
        group.memberIds.push(memberId);
        group.updatedAt = new Date().toISOString();
      }
      return group;
    });
  }

  async removeGroupMember(
    groupId: string,
    requestingUserId: string,
    memberId: string
  ): Promise<GroupRecord> {
    return this.mutate(async () => {
      const group = this.requireGroup(groupId);
      const isSelf = requestingUserId === memberId;
      if (group.ownerId !== requestingUserId && !isSelf) {
        throw new StoreError("group_owner_required", 403, "Only the group owner can remove members");
      }
      if (memberId === group.ownerId) {
        throw new StoreError("group_owner_cannot_leave", 409, "The owner must delete the group");
      }
      if (!group.memberIds.includes(requestingUserId)) {
        throw new StoreError("group_membership_required", 403, "Group membership required");
      }
      group.memberIds = group.memberIds.filter((candidate) => candidate !== memberId);
      group.updatedAt = new Date().toISOString();
      return group;
    });
  }

  async deleteGroup(groupId: string, requestingUserId: string): Promise<void> {
    await this.mutate(async () => {
      const group = this.requireGroup(groupId);
      if (group.ownerId !== requestingUserId) {
        throw new StoreError("group_owner_required", 403, "Only the group owner can delete the group");
      }
      this.state.groups = this.state.groups.filter((candidate) => candidate.id !== groupId);
    });
  }

  async upsertRide(
    userId: string,
    ride: Omit<RideRecord, "userId" | "createdAt" | "updatedAt">
  ): Promise<RideRecord> {
    return this.mutate(async () => {
      this.requireUser(userId);
      const existing = this.state.rides.find((candidate) => candidate.id === ride.id);
      if (existing && existing.userId !== userId) {
        throw new StoreError("ride_id_conflict", 409, "Ride ID belongs to another account");
      }
      const now = new Date().toISOString();
      if (existing) {
        Object.assign(existing, ride, { updatedAt: now });
        return existing;
      }
      const record: RideRecord = {
        ...ride,
        userId,
        createdAt: now,
        updatedAt: now
      };
      this.state.rides.push(record);
      return record;
    });
  }

  ridesFor(userId: string): RideRecord[] {
    return this.state.rides
      .filter((ride) => ride.userId === userId)
      .sort((first, second) => second.startedAt.localeCompare(first.startedAt))
      .slice(0, 200);
  }

  rideFor(userId: string, rideId: string): RideRecord | undefined {
    return this.state.rides.find(
      (ride) => ride.userId === userId && ride.id === rideId
    );
  }

  async deleteRide(userId: string, rideId: string): Promise<void> {
    await this.mutate(async () => {
      if (!this.rideFor(userId, rideId)) {
        throw new StoreError("ride_not_found", 404, "Ride not found");
      }
      this.state.rides = this.state.rides.filter(
        (ride) => ride.userId !== userId || ride.id !== rideId
      );
    });
  }

  private requireUser(userId: string): UserRecord {
    const user = this.userById(userId);
    if (!user) {
      throw new StoreError("user_not_found", 404, "User not found");
    }
    return user;
  }

  private requireGroup(groupId: string): GroupRecord {
    const group = this.groupById(groupId);
    if (!group) {
      throw new StoreError("group_not_found", 404, "Group not found");
    }
    return group;
  }

  private createUser(displayName: string): UserRecord {
    const now = new Date().toISOString();
    const user: UserRecord = {
      id: `usr_${randomUUID()}`,
      deviceIdHashes: [],
      displayName,
      friendCode: this.generateFriendCode(),
      createdAt: now,
      updatedAt: now
    };
    this.state.users.push(user);
    return user;
  }

  private createSession(userId: string): string {
    const now = new Date();
    const accessToken = randomBytes(32).toString("base64url");
    const activeSessions = this.state.sessions.filter(
      (session) => new Date(session.expiresAt).getTime() > now.getTime()
    );
    this.state.sessions = activeSessions
      .filter((session) => session.userId !== userId)
      .concat(activeSessions
        .filter((session) => session.userId === userId)
        .sort((first, second) => second.createdAt.localeCompare(first.createdAt))
        .slice(0, 9));
    this.state.sessions.push({
      tokenHash: hash(accessToken),
      userId,
      createdAt: now.toISOString(),
      expiresAt: new Date(now.getTime() + this.sessionTTLMilliseconds).toISOString()
    });
    return accessToken;
  }

  private mergeUsers(target: UserRecord, source: UserRecord): UserRecord {
    target.deviceIdHashes = Array.from(
      new Set([...target.deviceIdHashes, ...source.deviceIdHashes])
    );
    this.state.friendships = this.state.friendships
      .map((friendship) => {
        const [userAId, userBId] = normalizePair(
          friendship.userAId === source.id ? target.id : friendship.userAId,
          friendship.userBId === source.id ? target.id : friendship.userBId
        );
        return { ...friendship, userAId, userBId };
      })
      .filter((friendship, index, friendships) =>
        friendship.userAId !== friendship.userBId
        && friendships.findIndex(
          (candidate) =>
            candidate.userAId === friendship.userAId
            && candidate.userBId === friendship.userBId
        ) === index
      );
    this.state.friendRequests = this.state.friendRequests
      .map((request) => ({
        ...request,
        fromUserId: request.fromUserId === source.id ? target.id : request.fromUserId,
        toUserId: request.toUserId === source.id ? target.id : request.toUserId
      }))
      .filter((request) => request.fromUserId !== request.toUserId);
    this.state.sessions = this.state.sessions.filter(
      (session) => session.userId !== source.id
    );
    this.state.groups = this.state.groups.map((group) => ({
      ...group,
      ownerId: group.ownerId === source.id ? target.id : group.ownerId,
      memberIds: Array.from(new Set(group.memberIds.map(
        (memberId) => memberId === source.id ? target.id : memberId
      )))
    }));
    this.state.rides = this.state.rides.map((ride) => (
      ride.userId === source.id ? { ...ride, userId: target.id } : ride
    ));
    this.state.pushTokens = this.state.pushTokens
      .map((record) => (
        record.userId === source.id ? { ...record, userId: target.id } : record
      ))
      .filter((record, index, records) =>
        records.findIndex(
          (candidate) =>
            candidate.token === record.token
            && candidate.environment === record.environment
        ) === index
      );
    this.state.users = this.state.users.filter((user) => user.id !== source.id);
    return target;
  }

  private migrate(raw: Record<string, unknown>): DatabaseState {
    const legacy = raw as unknown as {
      users?: Array<UserRecord & { deviceIdHash?: string }>;
      sessions?: Array<Omit<SessionRecord, "expiresAt"> & { expiresAt?: string }>;
      friendRequests?: FriendRequestRecord[];
      friendships?: FriendshipRecord[];
      groups?: GroupRecord[];
      rides?: RideRecord[];
      pushTokens?: PushTokenRecord[];
    };
    const now = Date.now();
    return {
      version: 4,
      users: (legacy.users ?? []).map((user) => {
        const { deviceIdHash, ...currentUser } = user;
        return {
          ...currentUser,
          deviceIdHashes: user.deviceIdHashes
            ?? (deviceIdHash ? [deviceIdHash] : [])
        };
      }),
      sessions: (legacy.sessions ?? []).map((session) => ({
        ...session,
        expiresAt: session.expiresAt
          ?? new Date(now + this.sessionTTLMilliseconds).toISOString()
      })),
      friendRequests: legacy.friendRequests ?? [],
      friendships: legacy.friendships ?? [],
      groups: legacy.groups ?? [],
      rides: legacy.rides ?? [],
      pushTokens: legacy.pushTokens ?? []
    };
  }

  private generateFriendCode(): string {
    const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    for (;;) {
      const code = Array.from(
        randomBytes(8),
        (byte) => alphabet[byte % alphabet.length]
      ).join("");
      if (!this.state.users.some((user) => user.friendCode === code)) {
        return code;
      }
    }
  }

  private async mutate<T>(operation: () => Promise<T>): Promise<T> {
    const previousMutation = this.mutationQueue;
    let releaseMutation: () => void = () => {};
    this.mutationQueue = new Promise<void>((resolve) => {
      releaseMutation = resolve;
    });

    await previousMutation;
    try {
      const result = await operation();
      await this.persist();
      return result;
    } finally {
      releaseMutation();
    }
  }

  private async persist(): Promise<void> {
    await mkdir(path.dirname(this.filePath), { recursive: true });
    const temporaryPath = `${this.filePath}.${process.pid}.tmp`;
    await writeFile(temporaryPath, JSON.stringify(this.state, null, 2), {
      encoding: "utf8",
      mode: 0o600
    });
    await rename(temporaryPath, this.filePath);
  }
}
