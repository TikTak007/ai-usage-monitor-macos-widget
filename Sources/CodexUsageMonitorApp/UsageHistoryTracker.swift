import CodexUsageCore
import Foundation

final class UsageHistoryTracker: @unchecked Sendable {
    private let lock = NSLock()
    private let defaults: UserDefaults
    private let storageKey = "usageWeeklyHistory.v1"
    private var histories: [String: [UsageHistorySample]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([String: [UsageHistorySample]].self, from: data) {
            histories = stored
        } else {
            histories = [:]
        }
    }

    func process(_ snapshot: UsageSnapshot) -> [String: [UsageHistorySample]] {
        lock.lock()
        defer { lock.unlock() }
        let cutoff = snapshot.updatedAt.addingTimeInterval(-UsageHistory.retention)
        histories = histories.compactMapValues { samples in
            let retained = samples.filter { $0.observedAt >= cutoff }
            return retained.isEmpty ? nil : retained
        }
        for limit in snapshot.limits {
            for window in limit.windows where window.windowDurationMins == 7 * 24 * 60 {
                let key = UsagePaceTracker.key(limitID: limit.limitID, window: window)
                histories[key] = UsageHistory.recording(
                    histories[key] ?? [], remainingPercent: window.remainingPercent,
                    observedAt: snapshot.updatedAt, resetsAt: window.resetsAt
                )
            }
        }
        if let encoded = try? JSONEncoder().encode(histories) { defaults.set(encoded, forKey: storageKey) }
        return histories
    }
}
