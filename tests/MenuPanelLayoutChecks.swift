import AppKit
import Combine
import CodexUsageCore
import CodexUsageShared
import SwiftUI

@MainActor final class UsageViewModel: ObservableObject {
    enum ConnectionState: Equatable { case idle, loading, connected, failed(String) }
    @Published var snapshot: UsageSnapshot?
    @Published var state: ConnectionState = .connected
    @Published var notificationsEnabled: Bool? = true
    @Published var paceEstimates: [String: UsagePaceEstimate] = [:]
    @Published var weeklyHistories: [String: [UsageHistorySample]] = [:]
    var isRefreshing: Bool { false }
    func refresh() {}
    func publishCurrentSnapshot() {}
}
enum UsagePaceTracker {
    static func key(limitID: String, window: UsageWindow) -> String {
        "\(limitID)|\(window.source)|\(window.windowDurationMins ?? -1)"
    }
}

@main @MainActor struct MenuPanelLayoutChecks {
    static func main() throws {
        _ = NSApplication.shared
        let output = CommandLine.arguments.count > 1
            ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true) : nil
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        for (name, scheme, appearance) in [("light", ColorScheme.light, NSAppearance.Name.aqua), ("dark", .dark, .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            let model = UsageViewModel()
            update(model, count: 3, extra: false)
            let host = NSHostingView(rootView: UsagePanel(model: model, maximumHeightOverride: 900)
                .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "en_US")))
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 360, height: 900),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: 360, height: 900)
            settle(host)
            verify(host, window: window, fits: true, label: "three-expiries-credit-pace-forecast-\(name)")
            if let output { try save(host, to: output.appendingPathComponent("menu-\(name).png")) }
            update(model, count: 0, extra: false)
            settle(host)
            verify(host, window: window, fits: true, label: "zero-reset-shrink-\(name)")
            update(model, count: 3, extra: false)
            model.state = .failed("Synthetic connection failure")
            settle(host)
            verify(host, window: window, fits: true, label: "stale-grow-\(name)")
            model.state = .connected
            // A genuinely constrained display must retain the content and allow scrolling.
            host.rootView = UsagePanel(model: model, maximumHeightOverride: 420)
                .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "en_US"))
            settle(host)
            verify(host, window: window, fits: false, label: "short-display-\(name)")
            // Returning to a large display must not keep an old height or scroll offset.
            host.rootView = UsagePanel(model: model, maximumHeightOverride: 900)
                .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "en_US"))
            settle(host)
            window.orderOut(nil)
            update(model, count: 2, extra: false)
            settle(host)
            window.alphaValue = 0
            window.orderFront(nil)
            settle(host)
            verify(host, window: window, fits: true, label: "hidden-grow-and-reopen-\(name)")
            update(model, count: 3, extra: true)
            settle(host)
            verify(host, window: window, fits: false, label: "many-limits-overflow-\(name)")
            window.close()
        }
        print("Native menu layout: 12 real-content fit/overflow/grow/shrink/reopen cases PASS")
    }

    static func update(_ model: UsageViewModel, count: Int, extra: Bool) {
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 3600) * 3600)
        let reset = now.addingTimeInterval(7 * 86400)
        let window = UsageWindow(source: "primary", label: "Weekly (7-day)", usedPercent: 7,
            remainingPercent: 93, windowDurationMins: 10080, resetsAt: reset)
        var limits = [UsageLimit(limitID: "codex", displayName: "Codex", planType: "pro",
            rateLimitReachedType: nil, spendControlReached: false, windows: [window],
            creditBalance: .amount(42420))]
        if extra {
            limits += (1...5).map { UsageLimit(limitID: "synthetic-\($0)", displayName: "Additional limit \($0)",
                planType: "pro", rateLimitReachedType: nil, spendControlReached: false, windows: [window]) }
        }
        let credits = (0..<count).map { UsageResetCredit(grantedAt: now.addingTimeInterval(-86400),
            expiresAt: now.addingTimeInterval(Double($0 + 3) * 86400), status: "available",
            resetType: "codexRateLimits", title: nil, description: nil) }
        model.snapshot = UsageSnapshot(limits: limits,
            resetCredits: UsageResetCreditsSummary(availableCount: count, credits: credits), updatedAt: now)
        let key = UsagePaceTracker.key(limitID: "codex", window: window)
        model.paceEstimates = [key: UsagePaceEstimate(exhaustionDate: now.addingTimeInterval(3 * 86400),
            usedPercentPerHour: 1.2, recentUsedPercentPerHour: 1.2, longTermUsedPercentPerHour: 1,
            confidence: .medium)]
        model.weeklyHistories = [key: [UsageHistorySample(observedAt: now.addingTimeInterval(-180),
            remainingPercent: 94, resetsAt: reset), UsageHistorySample(observedAt: now,
            remainingPercent: 93, resetsAt: reset)]]
    }

    static func settle<V: View>(_ host: NSHostingView<V>) {
        for _ in 0..<16 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.025))
        }
    }
    static func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }
    static func verify<V: View>(_ host: NSHostingView<V>, window: NSWindow, fits: Bool, label: String) {
        let scrolls = scrollViews(in: host)
        precondition(scrolls.count == 1, "\(label): expected one actual NSScrollView")
        let scroll = scrolls[0]
        let document = scroll.documentView!.frame.height
        let viewport = scroll.contentView.bounds.height
        precondition(abs(window.contentLayoutRect.height - host.bounds.height) <= 1,
            "\(label): native window and SwiftUI panel disagree")
        if fits {
            precondition(document <= viewport + 1,
                "\(label): unnecessary scrolling (document \(document), viewport \(viewport))")
            precondition(abs(scroll.contentView.bounds.minY) <= 1,
                "\(label): content remains scrolled after fitting")
        } else {
            precondition(document > viewport + 1, "\(label): tall content was clipped instead of scrollable")
        }
        print("\(label): \(fits ? "FIT" : "BOUNDED_SCROLL") window=\(host.bounds.height) document=\(document) viewport=\(viewport)")
    }
    static func save<V: View>(_ host: NSHostingView<V>, to url: URL) throws {
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
