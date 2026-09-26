import Charts
import CodexUsageCore
import SwiftUI

struct WeeklyUsageChart: View {
    let samples: [UsageHistorySample]
    let window: UsageWindow
    let estimate: UsagePaceEstimate?
    let observedAt: Date
    @State private var inspectedSample: UsageHistorySample?

    private var start: Date { observedAt.addingTimeInterval(-UsageHistory.retention) }
    private var forecast: UsagePaceEstimate? {
        guard let estimate, let reset = window.resetsAt,
              estimate.exhaustionDate > observedAt, estimate.exhaustionDate < reset else { return nil }
        return estimate
    }
    private var end: Date {
        if let reset = window.resetsAt, reset > observedAt {
            return reset
        }
        return observedAt
    }
    private var points: [UsageHistorySample] {
        UsageHistory.drawingSamples(samples.filter { $0.observedAt >= start && $0.observedAt <= observedAt })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                Text("7-day history + forecast").font(.caption.weight(.medium))
                Spacer(minLength: 4)
                legend("History", color: .teal, dashed: false)
                if forecast != nil { legend("Forecast", color: .orange, dashed: true) }
            }
            Chart {
                ForEach(points) { sample in
                    AreaMark(x: .value("Time", sample.observedAt), y: .value("Remaining", sample.remainingPercent),
                             series: .value("Series", "history-\(sample.segment)"))
                        .foregroundStyle(LinearGradient(colors: [.teal.opacity(0.28), .teal.opacity(0.01)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Time", sample.observedAt), y: .value("Remaining", sample.remainingPercent),
                             series: .value("Series", "history-\(sample.segment)"))
                        .foregroundStyle(.teal).lineStyle(StrokeStyle(lineWidth: 1.5))
                        .accessibilityLabel(sample.observedAt.formatted(date: .abbreviated, time: .shortened))
                        .accessibilityValue("\(sample.remainingPercent) percent remaining")
                }
                if let forecast {
                    ForEach([observedAt, forecast.exhaustionDate], id: \.self) { date in
                        LineMark(x: .value("Time", date),
                                 y: .value("Predicted remaining", date == observedAt ? window.remainingPercent : 0),
                                 series: .value("Series", "forecast"))
                            .foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                    PointMark(x: .value("Expected empty", forecast.exhaustionDate), y: .value("Remaining", 0))
                        .foregroundStyle(.orange).symbolSize(24)
                        .accessibilityLabel("Expected empty \(Self.timestamp(forecast.exhaustionDate))")
                }
                PointMark(x: .value("Now", observedAt), y: .value("Remaining", window.remainingPercent))
                    .foregroundStyle(.teal).symbolSize(28)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("\(window.remainingPercent)%").font(.caption2.weight(.semibold))
                    }
                if let inspectedSample {
                    RuleMark(x: .value("Observed time", inspectedSample.observedAt))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .chartXScale(domain: start...end)
            .chartYScale(domain: 0...100)
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                    AxisValueLabel(anchor: .top) {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                    AxisValueLabel(anchor: .trailing) { if let percent = value.as(Int.self) { Text("\(percent)%") } }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let plot: CGRect
                                if #available(macOS 14, *), let anchor = proxy.plotFrame {
                                    plot = geometry[anchor]
                                } else {
                                    plot = geometry[proxy.plotAreaFrame]
                                }
                                let plotX = location.x - plot.origin.x
                                guard plotX >= 0, plotX <= plot.width,
                                      let time: Date = proxy.value(atX: plotX), time <= observedAt else {
                                    inspectedSample = nil; return
                                }
                                inspectedSample = samples.min {
                                    abs($0.observedAt.timeIntervalSince(time)) < abs($1.observedAt.timeIntervalSince(time))
                                }
                            case .ended: inspectedSample = nil
                            }
                        }
                }
            }
            .frame(height: 120)
            if let inspectedSample {
                Text("\(Self.timestamp(inspectedSample.observedAt)) · \(inspectedSample.remainingPercent)% remaining")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                Text("Now \(Self.timestamp(observedAt))").font(.caption2).foregroundStyle(.secondary)
            }
            if let forecast {
                Text("Expected empty \(Self.timestamp(forecast.exhaustionDate))")
                    .font(.caption2.weight(.medium)).foregroundStyle(.orange)
            }
            if let reset = window.resetsAt {
                Text("Reset \(Self.timestamp(reset))").font(.caption2).foregroundStyle(.secondary)
            }
            if samples.count < 2 {
                Text("Collecting history. Earlier data is unavailable.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weekly remaining history and estimated exhaustion")
    }

    private func legend(_ text: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 3) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1))
                path.addLine(to: CGPoint(x: 12, y: 1))
            }.stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [3, 2] : []))
                .frame(width: 12, height: 3)
            Text(text).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .accessibilityLabel(text + (dashed ? ", dashed prediction" : ", solid observations"))
    }

    private static let formatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = .current
        value.dateFormat = "MMM d, HH:mm z"
        return value
    }()

    private static func timestamp(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
