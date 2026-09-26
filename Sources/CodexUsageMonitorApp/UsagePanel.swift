import AppKit
import CodexUsageCore
import CodexUsageShared
import SwiftUI

struct UsagePanel: View {
    @ObservedObject var model: UsageViewModel
    @AppStorage("appearanceMode") private var appearanceRawValue = AppearanceMode.system.rawValue
    @State private var measuredContentHeight: CGFloat = 0

    private let minimumPanelHeight: CGFloat = 220
    private let panelChromeHeight: CGFloat = 112

    private var maximumPanelHeight: CGFloat {
        let availableHeight = NSScreen.main?.visibleFrame.height ?? 620
        return min(680, max(420, availableHeight - 16))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 360, height: panelHeight)
        .background(.regularMaterial)
        .background(PanelWindowAppearance(mode: appearanceMode))
        .preferredColorScheme(appearanceMode.colorScheme)
        .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
            guard height > 0, abs(height - measuredContentHeight) > 0.5 else { return }
            measuredContentHeight = height
        }
        .onChange(of: appearanceRawValue) { _ in
            model.publishCurrentSnapshot()
        }
        .animation(.easeInOut(duration: 0.16), value: panelHeight)
    }

    private var header: some View {
        HStack(spacing: 10) {
            UsageMonitorIcon(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Usage Monitor")
                    .font(.headline)
                connectionLabel
            }
            Spacer()
            Menu {
                Picker("Appearance", selection: $appearanceRawValue) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Appearance")
            .accessibilityLabel("Appearance")
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.isRefreshing)
            .help("Refresh usage")
            .accessibilityLabel("Refresh usage")
        }
        .padding(14)
    }

    @ViewBuilder
    private var connectionLabel: some View {
        switch model.state {
        case .idle:
            Label("Waiting", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .loading:
            Label("Updating", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Label("Unavailable", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = model.snapshot {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ResetCreditsCard(summary: snapshot.resetCredits)
                    ForEach(Array(snapshot.limits.prefix(2))) { limit in
                        LimitCard(limit: limit, paceEstimates: model.paceEstimates,
                                  weeklyHistories: model.weeklyHistories, observedAt: snapshot.updatedAt)
                    }
                    ForEach(Array(snapshot.limits.dropFirst(2))) { limit in
                        LimitCard(limit: limit, paceEstimates: model.paceEstimates,
                                  weeklyHistories: model.weeklyHistories, observedAt: snapshot.updatedAt)
                    }
                    if case .failed(let message) = model.state {
                        ErrorBanner(message: message)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ContentHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                }
            }
        } else if case .failed(let message) = model.state {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Try Again") { model.refresh() }
            }
            .padding(24)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("Reading limits from Codex…")
                    .foregroundStyle(.secondary)
            }
            .padding(30)
        }
    }

    private var panelHeight: CGFloat {
        let contentHeight = measuredContentHeight > 0
            ? measuredContentHeight
            : estimatedContentHeight
        return min(
            maximumPanelHeight,
            max(minimumPanelHeight, panelChromeHeight + contentHeight)
        )
    }

    private var estimatedContentHeight: CGFloat {
        guard let snapshot = model.snapshot else { return minimumPanelHeight - panelChromeHeight }

        let cardHeight = snapshot.limits.reduce(CGFloat.zero) { total, limit in
            let windowCount = max(limit.windows.count, 1)
            let additionalWindows = CGFloat(max(windowCount - 1, 0)) * 66
            let alertHeight: CGFloat = (
                limit.rateLimitReachedType != nil || limit.spendControlReached == true
            ) ? 31 : 0
            let chartHeight: CGFloat = limit.windows.contains { $0.windowDurationMins == 7 * 24 * 60 } ? 205 : 0
            return total + 106 + additionalWindows + alertHeight + chartHeight
        }
        let resetCreditsHeight: CGFloat = 66 + CGFloat(max((snapshot.resetCredits?.credits?.count ?? 1) - 1, 0)) * 18

        let hasErrorBanner: Bool
        if case .failed = model.state {
            hasErrorBanner = true
        } else {
            hasErrorBanner = false
        }
        let itemCount = snapshot.limits.count + 1 + (hasErrorBanner ? 1 : 0)
        let spacing = CGFloat(max(itemCount - 1, 0)) * 10
        let errorBannerHeight: CGFloat = hasErrorBanner ? 44 : 0
        return 20 + cardHeight + resetCreditsHeight + spacing + errorBannerHeight
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let updatedAt = model.snapshot?.updatedAt {
                    Text("Updated \(Formatters.updated.string(from: updatedAt))")
                } else {
                    Text("Not updated yet")
                }
                notificationStatus
            }
            .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var notificationStatus: some View {
        switch model.notificationsEnabled {
        case true:
            Label("Usage alerts and reset notifications", systemImage: "bell.fill")
        case false:
            Label("Notifications disabled", systemImage: "bell.slash")
                .foregroundStyle(.orange)
        case nil:
            Label("Checking notifications", systemImage: "bell")
        }
    }

    private var appearanceMode: AppearanceMode {
        AppearanceMode(storedValue: appearanceRawValue)
    }
}

private struct PanelWindowAppearance: NSViewRepresentable {
    let mode: AppearanceMode

    func makeNSView(context: Context) -> PanelAppearanceView {
        let view = PanelAppearanceView()
        view.mode = mode
        return view
    }

    func updateNSView(_ nsView: PanelAppearanceView, context: Context) {
        nsView.mode = mode
    }
}

private final class PanelAppearanceView: NSView {
    var mode = AppearanceMode.system {
        didSet { applyAppearance() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAppearance()
    }

    private func applyAppearance() {
        window?.appearance = mode.nsAppearance
    }
}

private struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct LimitCard: View {
    let limit: UsageLimit
    let paceEstimates: [String: UsagePaceEstimate]
    let weeklyHistories: [String: [UsageHistorySample]]
    let observedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.displayName)
                    .font(.headline)
                Spacer()
                if let plan = limit.planType {
                    Text(plan.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }

            if limit.windows.isEmpty {
                Label("Limits unavailable", systemImage: "minus.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(limit.windows) { window in
                    WindowRow(
                        window: window,
                        paceEstimate: paceEstimates[
                            UsagePaceTracker.key(limitID: limit.limitID, window: window)
                        ]
                    )
                    if window.id != limit.windows.last?.id {
                        Divider()
                    }
                }
            }

            ForEach(limit.windows.filter { $0.windowDurationMins == 7 * 24 * 60 }) { window in
                WeeklyUsageChart(
                    samples: weeklyHistories[UsagePaceTracker.key(limitID: limit.limitID, window: window)] ?? [],
                    window: window,
                    estimate: paceEstimates[UsagePaceTracker.key(limitID: limit.limitID, window: window)],
                    observedAt: observedAt
                )
            }

            if let reached = limit.rateLimitReachedType {
                Label("Limit reached: \(reached)", systemImage: "exclamationmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if limit.spendControlReached == true {
                Label("Spend control reached", systemImage: "exclamationmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(.background.opacity(0.68), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.45), lineWidth: 0.5)
        }
    }
}

private struct WindowRow: View {
    let window: UsageWindow
    let paceEstimate: UsagePaceEstimate?

    var body: some View {
        HStack(spacing: 12) {
            Gauge(value: Double(window.remainingPercent), in: 0...100) {
                Text(window.label)
            } currentValueLabel: {
                Text("\(window.remainingPercent)%")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(gaugeColor)
            .frame(width: 54, height: 54)
            .accessibilityLabel("\(window.label) remaining")
            .accessibilityValue("\(window.remainingPercent) percent")

            VStack(alignment: .leading, spacing: 2) {
                Text(window.label)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 12) {
                    Text("Remaining \(window.remainingPercent)%")
                    Text("Used \(window.usedPercent)%")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                TimelineView(.periodic(from: .now, by: 60)) { context in
                    HStack(spacing: 8) {
                        Text(resetDescription)
                        Text(timeRemaining(now: context.date))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let paceEstimate {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(paceDescription(paceEstimate))
                        Text(
                            "Projected empty \(Formatters.projected.string(from: paceEstimate.exhaustionDate))"
                        )
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var gaugeColor: Color {
        if window.remainingPercent > 50 { return .green }
        if window.remainingPercent > 20 { return .orange }
        return .red
    }

    private var resetDescription: String {
        guard let reset = window.resetsAt else { return "Reset unavailable" }
        return "Reset \(Formatters.reset.string(from: reset))"
    }

    private func timeRemaining(now: Date) -> String {
        guard let reset = window.resetsAt else { return "Remaining time unavailable" }
        let totalMinutes = max(0, Int(reset.timeIntervalSince(now)) / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "Resets in \(days)d \(hours)h \(minutes)m" }
        return "Resets in \(hours)h \(minutes)m"
    }

    private func paceDescription(_ estimate: UsagePaceEstimate) -> String {
        let useDailyRate = (window.windowDurationMins ?? 0) >= 24 * 60
        let rate = useDailyRate
            ? estimate.usedPercentPerHour * 24
            : estimate.usedPercentPerHour
        let unit = useDailyRate ? "day" : "hour"
        let format = rate < 0.1 ? "%.2f" : "%.1f"
        let formattedRate = String(format: format, rate)
        return "Pace \(formattedRate)%/\(unit)"
    }
}

private struct ResetCreditsCard: View {
    let summary: UsageResetCreditsSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Label("Banked resets", systemImage: "arrow.counterclockwise.circle.fill")
                    .font(.headline)
                    .foregroundStyle(accentColor)
                Spacer()
                countBadge
            }

            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    if let summary, summary.availableCount > 0,
                       let credits = summary.credits, !credits.isEmpty {
                        let sorted = credits.sorted {
                            ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture)
                        }
                        ForEach(Array(sorted.enumerated()), id: \.offset) { index, credit in
                            Text((credits.count > 1 ? "\(index + 1). " : "") + expirationDescription(credit.expiresAt, now: context.date))
                        }
                        if summary.availableCount > credits.count {
                            Text("\(summary.availableCount - credits.count) additional reset(s): expiration unavailable.")
                        }
                    } else {
                        Text(secondaryDescription(now: context.date))
                    }
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(12)
        .background(.background.opacity(0.68), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.opacity(0.34), lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var countBadge: some View {
        if let summary {
            Text("\(summary.availableCount) AVAILABLE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(summary.availableCount > 0 ? .orange : .secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        } else {
            Text("UNAVAILABLE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
    }

    private func secondaryDescription(now: Date) -> String {
        guard let summary else {
            return "Codex did not return banked reset information."
        }
        guard summary.availableCount > 0 else {
            return "No expiration deadline to track."
        }
        guard let expiration = summary.nearestExpiration else {
            return summary.credits == nil
                ? "Count available; expiration details were not returned."
                : "Expiration deadline unavailable."
        }
        return "Expires \(Formatters.reset.string(from: expiration)) • \(timeRemaining(until: expiration, now: now))"
    }

    private func expirationDescription(_ expiration: Date?, now: Date) -> String {
        guard let expiration else { return "Expiration deadline unavailable." }
        return "Expires \(Formatters.reset.string(from: expiration)) • \(timeRemaining(until: expiration, now: now))"
    }

    private func timeRemaining(until expiration: Date, now: Date) -> String {
        let totalMinutes = max(0, Int(expiration.timeIntervalSince(now)) / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)d \(hours)h left" }
        return "\(hours)h \(minutes)m left"
    }

    private var accentColor: Color {
        (summary?.availableCount ?? 0) > 0 ? .orange : .secondary
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private enum Formatters {
    static let reset: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "MMM d, HH:mm 'JST'"
        return formatter
    }()

    static let updated: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "HH:mm 'JST'"
        return formatter
    }()

    static let projected: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "MMM d, HH:mm 'JST'"
        return formatter
    }()
}
