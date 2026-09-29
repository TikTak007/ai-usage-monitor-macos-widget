import Foundation
import XCTest
@testable import CodexUsageCore

final class UsageHistoryTests: XCTestCase {
    let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    func testThreeMinuteWeekRetainsAll3360Observations() throws {
        var history: [UsageHistorySample] = []
        let reset = epoch.addingTimeInterval(7 * 24 * 3600)
        for index in 0..<3360 {
            history = UsageHistory.recording(history, remainingPercent: 100 - index * 100 / 3360,
                observedAt: epoch.addingTimeInterval(Double(index * 180)), resetsAt: reset)
        }
        XCTAssertEqual(history.count, 3360)
        XCTAssertEqual(history.first?.observedAt, epoch)
        let data = try JSONEncoder().encode(history)
        XCTAssertEqual(try JSONDecoder().decode([UsageHistorySample].self, from: data), history)
        XCTAssertLessThan(data.count, 1_000_000)
    }

    func testIrregularResetAndMissingObservationStartSeparatePaths() {
        let reset = epoch.addingTimeInterval(5000)
        var history = UsageHistory.recording([], remainingPercent: 4, observedAt: epoch, resetsAt: reset)
        history = UsageHistory.recording(history, remainingPercent: 100,
            observedAt: epoch.addingTimeInterval(180), resetsAt: reset.addingTimeInterval(1000))
        history = UsageHistory.recording(history, remainingPercent: 90,
            observedAt: epoch.addingTimeInterval(1080), resetsAt: reset.addingTimeInterval(1000))
        XCTAssertEqual(history.map(\.segment), [0, 1, 2])
        XCTAssertEqual(history.map(\.remainingPercent), [4, 100, 90])
    }

    func testDuplicateOrOlderSamplesDoNotRewriteHistory() {
        let history = UsageHistory.recording([], remainingPercent: 40, observedAt: epoch, resetsAt: nil)
        XCTAssertEqual(UsageHistory.recording(history, remainingPercent: 1, observedAt: epoch, resetsAt: nil), history)
        XCTAssertEqual(UsageHistory.recording(history, remainingPercent: 1,
            observedAt: epoch.addingTimeInterval(-1), resetsAt: nil), history)
    }

    func testRetentionAndRapidManualRefreshAreBounded() {
        var history = UsageHistory.recording([], remainingPercent: 50, observedAt: epoch, resetsAt: nil)
        history = UsageHistory.recording(history, remainingPercent: 49,
            observedAt: epoch.addingTimeInterval(10), resetsAt: nil)
        XCTAssertEqual(history.count, 1)
        history = UsageHistory.recording(history, remainingPercent: 40,
            observedAt: epoch.addingTimeInterval(UsageHistory.retention + 180), resetsAt: nil)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.last?.remainingPercent, 40)
    }

    func testDrawingReductionPreservesExtremaLatestAndSegmentsWithoutChangingStoredData() {
        var samples: [UsageHistorySample] = []
        for index in 0..<3360 {
            let remaining: Int = index == 1600 ? 0 : (index == 1601 ? 100 : 50)
            let date = epoch.addingTimeInterval(Double(index) * 180)
            samples.append(UsageHistorySample(observedAt: date, remainingPercent: remaining,
                                             resetsAt: nil, segment: index < 1601 ? 0 : 1))
        }
        let drawing = UsageHistory.drawingSamples(samples)
        XCTAssertLessThanOrEqual(drawing.count, 600)
        XCTAssertEqual(drawing.first, samples.first)
        XCTAssertEqual(drawing.last, samples.last)
        XCTAssertTrue(drawing.contains(samples[1600]))
        XCTAssertTrue(drawing.contains(samples[1601]))
        XCTAssertEqual(samples.count, 3360)
        XCTAssertEqual(drawing, drawing.sorted { $0.observedAt < $1.observedAt })
    }
    func testMissingCycleMetadataAndRecoveryNeverConnectSeparateCycles() {
        let reset = epoch.addingTimeInterval(5_000)
        var history = UsageHistory.recording([], remainingPercent: 30, observedAt: epoch, resetsAt: reset)
        history = UsageHistory.recording(history, remainingPercent: 100,
            observedAt: epoch.addingTimeInterval(180), resetsAt: nil)
        history = UsageHistory.recording(history, remainingPercent: 99,
            observedAt: epoch.addingTimeInterval(360), resetsAt: reset.addingTimeInterval(4_000))
        XCTAssertEqual(history.map(\.segment), [0, 1, 2])
        var unchanged = UsageHistory.recording([], remainingPercent: 30, observedAt: epoch, resetsAt: reset)
        unchanged = UsageHistory.recording(unchanged, remainingPercent: 30,
            observedAt: epoch.addingTimeInterval(180), resetsAt: nil)
        unchanged = UsageHistory.recording(unchanged, remainingPercent: 29,
            observedAt: epoch.addingTimeInterval(360), resetsAt: reset)
        XCTAssertEqual(unchanged.map(\.segment), [0, 0, 0])
    }

    func testChartAlwaysShowsOneSevenDayCycleBeforeAndAfterReset() {
        let nextReset = epoch.addingTimeInterval(UsageHistory.retention)
        for elapsed: TimeInterval in [0, 180, 3 * 24 * 3600, UsageHistory.retention - 180] {
            let now = epoch.addingTimeInterval(elapsed)
            let range = UsageHistory.chartDomain(observedAt: now, resetsAt: nextReset)
            XCTAssertEqual(range.lowerBound, epoch)
            XCTAssertEqual(range.upperBound, nextReset)
            XCTAssertEqual(range.upperBound.timeIntervalSince(range.lowerBound), UsageHistory.retention)
            XCTAssertTrue(range.contains(now))
        }
        let advanced = UsageHistory.chartDomain(observedAt: nextReset.addingTimeInterval(180),
            resetsAt: nextReset.addingTimeInterval(UsageHistory.retention))
        XCTAssertEqual(advanced.lowerBound, nextReset)
        XCTAssertEqual(advanced.upperBound.timeIntervalSince(advanced.lowerBound), UsageHistory.retention)
    }

    func testUnknownExpiredOrDistantResetFallsBackToSevenDayHistory() {
        for reset in [nil, epoch.addingTimeInterval(-1), epoch,
                      epoch.addingTimeInterval(UsageHistory.retention + 180)] {
            let range = UsageHistory.chartDomain(observedAt: epoch, resetsAt: reset)
            XCTAssertEqual(range.upperBound, epoch)
            XCTAssertEqual(range.lowerBound, epoch.addingTimeInterval(-UsageHistory.retention))
        }
    }

    func testChartStartsAtResetAndConnectsFirstNinetyPercentObservation() {
        let reset = epoch.addingTimeInterval(UsageHistory.retention)
        let observed = epoch.addingTimeInterval(3600)
        let history = [UsageHistorySample(observedAt: observed, remainingPercent: 90,
                                          resetsAt: reset)]
        let points = UsageHistory.chartPoints(history, remainingPercent: 90,
                                              observedAt: observed, resetsAt: reset)
        XCTAssertEqual(points.map(\.remainingPercent), [100, 90])
        XCTAssertEqual(points.map(\.observedAt), [epoch, observed])
        XCTAssertEqual(points.map(\.lightFromPrevious), [false, true])
        XCTAssertEqual(history.count, 1, "The drawing origin must not be recorded")
    }

    func testChartConnectsSixMinuteAndLongGapsButKeepsContinuousEdgesNormal() {
        let reset = epoch.addingTimeInterval(UsageHistory.retention)
        let times: [TimeInterval] = [180, 360, 720, 900, 2 * 24 * 3600]
        let history = zip(times, [99, 98, 97, 96, 65]).map { offset, value in
            UsageHistorySample(observedAt: epoch.addingTimeInterval(offset),
                               remainingPercent: value, resetsAt: reset)
        }
        let points = UsageHistory.chartPoints(history, remainingPercent: 65,
            observedAt: epoch.addingTimeInterval(2 * 24 * 3600), resetsAt: reset)
        XCTAssertEqual(points.map(\.remainingPercent), [100, 99, 98, 97, 96, 65])
        XCTAssertEqual(points.map(\.lightFromPrevious), [false, true, false, true, false, true])
    }

    func testChartClassifiesGapsBeforeReducingThreeMinuteHistory() {
        let reset = epoch.addingTimeInterval(UsageHistory.retention)
        let history = (0..<3360).map { index in
            UsageHistorySample(observedAt: epoch.addingTimeInterval(Double(index * 180)),
                               remainingPercent: 100 - index * 100 / 3360, resetsAt: reset)
        }
        let points = UsageHistory.chartPoints(history, remainingPercent: 1,
            observedAt: history.last!.observedAt, resetsAt: reset, maximumPoints: 200)
        XCTAssertLessThanOrEqual(points.count, 200)
        XCTAssertEqual(points.last?.remainingPercent, 1)
        XCTAssertTrue(points.allSatisfy { !$0.lightFromPrevious })
    }

    func testChartUsesOnlyCurrentCycleAndDoesNotInventOriginWithoutReset() {
        let nextReset = epoch.addingTimeInterval(UsageHistory.retention)
        let oldReset = epoch.addingTimeInterval(3600)
        let old = UsageHistorySample(observedAt: epoch.addingTimeInterval(180),
                                     remainingPercent: 20, resetsAt: oldReset)
        let current = UsageHistorySample(observedAt: epoch.addingTimeInterval(7200),
                                         remainingPercent: 90, resetsAt: nextReset)
        let now = current.observedAt
        let currentPoints = UsageHistory.chartPoints([old, current], remainingPercent: 90,
                                                      observedAt: now, resetsAt: nextReset)
        XCTAssertEqual(currentPoints.map(\.remainingPercent), [100, 90])
        let unknownPoints = UsageHistory.chartPoints([current], remainingPercent: 90,
                                                      observedAt: now, resetsAt: nil)
        XCTAssertEqual(unknownPoints.map(\.remainingPercent), [90])
    }

    func testChartCanStartFromCurrentValueAloneAndKeepHorizontalMissingGap() {
        let reset = epoch.addingTimeInterval(UsageHistory.retention)
        let first = epoch.addingTimeInterval(180)
        let now = epoch.addingTimeInterval(3 * 24 * 3600)
        let onlyCurrent = UsageHistory.chartPoints([], remainingPercent: 90,
            observedAt: first, resetsAt: reset)
        XCTAssertEqual(onlyCurrent.map(\.remainingPercent), [100, 90])
        XCTAssertEqual(onlyCurrent.map(\.lightFromPrevious), [false, true])

        let flat = UsageHistory.chartPoints([
            UsageHistorySample(observedAt: first, remainingPercent: 65, resetsAt: reset)
        ], remainingPercent: 65, observedAt: now, resetsAt: reset)
        XCTAssertEqual(flat.map(\.remainingPercent), [100, 65, 65])
        XCTAssertEqual(flat.map(\.lightFromPrevious), [false, true, true])
    }

    func testChartExcludesUnknownOldCycleButRetainsUnknownAfterMatchingReset() {
        let reset = epoch.addingTimeInterval(UsageHistory.retention)
        let oldUnknown = UsageHistorySample(observedAt: epoch.addingTimeInterval(86400),
                                            remainingPercent: 20, resetsAt: nil)
        let current = UsageHistorySample(observedAt: epoch.addingTimeInterval(2 * 86400),
                                         remainingPercent: 90, resetsAt: reset)
        let currentUnknown = UsageHistorySample(observedAt: current.observedAt.addingTimeInterval(180),
                                                remainingPercent: 89, resetsAt: nil)
        let points = UsageHistory.chartPoints([oldUnknown, current, currentUnknown],
            remainingPercent: 89, observedAt: currentUnknown.observedAt, resetsAt: reset)
        XCTAssertEqual(points.map(\.remainingPercent), [100, 90, 89])
        XCTAssertFalse(points.contains { $0.remainingPercent == 20 })
    }

    func testChartSpreadsReducedPointsAcrossWeekAndRetainsLateExtrema() {
        let reset = epoch.addingTimeInterval(UsageHistory.retention)
        var samples: [UsageHistorySample] = []
        for index in 0..<120 where index != 4 && index != 9 {
            let value = index == 90 ? 0 : (index == 100 ? 100 : 50)
            samples.append(UsageHistorySample(
                observedAt: epoch.addingTimeInterval(Double(index * 180)),
                remainingPercent: value, resetsAt: reset))
        }
        let points = UsageHistory.chartPoints(samples, remainingPercent: 50,
            observedAt: samples.last!.observedAt, resetsAt: reset, maximumPoints: 10)
        XCTAssertLessThanOrEqual(points.count, 10)
        XCTAssertTrue(points.contains { $0.observedAt == epoch.addingTimeInterval(90 * 180) })
        XCTAssertTrue(points.contains { $0.observedAt == epoch.addingTimeInterval(100 * 180) })
        XCTAssertEqual(points.last?.remainingPercent, 50)
    }

    func testTwoPointLimitIncludesOriginAndLatest() {
        let reset = epoch.addingTimeInterval(UsageHistory.retention)
        let now = epoch.addingTimeInterval(86400)
        let points = UsageHistory.chartPoints([], remainingPercent: 90,
            observedAt: now, resetsAt: reset, maximumPoints: 2)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.map(\.remainingPercent), [100, 90])
    }

    func testOverfullGapBoundariesStillRetainLateExtrema() {
        let reset = epoch.addingTimeInterval(UsageHistory.retention)
        var samples: [UsageHistorySample] = []
        for index in 1..<200 where index % 4 != 0 {
            let value = index == 170 ? 0 : (index == 181 ? 100 : 50)
            samples.append(UsageHistorySample(
                observedAt: epoch.addingTimeInterval(Double(index * 180)),
                remainingPercent: value, resetsAt: reset))
        }
        let points = UsageHistory.chartPoints(samples, remainingPercent: 50,
            observedAt: samples.last!.observedAt, resetsAt: reset, maximumPoints: 20)
        XCTAssertLessThanOrEqual(points.count, 20)
        XCTAssertTrue(points.contains { $0.observedAt == epoch.addingTimeInterval(170 * 180) })
        XCTAssertTrue(points.contains { $0.observedAt == epoch.addingTimeInterval(181 * 180) })
        XCTAssertEqual(points.last?.observedAt, samples.last?.observedAt)
    }

}
