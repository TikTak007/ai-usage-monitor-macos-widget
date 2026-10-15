import XCTest
@testable import CodexUsageCore

final class UsageCreditBalanceTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    func testNormalizesExactDecimalBalanceAndRemovesInsignificantZeros() throws {
        let snapshot = try normalize(["hasCredits": true, "unlimited": false, "balance": "42420.1250000000"])
        XCTAssertEqual(snapshot.creditBalance, .amount(Decimal(string: "42420.125")!))
        XCTAssertEqual(snapshot.creditBalance?.formattedAmount(locale: locale), "42,420.125")
        XCTAssertEqual(snapshot.limits.first?.windows.first?.remainingPercent, 76)
    }

    func testZeroIsARealBalanceEvenWhenHasCreditsIsFalse() throws {
        let snapshot = try normalize(["hasCredits": false, "unlimited": false, "balance": "0.0000000000"])
        XCTAssertEqual(snapshot.creditBalance, .amount(.zero))
        XCTAssertEqual(snapshot.creditBalance?.formattedAmount(locale: locale), "0")
    }

    func testMissingBalanceDoesNotBecomeZero() throws {
        for value: Any? in [nil, NSNull(), ["hasCredits": false, "unlimited": false],
                               ["hasCredits": false, "unlimited": false, "balance": NSNull()]] {
            XCTAssertNil(try normalize(value).creditBalance)
        }
    }

    func testUnlimitedTakesPrecedenceOverNumericOrMissingBalance() throws {
        for value: Any in [NSNull(), "0", "42420"] {
            let snapshot = try normalize(["hasCredits": true, "unlimited": true, "balance": value])
            XCTAssertEqual(snapshot.creditBalance, .unlimited)
            XCTAssertEqual(snapshot.creditBalance?.formattedAmount(locale: locale), "Unlimited")
        }
    }

    func testInvalidOptionalCreditMetadataDoesNotHideQuotaWindows() throws {
        let invalid: [Any] = [
            "invalid", true, ["hasCredits": true, "unlimited": 1, "balance": "42"],
            ["hasCredits": 1, "unlimited": false, "balance": "42"],
            ["hasCredits": true, "unlimited": false, "balance": true],
            ["hasCredits": true, "unlimited": false, "balance": 42],
            ["hasCredits": true, "unlimited": false, "balance": "42credits"],
            ["hasCredits": true, "unlimited": false, "balance": "NaN"],
            ["hasCredits": true, "unlimited": false, "balance": "Infinity"],
            ["hasCredits": true, "unlimited": false, "balance": "42,420"],
            ["hasCredits": true, "unlimited": false, "balance": ""]
        ]
        for value in invalid {
            let snapshot = try normalize(value)
            XCTAssertNil(snapshot.creditBalance)
            XCTAssertEqual(snapshot.limits.first?.windows.first?.remainingPercent, 76)
        }
    }

    func testTinyFractionDoesNotDisplayAsZero() throws {
        let balance = try normalize(["hasCredits": true, "unlimited": false, "balance": "0.0000000001"])
        XCTAssertEqual(balance.creditBalance?.formattedAmount(locale: locale), "0.0000000001")
    }

    func testBalanceDoesNotPassThroughBinaryFloatingPoint() throws {
        let snapshot = try normalize(["hasCredits": true, "unlimited": false, "balance": "9007199254740993.125"])
        XCTAssertEqual(snapshot.creditBalance?.formattedAmount(locale: locale), "9,007,199,254,740,993.125")
    }

    func testFormattingUsesTheRequestedLocale() {
        XCTAssertEqual(UsageCreditBalance.amount(Decimal(string: "42420.5")!)
            .formattedAmount(locale: Locale(identifier: "de_DE")), "42.420,5")
    }

    func testMapIsAuthoritativeAndDoesNotBorrowLegacyCredits() throws {
        let old = bucket(credits: ["hasCredits": true, "unlimited": false, "balance": "42420"])
        let snapshot = try UsageNormalizer.normalize([
            "rateLimits": old,
            "rateLimitsByLimitId": ["codex": bucket(credits: nil)]
        ])
        XCTAssertNil(snapshot.creditBalance)
    }

    func testLegacyBucketIsSupportedWhenMapIsAbsent() throws {
        let snapshot = try normalize(["hasCredits": true, "unlimited": false, "balance": "42420"])
        XCTAssertEqual(snapshot.creditBalance?.formattedAmount(locale: locale), "42,420")
    }

    func testAdditionalBucketsAreNotAddedOrSubstitutedForCodex() throws {
        let credits: [String: Any] = ["hasCredits": true, "unlimited": false, "balance": "42420"]
        var additional = bucket(credits: credits)
        additional["limitId"] = "additional"
        let missing = try UsageNormalizer.normalize(["rateLimitsByLimitId": ["additional": additional]])
        XCTAssertNil(missing.creditBalance)
        let snapshot = try UsageNormalizer.normalize(["rateLimitsByLimitId": [
            "additional": additional, "codex": bucket(credits: credits)
        ]])
        XCTAssertEqual(snapshot.creditBalance, .amount(42420))
    }

    func testAbsentCreditsPreserveExistingSnapshotConstruction() {
        XCTAssertNil(UsageSnapshot(limits: [], updatedAt: Date()).creditBalance)
    }

    func testCreditBalanceAndBankedResetsCoexist() throws {
        let snapshot = try UsageNormalizer.normalize([
            "rateLimits": bucket(credits: ["hasCredits": true, "unlimited": false, "balance": "42420.5"]),
            "rateLimitResetCredits": ["availableCount": 2, "credits": [
                ["id": "synthetic-reset", "status": "available", "resetType": "codexRateLimits", "expiresAt": 1900000000]
            ]]
        ])
        XCTAssertEqual(snapshot.creditBalance, .amount(Decimal(string: "42420.5")!))
        XCTAssertEqual(snapshot.resetCredits?.availableCount, 2)
        XCTAssertEqual(snapshot.resetCredits?.credits?.count, 1)
    }

    private func normalize(_ credits: Any?) throws -> UsageSnapshot {
        try UsageNormalizer.normalize(["rateLimits": bucket(credits: credits)])
    }

    private func bucket(credits: Any?) -> [String: Any] {
        var value: [String: Any] = [
            "limitId": "codex",
            "primary": ["usedPercent": 24, "windowDurationMins": 10080, "resetsAt": 1800000000]
        ]
        if let credits { value["credits"] = credits }
        return value
    }
}
