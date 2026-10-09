import CodexUsageCore
import Foundation

final class UsagePaceTracker {
    static let shared = UsagePaceTracker()

    private let defaults: UserDefaults
    private let storageKey = "usagePaceHistories.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func process(_ snapshot: UsageSnapshot) -> [String: UsagePaceEstimate] {
        let storedHistories = loadHistories()
        var currentHistories: [String: UsagePaceHistory] = [:]
        var estimates: [String: UsagePaceEstimate] = [:]

        for limit in snapshot.limits {
            for window in limit.windows {
                let key = Self.key(limitID: limit.limitID, window: window)
                let update = UsagePaceEstimator.update(
                    history: storedHistories[key],
                    usedPercent: window.usedPercent,
                    observedAt: snapshot.updatedAt,
                    resetsAt: window.resetsAt,
                    windowDurationMins: window.windowDurationMins
                )
                currentHistories[key] = update.history
                estimates[key] = update.estimate
            }
        }

        save(currentHistories)
        return estimates
    }

    static func key(limitID: String, window: UsageWindow) -> String {
        "\(limitID)|\(window.source)|\(window.windowDurationMins ?? -1)"
    }

    private func loadHistories() -> [String: UsagePaceHistory] {
        guard let data = defaults.data(forKey: storageKey),
              let histories = try? JSONDecoder().decode(
                [String: UsagePaceHistory].self,
                from: data
              )
        else {
            return [:]
        }
        return histories
    }

    private func save(_ histories: [String: UsagePaceHistory]) {
        guard let data = try? JSONEncoder().encode(histories) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
