import CodexUsageCore
import CodexUsageShared
import WidgetKit

enum UsageWidgetBridge {
    static func publish(_ snapshot: UsageSnapshot) {
        let shared = WidgetUsageSnapshot(
            limits: snapshot.limits.map { limit in
                WidgetUsageLimit(
                    id: limit.limitID,
                    name: limit.displayName,
                    windows: limit.windows.map { window in
                        WidgetUsageWindow(
                            label: window.label,
                            remainingPercent: window.remainingPercent,
                            usedPercent: window.usedPercent,
                            resetsAt: window.resetsAt
                        )
                    }
                )
            },
            resetCredits: snapshot.resetCredits.map { summary in
                WidgetResetCreditsSummary(
                    availableCount: summary.availableCount,
                    nearestExpiration: summary.nearestExpiration,
                    detailsAvailable: summary.credits != nil
                )
            },
            appearanceMode: UserDefaults.standard.string(forKey: "appearanceMode"),
            updatedAt: snapshot.updatedAt
        )

        WidgetSnapshotServer.shared.publish(shared)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetUsageConstants.widgetKind)
    }
}
