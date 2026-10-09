import AppKit
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
        .configurationDisplayName("7-day Remaining Graph")
        .description("Shows Codex remaining usage, seven-day history, and estimated exhaustion.")
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
                    .padding(16)
                    .background(.background)
            }
        }
        .preferredColorScheme(AppearanceMode(storedValue: entry.snapshot?.appearanceMode).colorScheme)
        .widgetURL(URL(string: "aiusagemonitor://usage"))
    }
}

/// Kept independent of widget environment values for native snapshot rendering.
struct WidgetGraphView: View {
    @Environment(\.colorScheme) private var colorScheme
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
                    Text("7-day Remaining Graph")
                        .font(.headline)
                    Spacer(minLength: 0)
                    Text(snapshot?.weeklyGraphs?.isEmpty == true
                         ? "No weekly usage window" : "Open the app to refresh")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("History starts with the next update")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func graphContent(_ graph: WidgetWeeklyGraph, observedAt: Date) -> some View {
        VStack(alignment: .leading, spacing: isSmall ? 5 : 7) {
            if isLarge {
                HStack(alignment: .center, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        brand(graph.name)
                        Text("Reset \(stamp(graph.resetsAt))").foregroundStyle(.secondary)
                        if let empty = forecastDate(graph, observedAt: observedAt) {
                            Text("Est. empty \(stamp(empty))").foregroundStyle(.orange)
                        }
                        Text("Updated \(time(observedAt)) \(timeZone(observedAt))").foregroundStyle(.secondary)
                    }.font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    remainingRing(graph.remainingPercent)
                }.frame(height: 94)
                HStack {
                    Spacer()
                    legend(hasForecast: forecastDate(graph, observedAt: observedAt) != nil)
                }.padding(.top, 15)
            } else if isSmall {
                HStack {
                    brand(graph.name)
                    Spacer(minLength: 0)
                    Text("\(time(observedAt)) \(timeZone(observedAt))").font(.system(size: 8)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reset \(stamp(graph.resetsAt))").foregroundStyle(.secondary)
                    if let empty = forecastDate(graph, observedAt: observedAt) {
                        Text("Est. empty \(stamp(empty))").foregroundStyle(.orange)
                    }
                }.font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.85)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        brand(graph.name)
                        Text("Updated \(time(observedAt)) \(timeZone(observedAt))")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Reset \(stamp(graph.resetsAt))").foregroundStyle(.secondary)
                        if let empty = forecastDate(graph, observedAt: observedAt) {
                            Text("Est. empty \(stamp(empty))").foregroundStyle(.orange)
                        }
                    }.font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            graphChart(graph, observedAt: observedAt)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    private func brand(_ name: String) -> some View {
        HStack(spacing: 5) {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable()
                    .frame(width: isSmall ? 16 : 19, height: isSmall ? 16 : 19)
            } else {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(teal)
                    .frame(width: isSmall ? 16 : 19, height: isSmall ? 16 : 19)
            }
            Text(name).font(.system(size: isSmall ? 12 : 14, weight: .bold))
                .lineLimit(1)
        }
    }

    private func stamp(_ date: Date?) -> String {
        guard let date else { return "Unavailable" }
        return Self.dateFormatter.string(from: date)
    }

    private func time(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private func timeZone(_ date: Date) -> String {
        TimeZone.current.abbreviation(for: date) ?? TimeZone.current.identifier
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func remainingRing(_ percent: Int) -> some View {
        let normalized = min(max(percent, 0), 100)
        return ZStack {
            Circle().stroke(.secondary.opacity(0.18), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(normalized) / 100)
                .stroke(RemainingRing.color(for: normalized), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(normalized)%")
                .font(.system(size: 23, weight: .bold, design: .rounded))
        }
        .frame(width: 78, height: 78)
        .padding(4)
        .accessibilityLabel("\(normalized) percent remaining")
    }

    private func legend(hasForecast: Bool) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Rectangle().fill(teal).frame(width: 16, height: 2)
                Text("History")
            }
            if hasForecast {
                HStack(spacing: 4) {
                    HStack(spacing: 3) {
                        Rectangle().fill(.orange).frame(width: 6, height: 2)
                        Rectangle().fill(.orange).frame(width: 6, height: 2)
                    }
                    Text("Forecast")
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
                    x: .value("Time", point.observedAt),
                    yStart: .value("Minimum", 0),
                    yEnd: .value("Remaining", point.remainingPercent),
                    series: .value("Segment", "actual-area")
                )
                .foregroundStyle(teal.opacity(0.15))
                .interpolationMethod(.linear)
            }
            ForEach(WidgetGraphDrawing.strokeRuns(points)) { run in
                ForEach(run.points) { point in
                    LineMark(
                        x: .value("Time", point.observedAt),
                        y: .value("Remaining", point.remainingPercent),
                        series: .value("Segment", "actual-stroke-\(run.id)")
                    )
                    .foregroundStyle(teal.opacity(run.light ? 0.65 : 1))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.linear)
                }
            }
            RuleMark(x: .value("Now", observedAt))
                .foregroundStyle(.secondary.opacity(0.22))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            if let forecast {
                LineMark(
                    x: .value("Time", observedAt),
                    y: .value("Remaining", remaining),
                    series: .value("Segment", "forecast")
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                LineMark(
                    x: .value("Time", forecast),
                    y: .value("Remaining", 0),
                    series: .value("Segment", "forecast")
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                PointMark(x: .value("Time", forecast), y: .value("Remaining", 0))
                    .foregroundStyle(.orange)
                    .symbolSize(isSmall ? 24 : 34)
            }
            PointMark(x: .value("Time", observedAt), y: .value("Remaining", remaining))
                .foregroundStyle(teal)
                .symbolSize(isSmall ? 40 : 55)

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
                        Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits).locale(Locale(identifier: "en_US")))
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
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let frame: CGRect = {
                    if #available(macOS 14, *), let anchor = proxy.plotFrame { return geometry[anchor] }
                    return geometry[proxy.plotAreaFrame]
                }()
                if let x = proxy.position(forX: observedAt),
                   let y = proxy.position(forY: remaining) {
                    let label = isLarge ? "Now" : "\(remaining)%"
                    let font = NSFont.systemFont(ofSize: isLarge ? 10 : (isSmall ? 13 : 16),
                                                 weight: isLarge ? .regular : .bold)
                    let measured = (label as NSString).size(withAttributes: [.font: font])
                    let size = CGSize(width: ceil(measured.width) + 8,
                                      height: ceil(font.ascender - font.descender) + 4)
                    let segments = labelObstacles(points, forecast: forecast, observedAt: observedAt,
                                                  remaining: remaining, proxy: proxy)
                    let placement = GraphLabelPlacement.rect(
                        point: CGPoint(x: x, y: y), label: size, plot: frame.size, segments: segments)
                    let needsBacking = segments.contains {
                        GraphLabelPlacement.intersects($0.0, $0.1, placement.insetBy(dx: -3, dy: -3))
                    }
                    Text(label)
                        .font(Font(font))
                        .foregroundStyle(isLarge ? Color.secondary : Color.primary)
                        .frame(width: size.width, height: size.height)
                        .background(labelBackground.opacity(needsBacking ? 0.94 : 0), in: RoundedRectangle(cornerRadius: 4))
                        .position(x: frame.minX + placement.midX, y: frame.minY + placement.midY)
                        .accessibilityHidden(true)
                }
            }
            .allowsHitTesting(false)
        }
        .accessibilityLabel("Seven-day remaining history, now \(remaining) percent")
    }

    private var labelBackground: Color {
        colorScheme == .dark ? Color(red: 0.12, green: 0.13, blue: 0.15) : .white
    }

    private func labelObstacles(
        _ points: [WidgetHistoryPoint], forecast: Date?, observedAt: Date,
        remaining: Int, proxy: ChartProxy
    ) -> [(CGPoint, CGPoint)] {
        func position(_ date: Date, _ value: Int) -> CGPoint? {
            guard let x = proxy.position(forX: date), let y = proxy.position(forY: value) else { return nil }
            return CGPoint(x: x, y: y)
        }
        var segments: [(CGPoint, CGPoint)] = []
        for (a, b) in zip(points, points.dropFirst()) {
            if let start = position(a.observedAt, a.remainingPercent),
               let end = position(b.observedAt, b.remainingPercent) { segments.append((start, end)) }
        }
        if let forecast, let start = position(observedAt, remaining), let end = position(forecast, 0) {
            segments.append((start, end))
        }
        return segments
    }

    private func displayedPoints(
        _ graph: WidgetWeeklyGraph,
        observedAt: Date
    ) -> [WidgetHistoryPoint] {
        var points = graph.visiblePoints(observedAt: observedAt)
            .filter { (0...100).contains($0.remainingPercent) }
            .sorted { $0.observedAt < $1.observedAt }
        // Current snapshots include this drawing-only point. Add it for older snapshots too.
        let range = graph.domain(observedAt: observedAt)
        if let reset = graph.resetsAt, reset > observedAt,
           reset.timeIntervalSince(observedAt) <= WidgetWeeklyGraph.duration,
           let first = points.first, first.observedAt > range.lowerBound {
            points.insert(WidgetHistoryPoint(observedAt: range.lowerBound, remainingPercent: 100,
                                             segment: first.segment, lightFromPrevious: false), at: 0)
        }
        return points
    }

    private func forecastDate(_ graph: WidgetWeeklyGraph, observedAt: Date) -> Date? {
        guard graph.remainingPercent > 0 else { return nil }
        return graph.forecastDate(observedAt: observedAt)
    }

}

/// Place the measured label inside the plot, away from the point and actual/forecast lines.
/// A compact backing keeps it readable if a dense history leaves no fully clear candidate.
enum GraphLabelPlacement {
    static func rect(point: CGPoint, label: CGSize, plot: CGSize,
                     segments: [(CGPoint, CGPoint)]) -> CGRect {
        let bounds = CGRect(origin: .zero, size: plot).insetBy(dx: 2, dy: 2)
        let gap: CGFloat = 9
        let centered = point.x - label.width / 2
        let xs = [centered, point.x + gap, point.x - gap - label.width]
        let ys = [point.y - gap - label.height, point.y + gap]
        var candidates = ys.flatMap { y in xs.map { x in
            CGRect(x: min(max(x, bounds.minX), max(bounds.minX, bounds.maxX - label.width)),
                   y: min(max(y, bounds.minY), max(bounds.minY, bounds.maxY - label.height)),
                   width: label.width, height: label.height)
        } }
        // Side positions remain usable when the plot is too short for above/below.
        for x in xs.dropFirst() {
            candidates.append(CGRect(x: min(max(x, bounds.minX), max(bounds.minX, bounds.maxX - label.width)),
                y: min(max(point.y - label.height / 2, bounds.minY), max(bounds.minY, bounds.maxY - label.height)),
                width: label.width, height: label.height))
        }
        // Broaden the search in short plots, where clamping near-point candidates can
        // place them back across a steep history or forecast line.
        for row in 0...8 {
            for column in 0...8 {
                let x = bounds.minX + max(0, bounds.width - label.width) * CGFloat(column) / 8
                let y = bounds.minY + max(0, bounds.height - label.height) * CGFloat(row) / 8
                candidates.append(CGRect(origin: CGPoint(x: x, y: y), size: label))
            }
        }
        let pointArea = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
        func score(_ rect: CGRect) -> CGFloat {
            let near = rect.insetBy(dx: -3, dy: -3)
            let collisions = segments.filter { intersects($0.0, $0.1, near) }.count
            let distance = hypot(rect.midX - point.x, rect.midY - point.y)
            return CGFloat(collisions) * 1000 + (rect.intersects(pointArea) ? 10000 : 0) + distance
        }
        return candidates.enumerated().min {
            let a = score($0.element), b = score($1.element)
            return a == b ? $0.offset < $1.offset : a < b
        }!.element
    }

    static func intersects(_ a: CGPoint, _ b: CGPoint, _ rect: CGRect) -> Bool {
        // Liang–Barsky clipping also covers vertical/horizontal and zero-length segments.
        var lower: CGFloat = 0, upper: CGFloat = 1
        let dx = b.x - a.x, dy = b.y - a.y
        for (p, q) in [(-dx, a.x - rect.minX), (dx, rect.maxX - a.x),
                       (-dy, a.y - rect.minY), (dy, rect.maxY - a.y)] {
            if p == 0 { if q < 0 { return false } }
            else {
                let ratio = q / p
                if p < 0 { lower = max(lower, ratio) } else { upper = min(upper, ratio) }
                if lower > upper { return false }
            }
        }
        return true
    }
}
