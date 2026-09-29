import Foundation

public struct UsageHistorySample: Codable, Equatable, Identifiable, Sendable {
    public let observedAt: Date
    public let remainingPercent: Int
    public let resetsAt: Date?
    public let segment: Int
    public var id: Date { observedAt }

    public init(observedAt: Date, remainingPercent: Int, resetsAt: Date?, segment: Int = 0) {
        self.observedAt = observedAt
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.segment = segment
    }
}

/// A point used only for drawing. The start point and light connections are never recorded.
public struct UsageChartPoint: Equatable, Identifiable, Sendable {
    public let observedAt: Date
    public let remainingPercent: Int
    public let lightFromPrevious: Bool
    public var id: Date { observedAt }

    public init(observedAt: Date, remainingPercent: Int, lightFromPrevious: Bool) {
        self.observedAt = observedAt
        self.remainingPercent = remainingPercent
        self.lightFromPrevious = lightFromPrevious
    }
}

public enum UsageHistory {
    public static let retention: TimeInterval = 7 * 24 * 60 * 60
    public static let maximumSamples = 4_096
    public static let maximumConnectedGap: TimeInterval = 5 * 60

    /// Show exactly one weekly period, ending at the authoritative next reset.
    /// Missing, expired or implausibly distant metadata falls back to seven days of history.
    public static func chartDomain(observedAt: Date, resetsAt: Date?) -> ClosedRange<Date> {
        let end: Date
        if let reset = resetsAt, reset > observedAt,
           reset.timeIntervalSince(observedAt) <= retention {
            end = reset
        } else {
            end = observedAt
        }
        return end.addingTimeInterval(-retention)...end
    }

    public static func recording(
        _ samples: [UsageHistorySample], remainingPercent: Int,
        observedAt: Date, resetsAt: Date?
    ) -> [UsageHistorySample] {
        guard (0...100).contains(remainingPercent),
              samples.last.map({ observedAt > $0.observedAt }) ?? true else { return samples }
        var result = samples
        let last = result.last
        let knownReset = result.last(where: { $0.resetsAt != nil })?.resetsAt
        // A gap or a changed cycle ends the old path; never draw a fabricated recovery.
        let breaksPath = last.map {
            observedAt.timeIntervalSince($0.observedAt) > maximumConnectedGap ||
                (knownReset != nil && resetsAt != nil && knownReset != resetsAt) ||
                remainingPercent > $0.remainingPercent
        } ?? false
        let segment = (last?.segment ?? 0) + (breaksPath ? 1 : 0)
        let sample = UsageHistorySample(observedAt: observedAt, remainingPercent: remainingPercent,
                                        resetsAt: resetsAt, segment: segment)
        if let last, !breaksPath, observedAt.timeIntervalSince(last.observedAt) < 150 {
            result[result.count - 1] = sample
        } else {
            result.append(sample)
        }
        let cutoff = observedAt.addingTimeInterval(-retention)
        result.removeAll { $0.observedAt < cutoff }
        if result.count > maximumSamples { result.removeFirst(result.count - maximumSamples) }
        return result
    }

    /// Preserve each bucket's extrema and chronological order, including reset/gap segments.
    /// Storage retains three-minute observations; only the rendering copy is reduced.
    public static func drawingSamples(
        _ samples: [UsageHistorySample], maximumPoints: Int = 600
    ) -> [UsageHistorySample] {
        guard maximumPoints >= 4, samples.count > maximumPoints else { return samples }
        let bucketCount = (maximumPoints - 2) / 2
        var selected = Set([0, samples.count - 1])
        for bucket in 0..<bucketCount {
            let lower = bucket * samples.count / bucketCount
            let upper = (bucket + 1) * samples.count / bucketCount
            let indices = lower..<upper
            if let low = indices.min(by: { samples[$0].remainingPercent < samples[$1].remainingPercent }),
               let high = indices.max(by: { samples[$0].remainingPercent < samples[$1].remainingPercent }) {
                selected.insert(low)
                selected.insert(high)
            }
        }
        return selected.sorted().map { samples[$0] }
    }

    /// Draw one current cycle. Classify gaps before reducing points so normal three-minute
    /// observations do not become light merely because the rendering copy is sparse.
    public static func chartPoints(
        _ samples: [UsageHistorySample], remainingPercent: Int,
        observedAt: Date, resetsAt: Date?, maximumPoints: Int = 600
    ) -> [UsageChartPoint] {
        guard (0...100).contains(remainingPercent), maximumPoints >= 2 else { return [] }
        let range = chartDomain(observedAt: observedAt, resetsAt: resetsAt)
        let hasCycleStart = resetsAt.map {
            $0 > observedAt && $0.timeIntervalSince(observedAt) <= retention
        } ?? false
        let ordered = samples.filter {
            range.contains($0.observedAt) && $0.observedAt <= observedAt
        }.sorted { $0.observedAt < $1.observedAt }
        // A sample without reset metadata can belong to this cycle only after
        // an observation established the matching reset. Otherwise it may be
        // from the preceding cycle when the reset time changed irregularly.
        var knownCycle: Date?
        var source = ordered.filter { sample in
            if let reset = sample.resetsAt { knownCycle = reset }
            guard let resetsAt else { return true }
            guard let knownCycle else { return false }
            // Reset metadata can vary by one second within the same weekly period.
            // Compare to the current reset directly (never accumulate tolerances),
            // while the domain above still excludes observations before its start.
            return abs(knownCycle.timeIntervalSince(resetsAt)) <= 1
        }
        if source.last?.observedAt == observedAt {
            source[source.count - 1] = UsageHistorySample(
                observedAt: observedAt, remainingPercent: remainingPercent,
                resetsAt: resetsAt, segment: source[source.count - 1].segment)
        } else {
            source.append(UsageHistorySample(observedAt: observedAt, remainingPercent: remainingPercent,
                                             resetsAt: resetsAt, segment: source.last?.segment ?? 0))
        }
        guard !source.isEmpty else { return [] }

        // Keep both ends of a missing interval whenever the drawing limit permits it.
        var boundary = Set([0, source.count - 1])
        if source.count > 1 {
            for index in 1..<source.count
                where source[index].observedAt.timeIntervalSince(source[index - 1].observedAt) > maximumConnectedGap {
                boundary.insert(index - 1)
                boundary.insert(index)
            }
        }
        let sourceBudget = maximumPoints - (hasCycleStart && source.first?.observedAt != range.lowerBound ? 1 : 0)
        let preferredDates = Set(drawingSamples(source, maximumPoints: sourceBudget).map(\.observedAt))
        var selected = boundary.sorted()
        if sourceBudget == 1 {
            selected = [source.count - 1]
        } else if selected.count > sourceBudget {
            selected = [0, source.count - 1]
            let extrema = [source.indices.min(by: { source[$0].remainingPercent < source[$1].remainingPercent }),
                           source.indices.max(by: { source[$0].remainingPercent < source[$1].remainingPercent })]
            for index in extrema.compactMap({ $0 })
                where selected.count < sourceBudget && !selected.contains(index) {
                selected.append(index)
            }
            let candidates = boundary.sorted().filter { !selected.contains($0) }
            let slots = sourceBudget - selected.count
            if slots > 0 {
                selected += (0..<slots).map {
                    candidates[(2 * $0 + 1) * candidates.count / (2 * slots)]
                }
            }
            selected.sort()
        } else {
            var available = sourceBudget - selected.count
            if available > 0 {
                let extrema = [source.indices.min(by: { source[$0].remainingPercent < source[$1].remainingPercent }),
                               source.indices.max(by: { source[$0].remainingPercent < source[$1].remainingPercent })]
                for index in extrema.compactMap({ $0 }) where available > 0 && !boundary.contains(index) && !selected.contains(index) {
                    selected.append(index)
                    available -= 1
                }
                let candidates = source.indices.filter {
                    preferredDates.contains(source[$0].observedAt) && !boundary.contains($0) && !selected.contains($0)
                }
                if candidates.count <= available {
                    selected += candidates
                } else if available > 0 {
                    selected += (0..<available).map {
                        candidates[(2 * $0 + 1) * candidates.count / (2 * available)]
                    }
                }
            }
            selected.sort()
        }

        var points: [UsageChartPoint] = []
        if hasCycleStart && source[0].observedAt > range.lowerBound {
            points.append(UsageChartPoint(observedAt: range.lowerBound, remainingPercent: 100,
                                          lightFromPrevious: false))
        }
        var previousIndex: Int?
        for index in selected {
            let light: Bool
            if let previousIndex {
                light = ((previousIndex + 1)...index).contains {
                    source[$0].observedAt.timeIntervalSince(source[$0 - 1].observedAt) > maximumConnectedGap
                }
            } else {
                light = !points.isEmpty
            }
            points.append(UsageChartPoint(observedAt: source[index].observedAt,
                                          remainingPercent: source[index].remainingPercent,
                                          lightFromPrevious: light))
            previousIndex = index
        }
        return points
    }
}
