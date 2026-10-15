import CodexUsageCore
import SwiftUI

struct CreditsBalanceCard: View {
    let balance: UsageCreditBalance?
    let isStale: Bool

    private var valueColor: Color {
        guard let balance else { return .secondary }
        if case .amount(let value) = balance, value == .zero { return .orange }
        return .primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Credits remaining")
                    .font(.headline)
                Spacer()
                Text("Codex")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(balance?.formattedAmount() ?? "Unavailable")
                    .font(.system(size: balance == nil ? 23 : 30, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if case .amount? = balance {
                    Text("credits")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if isStale {
                Text(balance == nil ? "Update failed" : "Update failed · Showing last balance")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if balance == nil {
                Text("Credit balance was not returned")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.opacity(0.68), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
    }
}
