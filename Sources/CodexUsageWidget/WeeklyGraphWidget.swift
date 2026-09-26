import Charts
import SwiftUI
import WidgetKit

struct WeeklyGraphTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: Self.previewSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(UsageEntry(date: .now, snapshot: Self.previewSnapshot))
        } else {
            UsageTimelineProvider().getSnapshot(in: context, completion: completion)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        UsageTimelineProvider().getTimeline(in: context, completion: completion)
    }

    /// Gallery examples are synthetic and never substitute for missing live data.
    private static var previewSnapshot: WidgetUsageSnapshot {
        let observed = Date()
        let day: TimeInterval = 24 * 60 * 60
        let remaining = [96, 84, 70, 55, 42]
        let points = remaining.enumerated().map { index, value in
            WidgetHistoryPoint(
                observedAt: observed.addingTimeInterval(Double(index - 4) * day),
                remainingPercent: value,
                segment: 0
            )
        }
        return WidgetUsageSnapshot(
            limits: [],
            updatedAt: observed,
            weeklyGraphs: [
                WidgetWeeklyGraph(
                    id: "synthetic-codex-weekly",
                    name: "Codex",
                    remainingPercent: 42,
                    resetsAt: observed.addingTimeInterval(2 * day),
                    exhaustionDate: observed.addingTimeInterval(day),
                    points: points
                )
            ]
        )
    }
}

struct WeeklyGraphWidget: Widget {
    var body: some WidgetConfiguration { configuration }

    private var configuration: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetUsageConstants.graphWidgetKind,
            provider: WeeklyGraphTimelineProvider()
        ) { entry in
            WeeklyGraphWidgetRoot(entry: entry)
        }
        .configurationDisplayName("7日間の残量グラフ")
        .description("Codexの残量と7日間の推移、使い切り予測を表示します。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct WeeklyGraphWidgetRoot: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                WidgetGraphView(snapshot: entry.snapshot, family: family)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                WidgetGraphView(snapshot: entry.snapshot, family: family)
                    .background(.background)
            }
        }
        .preferredColorScheme(AppearanceMode(storedValue: entry.snapshot?.appearanceMode).colorScheme)
        .widgetURL(URL(string: "aiusagemonitor://usage"))
    }
}

/// Kept independent of widget environment values for native snapshot rendering.
struct WidgetGraphView: View {
    let snapshot: WidgetUsageSnapshot?
    let family: WidgetFamily

    private let teal = Color(red: 0.0, green: 0.66, blue: 0.64)
    private var isSmall: Bool { family == .systemSmall }
    private var isLarge: Bool { family == .systemLarge }

    var body: some View {
        Group {
            if let snapshot, let graph = snapshot.weeklyGraphs?.first {
                graphContent(graph, observedAt: snapshot.updatedAt)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("7日間の残量グラフ")
                        .font(.headline)
                    Spacer(minLength: 0)
                    Text(snapshot?.weeklyGraphs?.isEmpty == true
                         ? "週間の利用枠がありません" : "アプリを開いて更新してください")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("履歴は次の更新から表示されます")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(isSmall ? 10 : 14)
    }

    private func graphContent(_ graph: WidgetWeeklyGraph, observedAt: Date) -> some View {
        VStack(alignment: .leading, spacing: isSmall ? 5 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(graph.name)
                    .font(isSmall ? .subheadline.weight(.bold) : .headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if isSmall {
                    Spacer(minLength: 4)
                    Text(observedAt, format: .dateTime.hour().minute())
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                }
                if !isSmall {
                    Spacer(minLength: 4)
                    resetLabel(graph, observedAt: observedAt)
                }
            }
            if isLarge {
                HStack(alignment: .bottom) {
                    remainingRing(graph.remainingPercent)
                    Spacer()
                    legend(hasForecast: forecastDate(graph, observedAt: observedAt) != nil)
                }
                .padding(.bottom, 2)
            }
            graphChart(graph, observedAt: observedAt)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer(graph, observedAt: observedAt)
        }
        .accessibilityElement(children: .combine)
    }

    private func remainingRing(_ percent: Int) -> some View {
        let normalized = min(max(percent, 0), 100)
        return ZStack {
            Circle().stroke(.secondary.opacity(0.18), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(normalized) / 100)
                .stroke(teal, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(normalized)%")
                .font(.system(size: 23, weight: .bold, design: .rounded))
        }
        .frame(width: 78, height: 78)
        .padding(4)
        .accessibilityLabel("残量 \(normalized)パーセント")
    }

    private func legend(hasForecast: Bool) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Rectangle().fill(teal).frame(width: 16, height: 2)
                Text("実績")
            }
            if hasForecast {
                HStack(spacing: 4) {
                    HStack(spacing: 3) {
                        Rectangle().fill(.orange).frame(width: 6, height: 2)
                        Rectangle().fill(.orange).frame(width: 6, height: 2)
                    }
                    Text("予測")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func graphChart(_ graph: WidgetWeeklyGraph, observedAt: Date) -> some View {
        let domain = graph.domain(observedAt: observedAt)
        let points = displayedPoints(graph, observedAt: observedAt)
        let forecast = forecastDate(graph, observedAt: observedAt)
        let remaining = min(max(graph.remainingPercent, 0), 100)
        let currentFraction = observedAt.timeIntervalSince(domain.lowerBound)
            / domain.upperBound.timeIntervalSince(domain.lowerBound)
        let labelAlignment: Alignment = currentFraction > 0.85 ? .trailing
            : currentFraction < 0.15 ? .leading : .center
        let tickCount = isSmall ? 2 : 4
        let ticks = (0..<tickCount).map { index in
            domain.lowerBound.addingTimeInterval(
                domain.upperBound.timeIntervalSince(domain.lowerBound)
                    * Double(index) / Double(tickCount - 1)
            )
        }

        return Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("日時", point.observedAt),
                    yStart: .value("下限", 0),
                    yEnd: .value("残量", point.remainingPercent),
                    series: .value("区間", "actual-\(point.segment)")
                )
                .foregroundStyle(teal.opacity(0.15))
                .interpolationMethod(.linear)
                LineMark(
                    x: .value("日時", point.observedAt),
                    y: .value("残量", point.remainingPercent),
                    series: .value("区間", "actual-\(point.segment)")
                )
                .foregroundStyle(teal)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.linear)
            }
            RuleMark(x: .value("現在", observedAt))
                .foregroundStyle(.secondary.opacity(0.22))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            if let forecast {
                LineMark(
                    x: .value("日時", observedAt),
                    y: .value("残量", remaining),
                    series: .value("区間", "forecast")
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                LineMark(
                    x: .value("日時", forecast),
                    y: .value("残量", 0),
                    series: .value("区間", "forecast")
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                PointMark(x: .value("日時", forecast), y: .value("残量", 0))
                    .foregroundStyle(.orange)
                    .symbolSize(isSmall ? 24 : 34)
            }
            PointMark(x: .value("日時", observedAt), y: .value("残量", remaining))
                .foregroundStyle(teal)
                .symbolSize(isSmall ? 40 : 55)
                .annotation(
                    position: remaining >= 90 ? .bottom : .top,
                    alignment: labelAlignment,
                    spacing: 5
                ) {
                    Text(isLarge ? "現在" : "\(remaining)%")
                        .font(isLarge ? .caption : .system(size: isSmall ? 13 : 16, weight: .bold))
                        .foregroundStyle(isLarge ? Color.secondary : Color.primary)
                        .padding(.horizontal, 2)
                }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...100)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                if !isSmall {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(.secondary.opacity(0.18))
                }
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel(anchor: value.as(Date.self) == domain.lowerBound ? .topLeading :
                    (value.as(Date.self) == domain.upperBound ? .topTrailing : .top)) {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                            .font(.system(size: isSmall ? 8 : 9))
                    }
                }
            }
        }
        .chartYAxis {
            if isLarge {
                AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                    AxisValueLabel(anchor: .trailing) {
                        if let number = value.as(Int.self) {
                            Text("\(number)%").font(.system(size: 9))
                        }
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.padding(.top, 4).padding(.bottom, 3)
        }
        .accessibilityLabel("7日間の残量推移、現在 \(remaining)パーセント")
    }

    private func displayedPoints(
        _ graph: WidgetWeeklyGraph,
        observedAt: Date
    ) -> [WidgetHistoryPoint] {
        let points = graph.visiblePoints(observedAt: observedAt)
            .filter { (0...100).contains($0.remainingPercent) }
            .sorted { $0.observedAt < $1.observedAt }
        // The publisher already preserves extrema and caps the drawing copy.
        // Keep reset segment identities intact and never manufacture a connected observation.
        return points
    }

    private func forecastDate(_ graph: WidgetWeeklyGraph, observedAt: Date) -> Date? {
        guard graph.remainingPercent > 0 else { return nil }
        return graph.forecastDate(observedAt: observedAt)
    }

    private func resetLabel(_ graph: WidgetWeeklyGraph, observedAt: Date) -> some View {
        Group {
            if let reset = graph.resetsAt, reset > observedAt {
                Text("リセット \(shortDate(reset))")
            } else {
                Text("7日間")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func footer(_ graph: WidgetWeeklyGraph, observedAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if isSmall {
                resetLabel(graph, observedAt: observedAt)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let estimate = forecastDate(graph, observedAt: observedAt) {
                    Text("使い切り予測 \(shortDate(estimate))")
                        .foregroundStyle(.orange)
                } else if graph.points.isEmpty {
                    Text("履歴を記録中")
                        .foregroundStyle(.secondary)
                } else if isLarge {
                    Text("使い切り予測なし")
                        .foregroundStyle(.secondary)
                }
                if !isSmall {
                    Spacer(minLength: 4)
                    Text("更新 \(observedAt.formatted(.dateTime.hour().minute()))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: isSmall ? 8 : 10))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
    }
}
