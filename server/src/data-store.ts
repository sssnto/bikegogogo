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

type DatabaseState = {
  version: 2;
  users: UserRecord[];
  sessions: SessionRecord[];
  friendRequests: FriendRequestRecord[];
  friendships: FriendshipRecord[];
};

const emptyState = (): DatabaseState => ({
  version: 2,
  users: [],
  sessions: [],
  friendRequests: [],
  friendships: []
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

  private requireUser(userId: string): UserRecord {
    const user = this.userById(userId);
    if (!user) {
      throw new StoreError("user_not_found", 404, "User not found");
    }
    return user;
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
    this.state.users = this.state.users.filter((user) => user.id !== source.id);
    return target;
  }

  private migrate(raw: Record<string, unknown>): DatabaseState {
    const legacy = raw as unknown as {
      users?: Array<UserRecord & { deviceIdHash?: string }>;
      sessions?: Array<Omit<SessionRecord, "expiresAt"> & { expiresAt?: string }>;
      friendRequests?: FriendRequestRecord[];
      friendships?: FriendshipRecord[];
    };
    const now = Date.now();
    return {
      version: 2,
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
      friendships: legacy.friendships ?? []
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
