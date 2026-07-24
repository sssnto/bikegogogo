import Foundation

public enum SampleData {
    public static let friends: [Friend] = [
        Friend(displayName: "阿鹏", isRiding: true),
        Friend(displayName: "小林", isRiding: true),
        Friend(displayName: "Kevin", isRiding: false)
    ]

    public static let group = CyclingGroup(
        id: UUID(uuidString: "B1CE60D0-0000-4000-8000-000000000001")!,
        name: "周末滨江骑行",
        members: friends
    )

    public static var ride: RideSession {
        let start = Date(timeIntervalSince1970: 1_785_000_000)
        let points = [
            RidePoint(latitude: 31.2304, longitude: 121.4737, elevationMeters: 8, speedMetersPerSecond: 5.8, heartRateBeatsPerMinute: 118, timestamp: start),
            RidePoint(latitude: 31.2320, longitude: 121.4768, elevationMeters: 10, speedMetersPerSecond: 6.4, heartRateBeatsPerMinute: 126, timestamp: start.addingTimeInterval(60)),
            RidePoint(latitude: 31.2351, longitude: 121.4800, elevationMeters: 13, speedMetersPerSecond: 7.2, heartRateBeatsPerMinute: 132, timestamp: start.addingTimeInterval(120)),
            RidePoint(latitude: 31.2380, longitude: 121.4842, elevationMeters: 12, speedMetersPerSecond: 7.8, heartRateBeatsPerMinute: 138, timestamp: start.addingTimeInterval(180))
        ]

        return RideSession(
            title: "浦东滨江轻松骑",
            state: .finished,
            source: .merged,
            startedAt: start,
            endedAt: start.addingTimeInterval(180),
            points: points,
            metrics: RideStatisticsCalculator.metrics(for: points)
        )
    }

    public static var voiceRoom: VoiceRoom {
        VoiceRoom(
            groupID: group.id,
            roomName: "weekend-riverside",
            participants: [],
            isJoined: false,
            isMuted: false
        )
    }
}
