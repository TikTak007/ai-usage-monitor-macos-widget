import Foundation
import XCTest
import CodexUsageShared
@testable import CodexUsageCore

final class WidgetGraphTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func graph(reset: Date?, predicted: Date?, points: [WidgetHistoryPoint] = []) -> WidgetWeeklyGraph {
        WidgetWeeklyGraph(id: "weekly", name: "Synthetic", remainingPercent: 42,
            resetsAt: reset, exhaustionDate: predicted, points: points)
    }

    func testLegacySnapshotAndNewSnapshotRoundTrip() throws {
        let legacy = Data("{\"limits\":[],\"updatedAt\":0}".utf8)
        XCTAssertNil(try WidgetSnapshotCodec.decode(legacy).weeklyGraphs)
        let reset = now.addingTimeInterval(3 * 24 * 3600)
        let item = graph(reset: reset, predicted: now.addingTimeInterval(24 * 3600),
            points: [WidgetHistoryPoint(observedAt: now, remainingPercent: 42, segment: 1)])
        let snapshot = WidgetUsageSnapshot(limits: [], updatedAt: now, weeklyGraphs: [item])
        let encoded = try WidgetSnapshotCodec.encode(snapshot)
        XCTAssertEqual(try WidgetSnapshotCodec.decode(encoded), snapshot)
        let json = String(decoding: encoded, as: UTF8.self)
        for forbidden in ["accessToken", "refreshToken", "accountId", "email", "auth.json"] {
            XCTAssertFalse(json.contains(forbidden))
        }
        XCTAssertNotEqual(WidgetUsageConstants.widgetKind, WidgetUsageConstants.graphWidgetKind)
    }

    func testCycleAndHoverFreePayloadExcludePastAndFutureHistory() {
        let reset = now.addingTimeInterval(3 * 24 * 3600)
        let points = [-5, -4, -1, 0, 1].map { days in
            WidgetHistoryPoint(observedAt: now.addingTimeInterval(Double(days) * 24 * 3600),
                remainingPercent: 42, segment: days < 0 ? 0 : 1)
        }
        let item = graph(reset: reset, predicted: nil, points: points)
        let range = item.domain(observedAt: now)
        XCTAssertEqual(range.upperBound.timeIntervalSince(range.lowerBound), WidgetWeeklyGraph.duration)
        XCTAssertEqual(item.visiblePoints(observedAt: now).map(\.observedAt), Array(points[1...3]).map(\.observedAt))
    }

    func testForecastNeverExtendsOutsideSevenDaysOrAfterReset() {
        let reset = now.addingTimeInterval(24 * 3600)
        let valid = now.addingTimeInterval(3600)
        XCTAssertEqual(graph(reset: reset, predicted: valid).forecastDate(observedAt: now), valid)
        for predicted in [now, now.addingTimeInterval(-1), reset, reset.addingTimeInterval(1)] {
            XCTAssertNil(graph(reset: reset, predicted: predicted).forecastDate(observedAt: now))
        }
        for invalidReset in [nil, now, now.addingTimeInterval(-1), now.addingTimeInterval(WidgetWeeklyGraph.duration + 1)] {
            let item = graph(reset: invalidReset, predicted: valid)
            XCTAssertNil(item.forecastDate(observedAt: now))
            XCTAssertEqual(item.domain(observedAt: now).upperBound, now)
        }
    }

    func testThreeMinuteWeekPublishesAtMost200DrawingPointsRetainingLatestAndExtrema() {
        var source: [UsageHistorySample] = []
        for index in 0..<3360 {
            let date = now.addingTimeInterval(Double(index - 3359) * 180)
            let percent = index == 1200 ? 0 : (index == 1201 ? 100 : 42)
            source.append(UsageHistorySample(observedAt: date, remainingPercent: percent,
                resetsAt: now.addingTimeInterval(180), segment: index < 1201 ? 0 : 1))
        }
        let reduced = UsageHistory.drawingSamples(source, maximumPoints: WidgetWeeklyGraph.maximumDrawingPoints)
        XCTAssertLessThanOrEqual(reduced.count, 200)
        XCTAssertEqual(reduced.last, source.last)
        XCTAssertTrue(reduced.contains(source[1200]))
        XCTAssertTrue(reduced.contains(source[1201]))
        XCTAssertEqual(source.count, 3360)
    }

    func testStrokeRunsShareBoundaryPointsWithoutBreakingLine() throws {
        let points = [
            WidgetHistoryPoint(observedAt: now, remainingPercent: 100, segment: 0,
                               lightFromPrevious: false),
            WidgetHistoryPoint(observedAt: now.addingTimeInterval(3600), remainingPercent: 90,
                               segment: 0, lightFromPrevious: true),
            WidgetHistoryPoint(observedAt: now.addingTimeInterval(3780), remainingPercent: 89,
                               segment: 0, lightFromPrevious: false),
            WidgetHistoryPoint(observedAt: now.addingTimeInterval(7200), remainingPercent: 65,
                               segment: 0, lightFromPrevious: true),
        ]
        let runs = WidgetGraphDrawing.strokeRuns(points)
        XCTAssertEqual(runs.map(\.light), [true, false, true])
        XCTAssertEqual(runs.map { $0.points.map(\.observedAt) },
                       [[points[0].observedAt, points[1].observedAt],
                        [points[1].observedAt, points[2].observedAt],
                        [points[2].observedAt, points[3].observedAt]])
        let encoded = try JSONEncoder().encode(points)
        XCTAssertEqual(try JSONDecoder().decode([WidgetHistoryPoint].self, from: encoded), points)
    }

    func testLegacyPointWithoutConnectionStyleStillDecodes() throws {
        let legacy = Data("{\"observedAt\":0,\"remainingPercent\":65,\"segment\":1}".utf8)
        let point = try JSONDecoder().decode(WidgetHistoryPoint.self, from: legacy)
        XCTAssertNil(point.lightFromPrevious)
        let later = WidgetHistoryPoint(observedAt: point.observedAt.addingTimeInterval(360),
                                       remainingPercent: 65, segment: 2)
        XCTAssertEqual(WidgetGraphDrawing.strokeRuns([point, later]).map(\.light), [true])
        let reducedNormal = WidgetHistoryPoint(observedAt: point.observedAt.addingTimeInterval(3600),
                                               remainingPercent: 64, segment: 1)
        XCTAssertEqual(WidgetGraphDrawing.strokeRuns([point, reducedNormal]).map(\.light), [false])
    }
}
