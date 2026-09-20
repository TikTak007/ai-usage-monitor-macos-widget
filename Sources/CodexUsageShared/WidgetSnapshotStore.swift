import Foundation

public enum WidgetUsageConstants {
    public static let widgetKind = "local.aiusagemonitor.usage-widget"
    public static let snapshotURL = URL(string: "http://127.0.0.1:58743/snapshot")!
}

public struct WidgetUsageWindow: Codable, Equatable, Sendable {
    public let label: String
    public let remainingPercent: Int
    public let usedPercent: Int
    public let resetsAt: Date?

    public init(
        label: String,
        remainingPercent: Int,
        usedPercent: Int,
        resetsAt: Date?
    ) {
        self.label = label
        self.remainingPercent = remainingPercent
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct WidgetUsageLimit: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let windows: [WidgetUsageWindow]

    public init(id: String, name: String, windows: [WidgetUsageWindow]) {
        self.id = id
        self.name = name
        self.windows = windows
    }
}

public struct WidgetResetCreditsSummary: Codable, Equatable, Sendable {
    public let availableCount: Int
    public let nearestExpiration: Date?
    public let detailsAvailable: Bool

    public init(
        availableCount: Int,
        nearestExpiration: Date?,
        detailsAvailable: Bool
    ) {
        self.availableCount = availableCount
        self.nearestExpiration = nearestExpiration
        self.detailsAvailable = detailsAvailable
    }
}

public struct WidgetUsageSnapshot: Codable, Equatable, Sendable {
    public let limits: [WidgetUsageLimit]
    public let resetCredits: WidgetResetCreditsSummary?
    public let appearanceMode: String?
    public let updatedAt: Date

    public init(
        limits: [WidgetUsageLimit],
        resetCredits: WidgetResetCreditsSummary? = nil,
        appearanceMode: String? = nil,
        updatedAt: Date
    ) {
        self.limits = limits
        self.resetCredits = resetCredits
        self.appearanceMode = appearanceMode
        self.updatedAt = updatedAt
    }
}

public enum WidgetSnapshotCodec {
    public static func encode(_ snapshot: WidgetUsageSnapshot) throws -> Data {
        try JSONEncoder().encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> WidgetUsageSnapshot {
        try JSONDecoder().decode(WidgetUsageSnapshot.self, from: data)
    }
}
