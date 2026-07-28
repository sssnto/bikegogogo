export type LiveLocationInput = {
  latitude: number;
  longitude: number;
  horizontalAccuracyMeters?: number;
  speedMetersPerSecond?: number;
  courseDegrees?: number;
  capturedAt: string;
};

export type LiveLocationRecord = LiveLocationInput & {
  groupId: string;
  userId: string;
  updatedAt: string;
};

export class LiveLocationStore {
  private readonly locations = new Map<string, LiveLocationRecord>();

  constructor(
    private readonly ttlMilliseconds = 90_000,
    private readonly now: () => Date = () => new Date()
  ) {}

  upsert(
    groupId: string,
    userId: string,
    input: LiveLocationInput
  ): LiveLocationRecord {
    const record: LiveLocationRecord = {
      ...input,
      groupId,
      userId,
      updatedAt: this.now().toISOString()
    };
    this.locations.set(this.key(groupId, userId), record);
    this.prune();
    return record;
  }

  list(groupId: string): LiveLocationRecord[] {
    this.prune();
    return Array.from(this.locations.values())
      .filter((location) => location.groupId === groupId)
      .sort((first, second) => second.updatedAt.localeCompare(first.updatedAt));
  }

  remove(groupId: string, userId: string): void {
    this.locations.delete(this.key(groupId, userId));
  }

  removeGroup(groupId: string): void {
    for (const [key, location] of this.locations) {
      if (location.groupId === groupId) {
        this.locations.delete(key);
      }
    }
  }

  removeUser(userId: string): void {
    for (const [key, location] of this.locations) {
      if (location.userId === userId) {
        this.locations.delete(key);
      }
    }
  }

  private prune(): void {
    const cutoff = this.now().getTime() - this.ttlMilliseconds;
    for (const [key, location] of this.locations) {
      if (new Date(location.updatedAt).getTime() < cutoff) {
        this.locations.delete(key);
      }
    }
  }

  private key(groupId: string, userId: string): string {
    return `${groupId}:${userId}`;
  }
}
