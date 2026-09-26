import Foundation

public enum WidgetUsageConstants {
    public static let widgetKind = "local.aiusagemonitor.usage-widget"
    public static let graphWidgetKind = widgetKind + ".weekly-graph"
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
    public let weeklyGraphs: [WidgetWeeklyGraph]?

    public init(
        limits: [WidgetUsageLimit],
        resetCredits: WidgetResetCreditsSummary? = nil,
        appearanceMode: String? = nil,
        updatedAt: Date,
        weeklyGraphs: [WidgetWeeklyGraph]? = nil
    ) {
        self.limits = limits
        self.resetCredits = resetCredits
        self.appearanceMode = appearanceMode
        self.updatedAt = updatedAt
        self.weeklyGraphs = weeklyGraphs
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

/// Drawing-only normalized history; never contains an account or credential.
public struct WidgetHistoryPoint: Codable, Equatable, Identifiable, Sendable {
    public let observedAt: Date
    public let remainingPercent: Int
    public let segment: Int
    public var id: Date { observedAt }

    public init(observedAt: Date, remainingPercent: Int, segment: Int) {
        self.observedAt = observedAt
        self.remainingPercent = min(max(remainingPercent, 0), 100)
        self.segment = segment
    }
}

public struct WidgetWeeklyGraph: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let remainingPercent: Int
    public let resetsAt: Date?
    public let exhaustionDate: Date?
    public let points: [WidgetHistoryPoint]
    public static let duration: TimeInterval = 7 * 24 * 3600
    public static let maximumDrawingPoints = 200

    public init(id: String, name: String, remainingPercent: Int, resetsAt: Date?,
                exhaustionDate: Date?, points: [WidgetHistoryPoint]) {
        self.id = id
        self.name = name
        self.remainingPercent = min(max(remainingPercent, 0), 100)
        self.resetsAt = resetsAt
        self.exhaustionDate = exhaustionDate
        self.points = points
    }

    public func domain(observedAt: Date) -> ClosedRange<Date> {
        let end: Date
        if let reset = resetsAt, reset > observedAt,
           reset.timeIntervalSince(observedAt) <= Self.duration {
            end = reset
        } else {
            end = observedAt
        }
        return end.addingTimeInterval(-Self.duration)...end
    }

    public func visiblePoints(observedAt: Date) -> [WidgetHistoryPoint] {
        let range = domain(observedAt: observedAt)
        return points.filter { range.contains($0.observedAt) && $0.observedAt <= observedAt }
    }

    public func forecastDate(observedAt: Date) -> Date? {
        guard let predicted = exhaustionDate, let reset = resetsAt,
              predicted > observedAt, predicted < reset,
              domain(observedAt: observedAt).contains(predicted) else { return nil }
        return predicted
    }
}
