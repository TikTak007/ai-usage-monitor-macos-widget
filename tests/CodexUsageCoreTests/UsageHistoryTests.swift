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

}
