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

public enum UsageHistory {
    public static let retention: TimeInterval = 7 * 24 * 60 * 60
    public static let maximumSamples = 4_096
    public static let maximumConnectedGap: TimeInterval = 5 * 60

    public static func recording(
        _ samples: [UsageHistorySample], remainingPercent: Int,
        observedAt: Date, resetsAt: Date?
    ) -> [UsageHistorySample] {
        guard (0...100).contains(remainingPercent),
              samples.last.map({ observedAt > $0.observedAt }) ?? true else { return samples }
        var result = samples
        let last = result.last
        // A gap or a changed cycle ends the old path; never draw a fabricated recovery.
        let breaksPath = last.map {
            observedAt.timeIntervalSince($0.observedAt) > maximumConnectedGap ||
                ($0.resetsAt != nil && resetsAt != nil && $0.resetsAt != resetsAt)
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
}
