import Foundation

/// Reset detection is independent of the downward threshold notification baseline.
public struct UsageResetCheckpoint: Codable, Equatable, Sendable {
    public let remainingPercent: Int
    public let resetsAt: TimeInterval?
    public let observedAt: TimeInterval
    public let lastNotifiedResetsAt: TimeInterval?

    public init(
        remainingPercent: Int,
        resetsAt: TimeInterval?,
        observedAt: TimeInterval,
        lastNotifiedResetsAt: TimeInterval? = nil
    ) {
        self.remainingPercent = min(max(remainingPercent, 0), 100)
        self.resetsAt = resetsAt.flatMap { $0.isFinite ? $0 : nil }
        self.observedAt = observedAt
        self.lastNotifiedResetsAt = lastNotifiedResetsAt
    }
}

public enum UsageResetPolicy {
    public static let retentionInterval: TimeInterval = 14 * 24 * 60 * 60
    public static let resetTimestampTolerance: TimeInterval = 60
    public static let minimumEarlyRecovery = 20
    public static let minimumEarlyRemaining = 90

    /// A future, advanced reset timestamp confirms a scheduled cycle transition.
    /// Before the prior deadline, substantial replenishment is also required.
    /// Percentages alone never establish a reset, including when metadata is absent.
    public static func update(
        previous: UsageResetCheckpoint?,
        remainingPercent: Int,
        resetsAt: Date?,
        observedAt: Date
    ) -> (checkpoint: UsageResetCheckpoint?, resetConfirmed: Bool) {
        let observed = observedAt.timeIntervalSince1970
        guard observed.isFinite else { return (previous, false) }
        if let previous, observed <= previous.observedAt {
            return (previous, false)
        }

        let remaining = min(max(remainingPercent, 0), 100)
        let reset = resetsAt?.timeIntervalSince1970
        let validReset = reset.flatMap { $0.isFinite ? $0 : nil }
        let retainedReset: TimeInterval?
        if let previousReset = previous?.resetsAt {
            // A backward metadata revision must not manufacture a short cycle
            // that looks like a reset when the original deadline reappears.
            retainedReset = validReset.map { max(previousReset, $0) } ?? previousReset
        } else {
            retainedReset = validReset
        }
        var confirmed = false
        if let previous, let oldReset = previous.resetsAt, let newReset = validReset {
            let advancesCycle = newReset > oldReset + resetTimestampTolerance
            let notAlreadyNotified = previous.lastNotifiedResetsAt.map {
                newReset > $0 + resetTimestampTolerance
            } ?? true
            let scheduled = observed >= oldReset
            let replenished = remaining >= minimumEarlyRemaining
                && remaining - previous.remainingPercent >= minimumEarlyRecovery
            confirmed = advancesCycle && newReset > observed && notAlreadyNotified
                && (scheduled || replenished)
        }

        return (
            UsageResetCheckpoint(
                remainingPercent: remaining,
                // A missing field does not erase previously authoritative cycle metadata.
                resetsAt: retainedReset,
                observedAt: observed,
                lastNotifiedResetsAt: confirmed ? validReset : previous?.lastNotifiedResetsAt
            ),
            confirmed
        )
    }

    /// Keep temporarily absent buckets, but bound persistence to two weeks.
    public static func prune(
        _ checkpoints: [String: UsageResetCheckpoint],
        observedAt: Date
    ) -> [String: UsageResetCheckpoint] {
        let timestamp = observedAt.timeIntervalSince1970
        guard timestamp.isFinite else { return checkpoints }
        let latest = max(timestamp, checkpoints.values.map(\.observedAt).max() ?? timestamp)
        return checkpoints.filter {
            $0.value.observedAt.isFinite && latest - $0.value.observedAt <= retentionInterval
        }
    }
}
