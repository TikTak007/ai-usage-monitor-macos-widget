import Foundation
import XCTest
@testable import CodexUsageCore

final class UsageResetPolicyTests: XCTestCase {
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func update(
        _ previous: UsageResetCheckpoint?, remaining: Int, reset: TimeInterval?, at: TimeInterval
    ) -> (checkpoint: UsageResetCheckpoint?, resetConfirmed: Bool) {
        UsageResetPolicy.update(
            previous: previous, remainingPercent: remaining,
            resetsAt: reset.map(date), observedAt: date(at)
        )
    }

    func testFirstObservationOnlyEstablishesBaseline() {
        let result = update(nil, remaining: 100, reset: 2_000, at: 1_000)
        XCTAssertFalse(result.resetConfirmed)
        XCTAssertEqual(result.checkpoint?.remainingPercent, 100)
    }

    func testScheduledResetRequiresAdvancedAuthoritativeFutureCycle() {
        let old = update(nil, remaining: 8, reset: 2_000, at: 1_900).checkpoint
        XCTAssertFalse(update(old, remaining: 100, reset: 2_000, at: 2_001).resetConfirmed)
        XCTAssertFalse(update(old, remaining: 100, reset: nil, at: 2_001).resetConfirmed)
        XCTAssertFalse(update(old, remaining: 100, reset: 2_061, at: 2_100).resetConfirmed)
        let result = update(old, remaining: 94, reset: 7_000, at: 2_001)
        XCTAssertTrue(result.resetConfirmed)
        XCTAssertEqual(result.checkpoint?.lastNotifiedResetsAt, 7_000)
    }

    func testEarlyResetRequiresLargeRecoveryAndNewerTimestamp() {
        let old = update(nil, remaining: 30, reset: 5_000, at: 1_000).checkpoint
        XCTAssertTrue(update(old, remaining: 100, reset: 9_000, at: 1_100).resetConfirmed)
        XCTAssertFalse(update(old, remaining: 100, reset: 5_000, at: 1_100).resetConfirmed)
        XCTAssertFalse(update(old, remaining: 100, reset: nil, at: 1_100).resetConfirmed)
        XCTAssertFalse(update(old, remaining: 100, reset: 4_000, at: 1_100).resetConfirmed)
    }

    func testMetadataRevisionsAndSmallCorrectionsAreNotResets() {
        let old = update(nil, remaining: 88, reset: 5_000, at: 1_000).checkpoint
        XCTAssertFalse(update(old, remaining: 88, reset: 9_000, at: 1_100).resetConfirmed)
        XCTAssertFalse(update(old, remaining: 95, reset: 9_000, at: 1_100).resetConfirmed)
        let depleted = update(nil, remaining: 20, reset: 5_000, at: 1_000).checkpoint
        XCTAssertFalse(update(depleted, remaining: 70, reset: 9_000, at: 1_100).resetConfirmed)
        XCTAssertFalse(update(depleted, remaining: 100, reset: 5_030, at: 1_100).resetConfirmed)
    }

    func testRepeatedAndOutOfOrderObservationsDoNotDuplicateOrReplaceCheckpoint() {
        let old = update(nil, remaining: 10, reset: 2_000, at: 1_900).checkpoint
        let reset = update(old, remaining: 100, reset: 7_000, at: 2_001)
        XCTAssertTrue(reset.resetConfirmed)
        let duplicate = update(reset.checkpoint, remaining: 100, reset: 7_000, at: 2_001)
        XCTAssertFalse(duplicate.resetConfirmed)
        XCTAssertEqual(duplicate.checkpoint, reset.checkpoint)
        let stale = update(reset.checkpoint, remaining: 0, reset: 2_000, at: 1_950)
        XCTAssertFalse(stale.resetConfirmed)
        XCTAssertEqual(stale.checkpoint, reset.checkpoint)
        XCTAssertFalse(update(reset.checkpoint, remaining: 100, reset: 7_000, at: 2_100).resetConfirmed)
    }

    func testMissingMetadataDoesNotClaimResetOrEraseKnownCycle() {
        let old = update(nil, remaining: 10, reset: 5_000, at: 1_000).checkpoint
        let absent = update(old, remaining: 100, reset: nil, at: 1_100)
        XCTAssertFalse(absent.resetConfirmed)
        XCTAssertEqual(absent.checkpoint?.resetsAt, 5_000)
        let unknown = update(nil, remaining: 10, reset: nil, at: 1_000).checkpoint
        XCTAssertFalse(update(unknown, remaining: 100, reset: 9_000, at: 1_100).resetConfirmed)
    }

    func testBackwardTimestampRevisionCannotManufactureScheduledReset() {
        let old = update(nil, remaining: 88, reset: 5_000, at: 1_000).checkpoint
        let revised = update(old, remaining: 88, reset: 1_200, at: 1_100)
        XCTAssertFalse(revised.resetConfirmed)
        XCTAssertEqual(revised.checkpoint?.resetsAt, 5_000)
        XCTAssertFalse(update(revised.checkpoint, remaining: 90, reset: 5_000, at: 1_300).resetConfirmed)
    }

    func testAbsentBucketsArePreservedUntilRetentionExpires() throws {
        let checkpoint = try XCTUnwrap(update(nil, remaining: 10, reset: 5_000, at: 1_000).checkpoint)
        let store = ["weekly": checkpoint]
        XCTAssertEqual(UsageResetPolicy.prune(store, observedAt: date(2_000)), store)
        XCTAssertEqual(UsageResetPolicy.prune(store, observedAt: date(1_000 + UsageResetPolicy.retentionInterval)), store)
        XCTAssertTrue(UsageResetPolicy.prune(store, observedAt: date(1_001 + UsageResetPolicy.retentionInterval)).isEmpty)
        XCTAssertEqual(UsageResetPolicy.prune(store, observedAt: date(900)), store)
    }

    func testCodableRestartRetainsNotificationDeduplication() throws {
        let old = update(nil, remaining: 10, reset: 2_000, at: 1_900).checkpoint
        let confirmed = try XCTUnwrap(update(old, remaining: 100, reset: 7_000, at: 2_001).checkpoint)
        let data = try JSONEncoder().encode(["weekly": confirmed])
        let restored = try JSONDecoder().decode([String: UsageResetCheckpoint].self, from: data)
        XCTAssertEqual(restored["weekly"], confirmed)
        XCTAssertFalse(update(restored["weekly"], remaining: 100, reset: 7_000, at: 2_100).resetConfirmed)
        let earlierSchema = Data("{\"remainingPercent\":30,\"resetsAt\":5000,\"observedAt\":1000}".utf8)
        let decoded = try JSONDecoder().decode(UsageResetCheckpoint.self, from: earlierSchema)
        XCTAssertNil(decoded.lastNotifiedResetsAt)
    }

    func testCheckpointNormalizesRemainingPercentage() {
        XCTAssertEqual(update(nil, remaining: 120, reset: nil, at: 1_000).checkpoint?.remainingPercent, 100)
        XCTAssertEqual(update(nil, remaining: -5, reset: nil, at: 1_000).checkpoint?.remainingPercent, 0)
    }
}
