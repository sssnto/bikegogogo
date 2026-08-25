export type AdminRole = "viewer" | "admin";

export type UserRecord = {
  id: string;
  deviceIdHashes?: string[];
  appleSubject?: string;
  email?: string;
  displayName: string;
  friendCode: string;
  createdAt: string;
  updatedAt: string;
};

export type RideRecord = {
  id: string;
  userId: string;
  title: string;
  source: "iPhone" | "appleWatch" | "merged";
  startedAt: string;
  endedAt?: string;
  points?: Array<{ heartRateBeatsPerMinute?: number }>;
  metrics: {
    distanceMeters: number;
    movingDurationSeconds: number;
    elapsedDurationSeconds: number;
    averageHeartRate?: number;
    activeEnergyKilocalories?: number;
  };
  weather?: unknown;
  createdAt: string;
  updatedAt: string;
};

export type BusinessState = {
  version?: number;
  users: UserRecord[];
  sessions: Array<{ userId: string; expiresAt: string }>;
  friendRequests: Array<{
    id: string;
    fromUserId: string;
    toUserId: string;
    status: "pending" | "accepted" | "rejected";
    createdAt: string;
    updatedAt: string;
  }>;
  friendships: Array<{ userAId: string; userBId: string; createdAt: string }>;
  groups: Array<{
    id: string;
    ownerId: string;
    memberIds: string[];
    createdAt: string;
    updatedAt: string;
  }>;
  rides: RideRecord[];
  pushTokens: Array<{
    userId: string;
    environment: "sandbox" | "production";
    createdAt: string;
    updatedAt: string;
  }>;
  voiceInvitations: Array<{
    id: string;
    callerId: string;
    targetKind: "friend" | "group";
    recipientIds: string[];
    respondedRecipientIds: string[];
    createdAt: string;
    expiresAt: string;
    cancelledAt?: string;
  }>;
};

export type BusinessSnapshot = {
  state: BusinessState;
  revision: number;
  updatedAt: string;
};
