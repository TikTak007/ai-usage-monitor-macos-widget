import Foundation

public struct UsagePaceSample: Codable, Equatable, Sendable {
    public let observedAt: TimeInterval
    public let cumulativeUsedPercent: Double

    public init(observedAt: TimeInterval, cumulativeUsedPercent: Double) {
        self.observedAt = observedAt
        self.cumulativeUsedPercent = cumulativeUsedPercent
    }
}

public struct UsagePaceHistory: Codable, Equatable, Sendable {
    public let firstObservedAt: TimeInterval
    public let latestUsedPercent: Int
    public let accountedUsedPercent: Int
    public let latestObservedAt: TimeInterval
    public let latestResetsAt: TimeInterval?
    public let cumulativeUsedPercent: Double
    public let recentSamples: [UsagePaceSample]
    public let longTermUsedPercentPerHour: Double?

    public init(
        firstObservedAt: TimeInterval,
        latestUsedPercent: Int,
        accountedUsedPercent: Int,
        latestObservedAt: TimeInterval,
        latestResetsAt: TimeInterval?,
        cumulativeUsedPercent: Double,
        recentSamples: [UsagePaceSample],
        longTermUsedPercentPerHour: Double?
    ) {
        self.firstObservedAt = firstObservedAt
        self.latestUsedPercent = latestUsedPercent
        self.accountedUsedPercent = accountedUsedPercent
        self.latestObservedAt = latestObservedAt
        self.latestResetsAt = latestResetsAt
        self.cumulativeUsedPercent = cumulativeUsedPercent
        self.recentSamples = recentSamples
        self.longTermUsedPercentPerHour = longTermUsedPercentPerHour
    }
}

public enum UsagePaceConfidence: String, Codable, Equatable, Sendable {
    case medium
    case high
}

public struct UsagePaceEstimate: Equatable, Sendable {
    public let exhaustionDate: Date
    public let usedPercentPerHour: Double
    public let recentUsedPercentPerHour: Double?
    public let longTermUsedPercentPerHour: Double
    public let confidence: UsagePaceConfidence

    public init(
        exhaustionDate: Date,
        usedPercentPerHour: Double,
        recentUsedPercentPerHour: Double?,
        longTermUsedPercentPerHour: Double,
        confidence: UsagePaceConfidence
    ) {
        self.exhaustionDate = exhaustionDate
        self.usedPercentPerHour = usedPercentPerHour
        self.recentUsedPercentPerHour = recentUsedPercentPerHour
        self.longTermUsedPercentPerHour = longTermUsedPercentPerHour
        self.confidence = confidence
    }
}

public enum UsagePaceEstimator {
    /// Avoids treating a single short burst (or percentage rounding) as a stable pace.
    public static let minimumObservationInterval: TimeInterval = 15 * 60
    public static let maximumSampleCount = 64

    private static let minimumSampleSpacing: TimeInterval = 150
    private static let resetTimestampTolerance: TimeInterval = 60
    private static let resetObservationTolerance: TimeInterval = 5 * 60

    public static func update(
        history: UsagePaceHistory?,
        usedPercent: Int,
        observedAt: Date,
        resetsAt: Date?,
        windowDurationMins: Int? = nil
    ) -> (history: UsagePaceHistory, estimate: UsagePaceEstimate?) {
        let currentUsedPercent = min(max(usedPercent, 0), 100)
        let observedTimestamp = observedAt.timeIntervalSince1970
        let resetTimestamp = resetsAt?.timeIntervalSince1970
        let shortHorizon = shortHorizon(windowDurationMins: windowDurationMins)
        let halfLife = longTermHalfLife(windowDurationMins: windowDurationMins)

        guard let history else {
            return (
                UsagePaceHistory(
                    firstObservedAt: observedTimestamp,
                    latestUsedPercent: currentUsedPercent,
                    accountedUsedPercent: currentUsedPercent,
                    latestObservedAt: observedTimestamp,
                    latestResetsAt: resetTimestamp,
                    cumulativeUsedPercent: 0,
                    recentSamples: [
                        UsagePaceSample(
                            observedAt: observedTimestamp,
                            cumulativeUsedPercent: 0
                        )
                    ],
                    longTermUsedPercentPerHour: nil
                ),
                nil
            )
        }

        guard observedTimestamp > history.latestObservedAt else {
            return (history, nil)
        }

        let elapsedSinceLatest = observedTimestamp - history.latestObservedAt
        let didReset = resetOccurred(
            history: history,
            currentUsedPercent: currentUsedPercent,
            observedTimestamp: observedTimestamp,
            resetTimestamp: resetTimestamp
        )

        let consumedDelta: Double
        let accountedUsedPercent: Int
        if didReset {
            // The new cycle's current usage is consumption after the reset. Adding it keeps
            // the cumulative counter monotonic instead of turning 85% -> 3% into -82%.
            consumedDelta = Double(currentUsedPercent)
            accountedUsedPercent = currentUsedPercent
        } else if currentUsedPercent > history.accountedUsedPercent {
            consumedDelta = Double(currentUsedPercent - history.accountedUsedPercent)
            accountedUsedPercent = currentUsedPercent
        } else {
            // Small downward movements are backend corrections, not negative consumption.
            consumedDelta = 0
            accountedUsedPercent = history.accountedUsedPercent
        }

        let cumulativeUsedPercent = history.cumulativeUsedPercent + consumedDelta
        let samples = updatedSamples(
            history.recentSamples,
            observedTimestamp: observedTimestamp,
            cumulativeUsedPercent: cumulativeUsedPercent,
            shortHorizon: shortHorizon
        )
        let recent = recentRate(
            samples: samples,
            observedTimestamp: observedTimestamp,
            cumulativeUsedPercent: cumulativeUsedPercent,
            shortHorizon: shortHorizon
        )
        let longTermRate: Double?
        if let recent,
           recent.elapsed >= minimumObservationInterval {
            longTermRate = updatedLongTermRate(
                previous: history.longTermUsedPercentPerHour,
                recentRatePerHour: recent.ratePerHour,
                elapsed: elapsedSinceLatest,
                halfLife: halfLife
            )
        } else {
            longTermRate = history.longTermUsedPercentPerHour
        }

        let updatedHistory = UsagePaceHistory(
            firstObservedAt: history.firstObservedAt,
            latestUsedPercent: currentUsedPercent,
            accountedUsedPercent: accountedUsedPercent,
            latestObservedAt: observedTimestamp,
            latestResetsAt: resetTimestamp,
            cumulativeUsedPercent: cumulativeUsedPercent,
            recentSamples: samples,
            longTermUsedPercentPerHour: longTermRate
        )

        let totalObservationTime = observedTimestamp - history.firstObservedAt
        guard totalObservationTime >= minimumObservationInterval,
              currentUsedPercent < 100,
              let longTermRate,
              let resetsAt,
              resetsAt > observedAt
        else {
            return (updatedHistory, nil)
        }

        let effectiveRate: Double
        if let recent,
           recent.elapsed >= minimumObservationInterval {
            effectiveRate = recent.ratePerHour * 0.6 + longTermRate * 0.4
        } else {
            effectiveRate = longTermRate
        }

        guard effectiveRate > 0.0001 else {
            return (updatedHistory, nil)
        }

        let remainingPercent = 100 - currentUsedPercent
        let secondsUntilExhausted = Double(remainingPercent) / effectiveRate * 60 * 60
        let exhaustionDate = observedAt.addingTimeInterval(secondsUntilExhausted)

        guard exhaustionDate < resetsAt else {
            return (updatedHistory, nil)
        }

        let confidence: UsagePaceConfidence
        if let recent,
           recent.elapsed >= shortHorizon * 0.9,
           totalObservationTime >= halfLife {
            confidence = .high
        } else {
            confidence = .medium
        }

        return (
            updatedHistory,
            UsagePaceEstimate(
                exhaustionDate: exhaustionDate,
                usedPercentPerHour: effectiveRate,
                recentUsedPercentPerHour: recent?.ratePerHour,
                longTermUsedPercentPerHour: longTermRate,
                confidence: confidence
            )
        )
    }

    public static func shortHorizon(windowDurationMins: Int?) -> TimeInterval {
        guard let minutes = windowDurationMins, minutes > 0 else {
            return 60 * 60
        }
        if minutes <= 5 * 60 { return 30 * 60 }
        if minutes >= 7 * 24 * 60 { return 3 * 60 * 60 }
        return min(max(Double(minutes) * 60 * 0.1, 30 * 60), 3 * 60 * 60)
    }

    public static func longTermHalfLife(windowDurationMins: Int?) -> TimeInterval {
        guard let minutes = windowDurationMins, minutes > 0 else {
            return 6 * 60 * 60
        }
        if minutes <= 5 * 60 { return 2 * 60 * 60 }
        if minutes >= 7 * 24 * 60 { return 24 * 60 * 60 }
        return min(max(Double(minutes) * 60 / 3, 2 * 60 * 60), 24 * 60 * 60)
    }

    private static func resetOccurred(
        history: UsagePaceHistory,
        currentUsedPercent: Int,
        observedTimestamp: TimeInterval,
        resetTimestamp: TimeInterval?
    ) -> Bool {
        if let previousReset = history.latestResetsAt,
           let resetTimestamp,
           resetTimestamp > previousReset + resetTimestampTolerance,
           (observedTimestamp >= previousReset - resetObservationTolerance ||
               currentUsedPercent < history.latestUsedPercent) {
            return true
        }

        let usedDrop = history.latestUsedPercent - currentUsedPercent
        return usedDrop >= 30 && currentUsedPercent <= 15
    }

    private static func updatedLongTermRate(
        previous: Double?,
        recentRatePerHour: Double,
        elapsed: TimeInterval,
        halfLife: TimeInterval
    ) -> Double {
        guard let previous else { return recentRatePerHour }
        let alpha = 1 - pow(0.5, elapsed / halfLife)
        return recentRatePerHour * alpha + previous * (1 - alpha)
    }

    private static func updatedSamples(
        _ existingSamples: [UsagePaceSample],
        observedTimestamp: TimeInterval,
        cumulativeUsedPercent: Double,
        shortHorizon: TimeInterval
    ) -> [UsagePaceSample] {
        var samples = existingSamples
        let newSample = UsagePaceSample(
            observedAt: observedTimestamp,
            cumulativeUsedPercent: cumulativeUsedPercent
        )

        if samples.count > 1,
           let last = samples.last,
           observedTimestamp - last.observedAt < minimumSampleSpacing {
            samples[samples.count - 1] = newSample
        } else {
            samples.append(newSample)
        }

        let cutoff = observedTimestamp - shortHorizon * 1.25
        if let firstInside = samples.firstIndex(where: { $0.observedAt >= cutoff }),
           firstInside > 1 {
            samples.removeFirst(firstInside - 1)
        }

        if samples.count > maximumSampleCount {
            samples.removeFirst(samples.count - maximumSampleCount)
        }
        return samples
    }

    private static func recentRate(
        samples: [UsagePaceSample],
        observedTimestamp: TimeInterval,
        cumulativeUsedPercent: Double,
        shortHorizon: TimeInterval
    ) -> (ratePerHour: Double, elapsed: TimeInterval)? {
        guard let first = samples.first,
              let last = samples.last,
              last.observedAt > first.observedAt
        else {
            return nil
        }

        let targetTimestamp = observedTimestamp - shortHorizon
        let start: UsagePaceSample
        if targetTimestamp <= first.observedAt {
            start = first
        } else if let upperIndex = samples.firstIndex(where: { $0.observedAt >= targetTimestamp }),
                  upperIndex > 0 {
            let lower = samples[upperIndex - 1]
            let upper = samples[upperIndex]
            let span = upper.observedAt - lower.observedAt
            let ratio = span > 0 ? (targetTimestamp - lower.observedAt) / span : 0
            start = UsagePaceSample(
                observedAt: targetTimestamp,
                cumulativeUsedPercent: lower.cumulativeUsedPercent +
                    (upper.cumulativeUsedPercent - lower.cumulativeUsedPercent) * ratio
            )
        } else {
            start = first
        }

        let elapsed = observedTimestamp - start.observedAt
        guard elapsed > 0 else { return nil }
        let consumed = max(0, cumulativeUsedPercent - start.cumulativeUsedPercent)
        return (consumed / elapsed * 60 * 60, elapsed)
    }
}
