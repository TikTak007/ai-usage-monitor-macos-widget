import CodexUsageCore
import Foundation
import UserNotifications

final class UsageNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = UsageNotificationManager()

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let checkpointsKey = "usageNotificationCheckpoints.v1"
    private let resetCheckpointsKey = "usageResetNotificationCheckpoints.v1"

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.center = center
        self.defaults = defaults
        super.init()
        center.delegate = self
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            guard let self else {
                completion(false)
                return
            }
            self.refreshAuthorizationStatus(completion: completion)
        }
    }

    func refreshAuthorizationStatus(completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion(true)
            default:
                completion(false)
            }
        }
    }

    func process(_ snapshot: UsageSnapshot) {
        let previous = loadCheckpoints()
        var current: [String: UsageThresholdCheckpoint] = [:]
        var events: [(limit: UsageLimit, window: UsageWindow, threshold: Int)] = []
        var resetCheckpoints = UsageResetPolicy.prune(
            loadResetCheckpoints(), observedAt: snapshot.updatedAt
        )
        var resetEvents: [(limit: UsageLimit, window: UsageWindow)] = []

        for limit in snapshot.limits {
            for window in limit.windows {
                let key = checkpointKey(limit: limit, window: window)
                let resetResult = UsageResetPolicy.update(
                    previous: resetCheckpoints[key],
                    remainingPercent: window.remainingPercent,
                    resetsAt: window.resetsAt,
                    observedAt: snapshot.updatedAt
                )
                resetCheckpoints[key] = resetResult.checkpoint
                if resetResult.resetConfirmed {
                    resetEvents.append((limit, window))
                }
                if let threshold = UsageThresholdPolicy.crossedThreshold(
                    previous: previous[key],
                    remainingPercent: window.remainingPercent,
                    resetsAt: window.resetsAt
                ) {
                    events.append((limit, window, threshold))
                }
                current[key] = UsageThresholdPolicy.checkpoint(
                    remainingPercent: window.remainingPercent,
                    resetsAt: window.resetsAt
                )
            }
        }

        saveCheckpoints(current)
        saveResetCheckpoints(resetCheckpoints)
        for event in resetEvents {
            scheduleResetNotification(limit: event.limit, window: event.window)
        }
        for event in events {
            scheduleNotification(
                limit: event.limit,
                window: event.window,
                threshold: event.threshold
            )
        }
    }

    private func checkpointKey(limit: UsageLimit, window: UsageWindow) -> String {
        "\(limit.limitID)|\(window.source)|\(window.windowDurationMins ?? -1)"
    }

    private func loadCheckpoints() -> [String: UsageThresholdCheckpoint] {
        guard let data = defaults.data(forKey: checkpointsKey),
              let value = try? JSONDecoder().decode(
                  [String: UsageThresholdCheckpoint].self,
                  from: data
              )
        else {
            return [:]
        }
        return value
    }

    private func saveCheckpoints(_ checkpoints: [String: UsageThresholdCheckpoint]) {
        guard let data = try? JSONEncoder().encode(checkpoints) else { return }
        defaults.set(data, forKey: checkpointsKey)
    }

    private func scheduleNotification(
        limit: UsageLimit,
        window: UsageWindow,
        threshold: Int
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Codex remaining usage is at or below \(threshold)%"
        content.body = "\(limit.displayName) / \(window.label): \(window.remainingPercent)% remaining"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "usage-\(limit.limitID)-\(window.source)-\(threshold)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    private func loadResetCheckpoints() -> [String: UsageResetCheckpoint] {
        guard let data = defaults.data(forKey: resetCheckpointsKey),
              let value = try? JSONDecoder().decode(
                  [String: UsageResetCheckpoint].self, from: data
              )
        else { return [:] }
        return value
    }

    private func saveResetCheckpoints(_ checkpoints: [String: UsageResetCheckpoint]) {
        guard let data = try? JSONEncoder().encode(checkpoints) else { return }
        defaults.set(data, forKey: resetCheckpointsKey)
    }

    private func scheduleResetNotification(limit: UsageLimit, window: UsageWindow) {
        let content = UNMutableNotificationContent()
        content.title = "Codex usage limit has reset"
        content.body = "\(limit.displayName) / \(window.label): \(window.remainingPercent)% remaining"
        content.sound = .default
        let cycle = window.resetsAt?.timeIntervalSince1970 ?? 0
        let request = UNNotificationRequest(
            identifier: "usage-reset-\(checkpointKey(limit: limit, window: window))-\(cycle)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
