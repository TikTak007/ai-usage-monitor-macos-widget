import Foundation

public struct UsageThresholdCheckpoint: Codable, Equatable, Sendable {
    public let remainingPercent: Int
    public let resetsAt: TimeInterval?

    public init(remainingPercent: Int, resetsAt: TimeInterval?) {
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }
}

public enum UsageThresholdPolicy {
    public static let thresholds = Array(stride(from: 90, through: 10, by: -10))

    public static func checkpoint(
        remainingPercent: Int,
        resetsAt: Date?
    ) -> UsageThresholdCheckpoint {
        UsageThresholdCheckpoint(
            remainingPercent: remainingPercent,
            resetsAt: resetsAt?.timeIntervalSince1970
        )
    }

    /// Returns the lowest newly crossed 10-point boundary for this refresh.
    /// A first observation, a new reset cycle, or an upward correction only
    /// establishes a baseline and never generates a notification.
    public static func crossedThreshold(
        previous: UsageThresholdCheckpoint?,
        remainingPercent: Int,
        resetsAt: Date?
    ) -> Int? {
        guard (0...100).contains(remainingPercent), let previous else {
            return nil
        }

        let currentReset = resetsAt?.timeIntervalSince1970
        guard previous.resetsAt == currentReset,
              remainingPercent < previous.remainingPercent
        else {
            return nil
        }

        return thresholds.last {
            previous.remainingPercent > $0 && remainingPercent <= $0
        }
    }
}
