import Foundation

public struct UsageWindow: Identifiable, Equatable, Sendable {
    public let source: String
    public let label: String
    public let usedPercent: Int
    public let remainingPercent: Int
    public let windowDurationMins: Int?
    public let resetsAt: Date?

    public var id: String {
        "\(source)-\(windowDurationMins ?? -1)-\(resetsAt?.timeIntervalSince1970 ?? -1)"
    }

    public init(
        source: String,
        label: String,
        usedPercent: Int,
        remainingPercent: Int,
        windowDurationMins: Int?,
        resetsAt: Date?
    ) {
        self.source = source
        self.label = label
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
}

public struct UsageLimit: Identifiable, Equatable, Sendable {
    public let limitID: String
    public let displayName: String
    public let planType: String?
    public let rateLimitReachedType: String?
    public let spendControlReached: Bool?
    public let windows: [UsageWindow]

    public var id: String { limitID }

    public init(
        limitID: String,
        displayName: String,
        planType: String?,
        rateLimitReachedType: String?,
        spendControlReached: Bool?,
        windows: [UsageWindow]
    ) {
        self.limitID = limitID
        self.displayName = displayName
        self.planType = planType
        self.rateLimitReachedType = rateLimitReachedType
        self.spendControlReached = spendControlReached
        self.windows = windows
    }
}

public struct UsageResetCredit: Equatable, Sendable {
    public let grantedAt: Date?
    public let expiresAt: Date?
    public let status: String
    public let resetType: String
    public let title: String?
    public let description: String?

    public init(
        grantedAt: Date?,
        expiresAt: Date?,
        status: String,
        resetType: String,
        title: String?,
        description: String?
    ) {
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.status = status
        self.resetType = resetType
        self.title = title
        self.description = description
    }
}

public struct UsageResetCreditsSummary: Equatable, Sendable {
    public let availableCount: Int
    public let credits: [UsageResetCredit]?

    public var nearestExpiration: Date? {
        credits?.compactMap(\.expiresAt).min()
    }

    public init(availableCount: Int, credits: [UsageResetCredit]?) {
        self.availableCount = availableCount
        self.credits = credits
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public let limits: [UsageLimit]
    public let resetCredits: UsageResetCreditsSummary?
    public let updatedAt: Date

    public init(
        limits: [UsageLimit],
        resetCredits: UsageResetCreditsSummary? = nil,
        updatedAt: Date
    ) {
        self.limits = limits
        self.resetCredits = resetCredits
        self.updatedAt = updatedAt
    }
}
