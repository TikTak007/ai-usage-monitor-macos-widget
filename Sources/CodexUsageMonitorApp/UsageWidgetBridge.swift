import CodexUsageCore
import CodexUsageShared
import WidgetKit

enum UsageWidgetBridge {
    static func publish(_ snapshot: UsageSnapshot, histories: [String: [UsageHistorySample]],
                        estimates: [String: UsagePaceEstimate]) {
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
            updatedAt: snapshot.updatedAt,
            weeklyGraphs: snapshot.limits.flatMap { limit in
                limit.windows.filter { $0.windowDurationMins == 7 * 24 * 60 }.map { window in
                    let key = UsagePaceTracker.key(limitID: limit.limitID, window: window)
                    let domain = UsageHistory.chartDomain(observedAt: snapshot.updatedAt, resetsAt: window.resetsAt)
                    let history = (histories[key] ?? []).filter {
                        domain.contains($0.observedAt) && $0.observedAt <= snapshot.updatedAt
                    }
                    return WidgetWeeklyGraph(
                        id: key, name: limit.displayName, remainingPercent: window.remainingPercent,
                        resetsAt: window.resetsAt, exhaustionDate: estimates[key]?.exhaustionDate,
                        points: UsageHistory.chartPoints(
                            history, remainingPercent: window.remainingPercent,
                            observedAt: snapshot.updatedAt, resetsAt: window.resetsAt,
                            maximumPoints: WidgetWeeklyGraph.maximumDrawingPoints
                        ).map { WidgetHistoryPoint(observedAt: $0.observedAt,
                            remainingPercent: $0.remainingPercent, segment: 0,
                            lightFromPrevious: $0.lightFromPrevious) }
                    )
                }
            }
        )

        WidgetSnapshotServer.shared.publish(shared)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetUsageConstants.widgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetUsageConstants.graphWidgetKind)
    }
}
