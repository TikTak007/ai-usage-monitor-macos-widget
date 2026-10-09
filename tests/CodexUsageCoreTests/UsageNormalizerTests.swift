import AppKit
import XCTest
@testable import CodexUsageCore
@testable import CodexUsageShared

final class UsageNormalizerTests: XCTestCase {
    func testNormalizesAllBucketsAndDynamicWindows() throws {
        let payload = try json(
            """
            {
              "rateLimits": {
                "limitId": "codex",
                "primary": {"usedPercent": 99, "windowDurationMins": 300, "resetsAt": 1},
                "secondary": null
              },
              "rateLimitsByLimitId": {
                "codex_bengalfox": {
                  "limitId": "codex_bengalfox",
                  "limitName": "GPT-5.3-Codex-Spark",
                  "planType": "pro",
                  "primary": {"usedPercent": 8, "windowDurationMins": 180, "resetsAt": 2},
                  "secondary": null,
                  "rateLimitReachedType": null,
                  "spendControlReached": false
                },
                "codex": {
                  "limitId": "codex",
                  "limitName": null,
                  "planType": "pro",
                  "primary": {"usedPercent": 12, "windowDurationMins": 10080, "resetsAt": 3},
                  "secondary": null,
                  "rateLimitReachedType": null,
                  "spendControlReached": null
                }
              }
            }
            """
        )

        let snapshot = try UsageNormalizer.normalize(
            payload,
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(snapshot.limits.map(\.limitID), ["codex", "codex_bengalfox"])
        XCTAssertEqual(snapshot.limits[0].windows[0].label, "Weekly (7-day)")
        XCTAssertEqual(snapshot.limits[0].windows[0].remainingPercent, 88)
        XCTAssertEqual(snapshot.limits[1].displayName, "GPT-5.3-Codex-Spark")
        XCTAssertEqual(snapshot.limits[1].windows[0].label, "3-hour")
    }

    func testPreservesUnknownAndNullDurations() throws {
        let payload = try json(
            """
            {
              "rateLimits": {
                "limitId": "codex",
                "primary": {"usedPercent": 10, "windowDurationMins": 90, "resetsAt": null},
                "secondary": {"usedPercent": 20, "windowDurationMins": null, "resetsAt": null}
              }
            }
            """
        )

        let snapshot = try UsageNormalizer.normalize(payload)

        XCTAssertEqual(snapshot.limits[0].windows[0].label, "90-minute")
        XCTAssertEqual(snapshot.limits[0].windows[1].label, "Duration unavailable")
    }

    func testNormalizesResetCreditCountAndNearestExpirationWithoutKeepingOpaqueID() throws {
        let payload = try json(
            """
            {
              "rateLimits": {
                "limitId": "codex",
                "primary": {"usedPercent": 10, "windowDurationMins": 10080, "resetsAt": 99}
              },
              "rateLimitResetCredits": {
                "availableCount": 2,
                "credits": [
                  {
                    "id": "opaque-credit-one",
                    "resetType": "codexRateLimits",
                    "status": "available",
                    "grantedAt": 10,
                    "expiresAt": 300,
                    "title": "Full reset",
                    "description": "Ready to redeem"
                  },
                  {
                    "id": "opaque-credit-two",
                    "resetType": "futureResetType",
                    "status": "futureStatus",
                    "grantedAt": 20,
                    "expiresAt": 200,
                    "title": null,
                    "description": null
                  }
                ]
              }
            }
            """
        )

        let snapshot = try UsageNormalizer.normalize(payload)
        let summary = try XCTUnwrap(snapshot.resetCredits)

        XCTAssertEqual(summary.availableCount, 2)
        XCTAssertEqual(summary.credits?.count, 2)
        XCTAssertEqual(summary.nearestExpiration, Date(timeIntervalSince1970: 200))
        XCTAssertFalse(String(describing: summary).contains("opaque-credit"))
    }

    func testDistinguishesCountOnlyResetCreditSummaryFromNoSummary() throws {
        let base = """
        {"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":10080}}}
        """
        let missing = try UsageNormalizer.normalize(try json(base))
        XCTAssertNil(missing.resetCredits)

        let countOnly = try UsageNormalizer.normalize(
            try json(
                """
                {
                  "rateLimits": {"primary":{"usedPercent":10,"windowDurationMins":10080}},
                  "rateLimitResetCredits": {"availableCount":1,"credits":null}
                }
                """
            )
        )
        XCTAssertEqual(countOnly.resetCredits?.availableCount, 1)
        XCTAssertNil(countOnly.resetCredits?.credits)
    }

    func testRejectsInvalidResetCreditSummary() throws {
        let payload = try json(
            """
            {
              "rateLimits": {"primary":{"usedPercent":10,"windowDurationMins":10080}},
              "rateLimitResetCredits": {"availableCount":-1,"credits":[]}
            }
            """
        )

        XCTAssertThrowsError(try UsageNormalizer.normalize(payload))
    }

    func testRejectsInvalidPercentage() throws {
        let payload = try json(
            """
            {"rateLimits":{"primary":{"usedPercent":101,"windowDurationMins":300}}}
            """
        )

        XCTAssertThrowsError(try UsageNormalizer.normalize(payload))
    }

    func testWindowLabels() {
        XCTAssertEqual(UsageNormalizer.windowLabel(durationMins: 180), "3-hour")
        XCTAssertEqual(UsageNormalizer.windowLabel(durationMins: 300), "5-hour")
        XCTAssertEqual(UsageNormalizer.windowLabel(durationMins: 10_080), "Weekly (7-day)")
        XCTAssertEqual(UsageNormalizer.windowLabel(durationMins: 60), "1-hour")
        XCTAssertEqual(UsageNormalizer.windowLabel(durationMins: 1_440), "1-day")
        XCTAssertEqual(UsageNormalizer.windowLabel(durationMins: 45), "45-minute")
    }

    func testThresholdPolicyDoesNotNotifyOnFirstObservation() {
        XCTAssertNil(
            UsageThresholdPolicy.crossedThreshold(
                previous: nil,
                remainingPercent: 33,
                resetsAt: Date(timeIntervalSince1970: 100)
            )
        )
    }

    func testThresholdPolicyReturnsLowestBoundaryCrossed() {
        let previous = UsageThresholdCheckpoint(
            remainingPercent: 95,
            resetsAt: 100
        )

        XCTAssertEqual(
            UsageThresholdPolicy.crossedThreshold(
                previous: previous,
                remainingPercent: 75,
                resetsAt: Date(timeIntervalSince1970: 100)
            ),
            80
        )
    }

    func testThresholdPolicyDoesNotRepeatWithinBoundary() {
        let previous = UsageThresholdCheckpoint(
            remainingPercent: 79,
            resetsAt: 100
        )

        XCTAssertNil(
            UsageThresholdPolicy.crossedThreshold(
                previous: previous,
                remainingPercent: 76,
                resetsAt: Date(timeIntervalSince1970: 100)
            )
        )
    }

    func testThresholdPolicyRebaselinesAfterReset() {
        let previous = UsageThresholdCheckpoint(
            remainingPercent: 12,
            resetsAt: 100
        )

        XCTAssertNil(
            UsageThresholdPolicy.crossedThreshold(
                previous: previous,
                remainingPercent: 9,
                resetsAt: Date(timeIntervalSince1970: 200)
            )
        )
    }

    func testPaceEstimatorProjectsExhaustionBeforeReset() throws {
        let baselineDate = Date(timeIntervalSince1970: 1_000)
        let resetDate = baselineDate.addingTimeInterval(24 * 60 * 60)
        let first = UsagePaceEstimator.update(
            history: nil,
            usedPercent: 20,
            observedAt: baselineDate,
            resetsAt: resetDate
        )

        XCTAssertNil(first.estimate)

        let currentDate = baselineDate.addingTimeInterval(2 * 60 * 60)
        let second = UsagePaceEstimator.update(
            history: first.history,
            usedPercent: 30,
            observedAt: currentDate,
            resetsAt: resetDate
        )

        let estimate = try XCTUnwrap(second.estimate)
        XCTAssertEqual(estimate.usedPercentPerHour, 5, accuracy: 0.001)
        XCTAssertEqual(
            estimate.exhaustionDate.timeIntervalSince1970,
            baselineDate.addingTimeInterval(16 * 60 * 60).timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testPaceEstimatorOmitsPredictionAfterReset() {
        let baselineDate = Date(timeIntervalSince1970: 1_000)
        let resetDate = baselineDate.addingTimeInterval(6 * 60 * 60)
        let first = UsagePaceEstimator.update(
            history: nil,
            usedPercent: 20,
            observedAt: baselineDate,
            resetsAt: resetDate
        )
        let second = UsagePaceEstimator.update(
            history: first.history,
            usedPercent: 21,
            observedAt: baselineDate.addingTimeInterval(2 * 60 * 60),
            resetsAt: resetDate
        )

        XCTAssertNil(second.estimate)
    }

    func testPaceEstimatorWaitsForEnoughObservationTime() {
        let baselineDate = Date(timeIntervalSince1970: 1_000)
        let resetDate = baselineDate.addingTimeInterval(24 * 60 * 60)
        let first = UsagePaceEstimator.update(
            history: nil,
            usedPercent: 20,
            observedAt: baselineDate,
            resetsAt: resetDate
        )
        let second = UsagePaceEstimator.update(
            history: first.history,
            usedPercent: 30,
            observedAt: baselineDate.addingTimeInterval(5 * 60),
            resetsAt: resetDate
        )

        XCTAssertNil(second.estimate)
    }

    func testPaceEstimatorCarriesCumulativeConsumptionAcrossReset() throws {
        let baselineDate = Date(timeIntervalSince1970: 1_000)
        let oldResetDate = baselineDate.addingTimeInterval(30 * 60)
        let first = UsagePaceEstimator.update(
            history: nil,
            usedPercent: 70,
            observedAt: baselineDate,
            resetsAt: oldResetDate,
            windowDurationMins: 300
        )
        let beforeReset = UsagePaceEstimator.update(
            history: first.history,
            usedPercent: 80,
            observedAt: baselineDate.addingTimeInterval(30 * 60),
            resetsAt: oldResetDate,
            windowDurationMins: 300
        )
        let newResetDate = oldResetDate.addingTimeInterval(5 * 60 * 60)
        let afterReset = UsagePaceEstimator.update(
            history: beforeReset.history,
            usedPercent: 3,
            observedAt: baselineDate.addingTimeInterval(60 * 60),
            resetsAt: newResetDate,
            windowDurationMins: 300
        )

        XCTAssertEqual(beforeReset.history.cumulativeUsedPercent, 10, accuracy: 0.001)
        XCTAssertEqual(afterReset.history.cumulativeUsedPercent, 13, accuracy: 0.001)
        XCTAssertEqual(afterReset.history.latestUsedPercent, 3)
        XCTAssertEqual(afterReset.history.latestResetsAt, newResetDate.timeIntervalSince1970)
        XCTAssertGreaterThan(
            try XCTUnwrap(afterReset.history.longTermUsedPercentPerHour),
            0
        )
    }

    func testPaceEstimatorIgnoresSmallDownwardCorrection() {
        let baselineDate = Date(timeIntervalSince1970: 1_000)
        let resetDate = baselineDate.addingTimeInterval(24 * 60 * 60)
        let first = UsagePaceEstimator.update(
            history: nil,
            usedPercent: 40,
            observedAt: baselineDate,
            resetsAt: resetDate
        )
        let increase = UsagePaceEstimator.update(
            history: first.history,
            usedPercent: 42,
            observedAt: baselineDate.addingTimeInterval(30 * 60),
            resetsAt: resetDate
        )
        let correction = UsagePaceEstimator.update(
            history: increase.history,
            usedPercent: 41,
            observedAt: baselineDate.addingTimeInterval(60 * 60),
            resetsAt: resetDate
        )
        let rebound = UsagePaceEstimator.update(
            history: correction.history,
            usedPercent: 42,
            observedAt: baselineDate.addingTimeInterval(90 * 60),
            resetsAt: resetDate
        )

        XCTAssertEqual(increase.history.cumulativeUsedPercent, 2, accuracy: 0.001)
        XCTAssertEqual(correction.history.cumulativeUsedPercent, 2, accuracy: 0.001)
        XCTAssertEqual(rebound.history.cumulativeUsedPercent, 2, accuracy: 0.001)
        XCTAssertEqual(correction.history.latestUsedPercent, 41)
    }

    func testPaceEstimatorDetectsLargeResetWithoutTimestamp() {
        let baselineDate = Date(timeIntervalSince1970: 1_000)
        let first = UsagePaceEstimator.update(
            history: nil,
            usedPercent: 85,
            observedAt: baselineDate,
            resetsAt: nil
        )
        let reset = UsagePaceEstimator.update(
            history: first.history,
            usedPercent: 4,
            observedAt: baselineDate.addingTimeInterval(30 * 60),
            resetsAt: nil
        )

        XCTAssertEqual(reset.history.cumulativeUsedPercent, 4, accuracy: 0.001)
    }

    func testPaceEstimatorLongIdleGapDecaysRate() throws {
        let baselineDate = Date(timeIntervalSince1970: 1_000)
        let resetDate = baselineDate.addingTimeInterval(7 * 24 * 60 * 60)
        let first = UsagePaceEstimator.update(
            history: nil,
            usedPercent: 20,
            observedAt: baselineDate,
            resetsAt: resetDate,
            windowDurationMins: 300
        )
        let active = UsagePaceEstimator.update(
            history: first.history,
            usedPercent: 30,
            observedAt: baselineDate.addingTimeInterval(60 * 60),
            resetsAt: resetDate,
            windowDurationMins: 300
        )
        let idle = UsagePaceEstimator.update(
            history: active.history,
            usedPercent: 30,
            observedAt: baselineDate.addingTimeInterval(25 * 60 * 60),
            resetsAt: resetDate,
            windowDurationMins: 300
        )

        let activeRate = try XCTUnwrap(active.history.longTermUsedPercentPerHour)
        let idleRate = try XCTUnwrap(idle.history.longTermUsedPercentPerHour)
        XCTAssertLessThan(idleRate, activeRate * 0.001)
    }

    func testPaceEstimatorBoundsRecentHistory() {
        let baselineDate = Date(timeIntervalSince1970: 1_000)
        let resetDate = baselineDate.addingTimeInterval(14 * 24 * 60 * 60)
        var history: UsagePaceHistory?

        for index in 0..<200 {
            history = UsagePaceEstimator.update(
                history: history,
                usedPercent: min(index / 5, 99),
                observedAt: baselineDate.addingTimeInterval(Double(index) * 3 * 60),
                resetsAt: resetDate,
                windowDurationMins: 10_080
            ).history
        }

        XCTAssertLessThanOrEqual(
            history?.recentSamples.count ?? Int.max,
            UsagePaceEstimator.maximumSampleCount
        )
    }

    func testPaceEstimatorUsesAdaptiveWindows() {
        XCTAssertEqual(UsagePaceEstimator.shortHorizon(windowDurationMins: 300), 30 * 60)
        XCTAssertEqual(UsagePaceEstimator.shortHorizon(windowDurationMins: 10_080), 3 * 60 * 60)
        XCTAssertEqual(UsagePaceEstimator.longTermHalfLife(windowDurationMins: 300), 2 * 60 * 60)
        XCTAssertEqual(UsagePaceEstimator.longTermHalfLife(windowDurationMins: 10_080), 24 * 60 * 60)
    }

    func testWidgetSnapshotRoundTripsWithoutCredentials() throws {
        let snapshot = WidgetUsageSnapshot(
            limits: [
                WidgetUsageLimit(
                    id: "codex",
                    name: "Codex",
                    windows: [
                        WidgetUsageWindow(
                            label: "3-hour",
                            remainingPercent: 40,
                            usedPercent: 60,
                            resetsAt: Date(timeIntervalSince1970: 123)
                        )
                    ]
                )
            ],
            resetCredits: WidgetResetCreditsSummary(
                availableCount: 1,
                nearestExpiration: Date(timeIntervalSince1970: 456),
                detailsAvailable: true
            ),
            appearanceMode: AppearanceMode.dark.rawValue,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let data = try WidgetSnapshotCodec.encode(snapshot)
        XCTAssertEqual(try WidgetSnapshotCodec.decode(data), snapshot)
        let keys = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        ).keys
        XCTAssertEqual(
            Set(keys),
            ["limits", "resetCredits", "appearanceMode", "updatedAt"]
        )
    }

    func testAppearanceModeFallsBackToSystem() {
        XCTAssertEqual(AppearanceMode(storedValue: nil), .system)
        XCTAssertEqual(AppearanceMode(storedValue: "future"), .system)
        XCTAssertEqual(AppearanceMode(storedValue: "light"), .light)
        XCTAssertEqual(AppearanceMode(storedValue: "dark"), .dark)
    }

    func testAppearanceModeMapsToWindowAppearance() {
        XCTAssertNil(AppearanceMode.system.nsAppearance)
        XCTAssertEqual(AppearanceMode.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(AppearanceMode.dark.nsAppearance?.name, .darkAqua)
    }

    private func json(_ text: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try XCTUnwrap(object as? [String: Any])
    }
}
