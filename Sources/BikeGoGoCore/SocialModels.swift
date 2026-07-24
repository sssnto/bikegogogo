import Foundation

public enum FriendshipStatus: String, Codable, Sendable {
    case pending
    case accepted
    case blocked
}

public struct Friend: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var displayName: String
    public var avatarURL: URL?
    public var status: FriendshipStatus
    public var isRiding: Bool

    public init(
        id: UUID = UUID(),
        displayName: String,
        avatarURL: URL? = nil,
        status: FriendshipStatus = .accepted,
        isRiding: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.status = status
        self.isRiding = isRiding
    }
}

public struct CyclingGroup: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var members: [Friend]
    public var activeVoiceRoomID: UUID?

    public init(
        id: UUID = UUID(),
        name: String,
        members: [Friend],
        activeVoiceRoomID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.members = members
        self.activeVoiceRoomID = activeVoiceRoomID
    }
}

public struct VoiceParticipant: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var displayName: String
    public var isMuted: Bool
    public var isSpeaking: Bool
    public var connectionQuality: VoiceConnectionQuality

    public init(
        id: UUID = UUID(),
        displayName: String,
        isMuted: Bool = false,
        isSpeaking: Bool = false,
        connectionQuality: VoiceConnectionQuality = .good
    ) {
        self.id = id
        self.displayName = displayName
        self.isMuted = isMuted
        self.isSpeaking = isSpeaking
        self.connectionQuality = connectionQuality
    }
}

public enum VoiceConnectionQuality: String, Codable, Sendable {
    case excellent
    case good
    case weak
    case reconnecting
    case disconnected
}

public struct VoiceRoom: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var groupID: UUID
    public var roomName: String
    public var participants: [VoiceParticipant]
    public var isJoined: Bool
    public var isMuted: Bool

    public init(
        id: UUID = UUID(),
        groupID: UUID,
        roomName: String,
        participants: [VoiceParticipant] = [],
        isJoined: Bool = false,
        isMuted: Bool = false
    ) {
        self.id = id
        self.groupID = groupID
        self.roomName = roomName
        self.participants = participants
        self.isJoined = isJoined
        self.isMuted = isMuted
    }
}

