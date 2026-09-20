import CodexUsageCore
import Combine
import Foundation

@MainActor
final class UsageViewModel: ObservableObject {
    enum ConnectionState: Equatable {
        case idle
        case loading
        case connected
        case failed(String)
    }

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var notificationsEnabled: Bool?
    @Published private(set) var paceEstimates: [String: UsagePaceEstimate] = [:]

    private var timer: Timer?
    private let refreshInterval: TimeInterval

    init(refreshInterval: TimeInterval = 3 * 60) {
        self.refreshInterval = refreshInterval
    }

    var isRefreshing: Bool {
        state == .loading
    }

    func start() {
        guard timer == nil else { return }
        UsageNotificationManager.shared.requestAuthorization { [weak self] enabled in
            DispatchQueue.main.async {
                self?.notificationsEnabled = enabled
            }
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func refresh() {
        UsageNotificationManager.shared.refreshAuthorizationStatus { [weak self] enabled in
            DispatchQueue.main.async {
                self?.notificationsEnabled = enabled
            }
        }
        guard !isRefreshing else { return }
        state = .loading
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try AppServerClient.fetchUsage() }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let snapshot):
                    self.paceEstimates = UsagePaceTracker.shared.process(snapshot)
                    self.snapshot = snapshot
                    self.state = .connected
                    UsageNotificationManager.shared.process(snapshot)
                    UsageWidgetBridge.publish(snapshot)
                case .failure(let error):
                    self.state = .failed(
                        (error as? LocalizedError)?.errorDescription
                            ?? "Codex usage could not be refreshed."
                    )
                }
            }
        }
    }

    func publishCurrentSnapshot() {
        guard let snapshot else { return }
        UsageWidgetBridge.publish(snapshot)
    }
}
