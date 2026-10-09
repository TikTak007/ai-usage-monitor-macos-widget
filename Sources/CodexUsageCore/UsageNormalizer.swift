import CoreFoundation
import Foundation

public enum UsageNormalizationError: LocalizedError, Equatable {
    case noSnapshots
    case invalidField(String)

    public var errorDescription: String? {
        switch self {
        case .noSnapshots:
            return "Codex did not return any usable rate-limit snapshots."
        case .invalidField(let field):
            return "Codex returned an invalid value for \(field)."
        }
    }
}

public enum UsageNormalizer {
    public static func normalize(
        _ payload: [String: Any],
        now: Date = Date()
    ) throws -> UsageSnapshot {
        let limits = try parseLimits(payload).sorted(by: limitSort)
        guard !limits.isEmpty else {
            throw UsageNormalizationError.noSnapshots
        }
        return UsageSnapshot(
            limits: limits,
            resetCredits: try parseResetCredits(payload["rateLimitResetCredits"]),
            updatedAt: now
        )
    }

    public static func windowLabel(durationMins: Int?) -> String {
        guard let durationMins else { return "Duration unavailable" }
        switch durationMins {
        case 180:
            return "3-hour"
        case 300:
            return "5-hour"
        case 10_080:
            return "Weekly (7-day)"
        default:
            if durationMins.isMultiple(of: 24 * 60) {
                return "\(durationMins / (24 * 60))-day"
            }
            if durationMins.isMultiple(of: 60) {
                return "\(durationMins / 60)-hour"
            }
            return "\(durationMins)-minute"
        }
    }

    private static func parseLimits(_ payload: [String: Any]) throws -> [UsageLimit] {
        if let byID = payload["rateLimitsByLimitId"] as? [String: Any], !byID.isEmpty {
            return try byID.map { mapKey, value in
                guard let snapshot = value as? [String: Any] else {
                    throw UsageNormalizationError.invalidField(
                        "rateLimitsByLimitId.\(mapKey)"
                    )
                }
                return try parseLimit(mapKey: mapKey, snapshot: snapshot)
            }
        }

        guard let historical = payload["rateLimits"] as? [String: Any] else {
            return []
        }
        let fallbackID = nonemptyString(historical["limitId"]) ?? "codex"
        return [try parseLimit(mapKey: fallbackID, snapshot: historical)]
    }

    private static func parseResetCredits(_ value: Any?) throws -> UsageResetCreditsSummary? {
        guard let value, !(value is NSNull) else { return nil }
        guard let raw = value as? [String: Any] else {
            throw UsageNormalizationError.invalidField("rateLimitResetCredits")
        }
        guard let availableCount = integer(raw["availableCount"]), availableCount >= 0 else {
            throw UsageNormalizationError.invalidField(
                "rateLimitResetCredits.availableCount"
            )
        }

        let credits: [UsageResetCredit]?
        if raw["credits"] == nil || raw["credits"] is NSNull {
            credits = nil
        } else if let rows = raw["credits"] as? [Any] {
            credits = try rows.enumerated().map { index, value in
                try parseResetCredit(value, index: index)
            }
        } else {
            throw UsageNormalizationError.invalidField("rateLimitResetCredits.credits")
        }

        return UsageResetCreditsSummary(
            availableCount: availableCount,
            credits: credits
        )
    }

    private static func parseResetCredit(_ value: Any, index: Int) throws -> UsageResetCredit {
        let field = "rateLimitResetCredits.credits[\(index)]"
        guard let raw = value as? [String: Any] else {
            throw UsageNormalizationError.invalidField(field)
        }
        guard nonemptyString(raw["id"]) != nil else {
            throw UsageNormalizationError.invalidField("\(field).id")
        }
        guard let status = nonemptyString(raw["status"]) else {
            throw UsageNormalizationError.invalidField("\(field).status")
        }
        guard let resetType = nonemptyString(raw["resetType"]) else {
            throw UsageNormalizationError.invalidField("\(field).resetType")
        }

        return UsageResetCredit(
            grantedAt: try optionalDate(raw["grantedAt"], field: "\(field).grantedAt"),
            expiresAt: try optionalDate(raw["expiresAt"], field: "\(field).expiresAt"),
            status: status,
            resetType: resetType,
            title: try optionalNonemptyString(raw["title"], field: "\(field).title"),
            description: try optionalNonemptyString(
                raw["description"],
                field: "\(field).description"
            )
        )
    }

    private static func parseLimit(
        mapKey: String,
        snapshot: [String: Any]
    ) throws -> UsageLimit {
        let limitID = nonemptyString(snapshot["limitId"]) ?? mapKey
        let limitName = nonemptyString(snapshot["limitName"])
        let planType = try optionalString(snapshot["planType"], field: "\(limitID).planType")
        let reachedType = try optionalString(
            snapshot["rateLimitReachedType"],
            field: "\(limitID).rateLimitReachedType"
        )
        let spendControlReached = try optionalBool(
            snapshot["spendControlReached"],
            field: "\(limitID).spendControlReached"
        )

        var windows: [UsageWindow] = []
        for source in ["primary", "secondary"] {
            guard let value = snapshot[source], !(value is NSNull) else { continue }
            guard let rawWindow = value as? [String: Any] else {
                throw UsageNormalizationError.invalidField("\(limitID).\(source)")
            }
            windows.append(
                try parseWindow(source: source, raw: rawWindow, limitID: limitID)
            )
        }

        return UsageLimit(
            limitID: limitID,
            displayName: limitName ?? (limitID == "codex" ? "Codex" : "Additional limit"),
            planType: planType,
            rateLimitReachedType: reachedType,
            spendControlReached: spendControlReached,
            windows: windows
        )
    }

    private static func parseWindow(
        source: String,
        raw: [String: Any],
        limitID: String
    ) throws -> UsageWindow {
        guard let used = integer(raw["usedPercent"]), (0...100).contains(used) else {
            throw UsageNormalizationError.invalidField(
                "\(limitID).\(source).usedPercent"
            )
        }

        let duration: Int?
        if raw["windowDurationMins"] == nil || raw["windowDurationMins"] is NSNull {
            duration = nil
        } else if let value = integer(raw["windowDurationMins"]), value > 0 {
            duration = value
        } else {
            throw UsageNormalizationError.invalidField(
                "\(limitID).\(source).windowDurationMins"
            )
        }

        let resetsAt: Date?
        if raw["resetsAt"] == nil || raw["resetsAt"] is NSNull {
            resetsAt = nil
        } else if let value = integer(raw["resetsAt"]) {
            resetsAt = Date(timeIntervalSince1970: TimeInterval(value))
        } else {
            throw UsageNormalizationError.invalidField(
                "\(limitID).\(source).resetsAt"
            )
        }

        return UsageWindow(
            source: source,
            label: windowLabel(durationMins: duration),
            usedPercent: used,
            remainingPercent: 100 - used,
            windowDurationMins: duration,
            resetsAt: resetsAt
        )
    }

    private static func limitSort(_ lhs: UsageLimit, _ rhs: UsageLimit) -> Bool {
        if lhs.limitID == "codex", rhs.limitID != "codex" { return true }
        if rhs.limitID == "codex", lhs.limitID != "codex" { return false }
        let nameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.limitID < rhs.limitID
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }
        let double = number.doubleValue
        guard double.isFinite,
              double.rounded() == double,
              double >= Double(Int.min),
              double <= Double(Int.max)
        else {
            return nil
        }
        return Int(double)
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func optionalString(_ value: Any?, field: String) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let string = value as? String else {
            throw UsageNormalizationError.invalidField(field)
        }
        return string
    }

    private static func optionalNonemptyString(_ value: Any?, field: String) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let string = value as? String else {
            throw UsageNormalizationError.invalidField(field)
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func optionalDate(_ value: Any?, field: String) throws -> Date? {
        guard let value, !(value is NSNull) else { return nil }
        guard let timestamp = integer(value), timestamp >= 0 else {
            throw UsageNormalizationError.invalidField(field)
        }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    private static func optionalBool(_ value: Any?, field: String) throws -> Bool? {
        guard let value, !(value is NSNull) else { return nil }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID()
        else {
            throw UsageNormalizationError.invalidField(field)
        }
        return number.boolValue
    }
}
