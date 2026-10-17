import Foundation

/// The returned Codex credit balance, separate from quota percentages and reset vouchers.
public enum UsageCreditBalance: Equatable, Sendable {
    case amount(Decimal)
    case unlimited

    public func formattedAmount(locale: Locale = .current) -> String {
        switch self {
        case .unlimited:
            return "Unlimited"
        case .amount(let balance):
            var value = balance
            var rounded = Decimal()
            NSDecimalRound(&rounded, &value, 0, .plain)
            return rounded.formatted(
                .number.precision(.fractionLength(0)).locale(locale)
            )
        }
    }
}
