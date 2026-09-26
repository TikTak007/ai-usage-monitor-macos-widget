import Foundation

/// Reset detection is independent of the downward threshold notification baseline.
public struct UsageResetCheckpoint: Codable, Equatable, Sendable {
    public let remainingPercent: Int
    public let resetsAt: TimeInterval?
    public let observedAt: TimeInterval
    public let lastNotifiedResetsAt: TimeInterval?

    public let pendingRemainingPercent: Int?
    public let pendingObservedAt: TimeInterval?
    public let pendingResetsAt: TimeInterval?

    public init(
        remainingPercent: Int,
        resetsAt: TimeInterval?,
        observedAt: TimeInterval,
        lastNotifiedResetsAt: TimeInterval? = nil,
        pendingRemainingPercent: Int? = nil,
        pendingObservedAt: TimeInterval? = nil,
        pendingResetsAt: TimeInterval? = nil
    ) {
        self.remainingPercent = min(max(remainingPercent, 0), 100)
        self.resetsAt = resetsAt.flatMap { $0.isFinite ? $0 : nil }
        self.observedAt = observedAt
        self.lastNotifiedResetsAt = lastNotifiedResetsAt
        self.pendingRemainingPercent = pendingRemainingPercent
        self.pendingObservedAt = pendingObservedAt
        self.pendingResetsAt = pendingResetsAt
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
        // Correlate split observations for at most fifteen minutes. An early
        // metadata revision alone must never become a scheduled reset later.
        let pendingIsFresh = previous?.pendingObservedAt.map {
            observed - $0 <= 15 * 60
        } ?? false
        let baseline = pendingIsFresh
            ? (previous?.pendingRemainingPercent ?? remaining)
            : (previous?.remainingPercent ?? remaining)
        var pendingRemaining = pendingIsFresh ? previous?.pendingRemainingPercent : nil
        var pendingObserved = pendingIsFresh ? previous?.pendingObservedAt : nil
        var pendingReset = pendingIsFresh ? previous?.pendingResetsAt : nil
        var confirmed = false
        if let previous, let oldReset = previous.resetsAt, let newReset = validReset {
            let advancesCycle = newReset > oldReset + resetTimestampTolerance
            let matchesPending = pendingReset.map {
                abs(newReset - $0) <= resetTimestampTolerance
            } ?? false
            let notAlreadyNotified = previous.lastNotifiedResetsAt.map {
                newReset > $0 + resetTimestampTolerance
            } ?? true
            let replenished = remaining >= minimumEarlyRemaining
                && remaining - baseline >= minimumEarlyRecovery
            confirmed = newReset > observed && notAlreadyNotified
                && ((advancesCycle && (observed >= oldReset || replenished))
                    || (matchesPending && replenished))
            if advancesCycle && !confirmed {
                pendingRemaining = baseline
                pendingObserved = pendingObserved ?? observed
                pendingReset = newReset
            }
        } else if validReset == nil, previous?.resetsAt != nil {
            pendingRemaining = pendingRemaining ?? previous?.remainingPercent
            pendingObserved = pendingObserved ?? observed
        }
        if confirmed {
            pendingRemaining = nil
            pendingObserved = nil
            pendingReset = nil
        }
        return (
            UsageResetCheckpoint(
                remainingPercent: remaining,
                resetsAt: retainedReset,
                observedAt: observed,
                lastNotifiedResetsAt: confirmed ? validReset : previous?.lastNotifiedResetsAt,
                pendingRemainingPercent: pendingRemaining,
                pendingObservedAt: pendingObserved,
                pendingResetsAt: pendingReset
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
