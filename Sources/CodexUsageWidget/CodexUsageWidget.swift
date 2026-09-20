import AppKit
import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetUsageSnapshot?
}

struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: Self.placeholderSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(UsageEntry(date: .now, snapshot: Self.placeholderSnapshot))
        } else {
            fetchSnapshot(completion: completion)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        fetchSnapshot { entry in
            completion(
                Timeline(
                    entries: [entry],
                    policy: .after(Date().addingTimeInterval(15 * 60))
                )
            )
        }
    }

    private func fetchSnapshot(completion: @escaping (UsageEntry) -> Void) {
        var request = URLRequest(url: WidgetUsageConstants.snapshotURL)
        request.timeoutInterval = 2
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let snapshot = statusCode == 200
                ? data.flatMap { try? WidgetSnapshotCodec.decode($0) }
                : nil
            completion(UsageEntry(date: .now, snapshot: snapshot))
        }.resume()
    }

    private static let placeholderSnapshot = WidgetUsageSnapshot(
        limits: [
            WidgetUsageLimit(
                id: "codex",
                name: "Codex",
                windows: [
                    WidgetUsageWindow(
                        label: "Weekly (7-day)",
                        remainingPercent: 64,
                        usedPercent: 36,
                        resetsAt: Date().addingTimeInterval(2 * 24 * 60 * 60)
                    )
                ]
            ),
            WidgetUsageLimit(
                id: "codex-spark",
                name: "Codex Spark",
                windows: [
                    WidgetUsageWindow(
                        label: "Weekly (7-day)",
                        remainingPercent: 92,
                        usedPercent: 8,
                        resetsAt: Date().addingTimeInterval(6 * 24 * 60 * 60)
                    )
                ]
            ),
        ],
        resetCredits: WidgetResetCreditsSummary(
            availableCount: 1,
            nearestExpiration: Date().addingTimeInterval(26 * 24 * 60 * 60),
            detailsAvailable: true
        ),
        appearanceMode: AppearanceMode.system.rawValue,
        updatedAt: .now
    )
}

@main
struct CodexUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetUsageConstants.widgetKind,
            provider: UsageTimelineProvider()
        ) { entry in
            WidgetRootView(entry: entry)
        }
        .configurationDisplayName("AI Usage Monitor")
        .description("Shows the latest Codex usage remaining from the menu bar app.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WidgetRootView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                content
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                content
                    .padding()
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .preferredColorScheme(
            AppearanceMode(storedValue: entry.snapshot?.appearanceMode).colorScheme
        )
        .widgetURL(URL(string: "aiusagemonitor://usage"))
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot, !snapshot.limits.isEmpty {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 12) {
                header(updatedAt: snapshot.updatedAt)
                if family == .systemSmall {
                    compactLimit(snapshot.limits[0])
                } else {
                    HStack(spacing: 16) {
                        ForEach(Array(snapshot.limits.prefix(2))) { limit in
                            mediumLimit(limit)
                        }
                    }
                }
                if let resetCredits = snapshot.resetCredits {
                    resetCreditsLine(resetCredits)
                }
                Spacer(minLength: 0)
            }
            .padding(family == .systemSmall ? 10 : 14)
        } else {
            emptyState
        }
    }

    private func header(updatedAt: Date) -> some View {
        HStack(spacing: 6) {
            UsageMonitorIcon(size: family == .systemSmall ? 17 : 14)
            Text(family == .systemSmall ? "AI Usage" : "AI Usage Monitor")
                .font(
                    family == .systemSmall
                        ? .subheadline.weight(.semibold)
                        : .caption.weight(.semibold)
                )
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(updatedAt, style: .time)
                .font(family == .systemSmall ? .caption : .caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func resetCreditsLine(_ summary: WidgetResetCreditsSummary) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .foregroundStyle(summary.availableCount > 0 ? .orange : .secondary)
            Text(resetCreditsDescription(summary))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 0)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func resetCreditsDescription(_ summary: WidgetResetCreditsSummary) -> String {
        guard summary.availableCount > 0 else { return "No banked resets" }
        let count = summary.availableCount == 1
            ? "1 banked reset"
            : "\(summary.availableCount) banked resets"
        guard let expiration = summary.nearestExpiration else {
            return summary.detailsAvailable ? count : "\(count) • expiry unavailable"
        }
        return "\(count) • expires \(expiration.formatted(.dateTime.month().day()))"
    }

    private func compactLimit(_ limit: WidgetUsageLimit) -> some View {
        VStack(alignment: .center, spacing: 5) {
            Text(limit.name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let window = limit.windows.first {
                RemainingRing(
                    percent: window.remainingPercent,
                    diameter: 66,
                    caption: "left"
                )
                Text(window.label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            } else {
                Text("Limit unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func mediumLimit(_ limit: WidgetUsageLimit) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(limit.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if let window = limit.windows.first {
                HStack(spacing: 9) {
                    RemainingRing(percent: window.remainingPercent, diameter: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(window.label)
                            .font(.caption2)
                            .lineLimit(2)
                        Text("Used \(window.usedPercent)%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            UsageMonitorIcon(size: 30)
            Text("Open AI Usage Monitor")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("The widget will show the next successful update.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
    }
}

struct RemainingRing: View {
    let percent: Int
    let diameter: CGFloat
    let caption: String?

    init(percent: Int, diameter: CGFloat, caption: String? = nil) {
        self.percent = percent
        self.diameter = diameter
        self.caption = caption
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.2), lineWidth: 7)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let caption {
                VStack(spacing: 0) {
                    Text("\(percent)%")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                    Text(caption)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .minimumScaleFactor(0.7)
            } else {
                Text("\(percent)%")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel("Remaining \(percent) percent")
    }

    private var color: Color {
        if percent > 50 { return .green }
        if percent > 20 { return .orange }
        return .red
    }
}
