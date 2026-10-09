import CodexUsageShared
import Foundation
import Network

final class WidgetSnapshotServer {
    static let shared = WidgetSnapshotServer()

    private let queue = DispatchQueue(label: "local.aiusagemonitor.widget-bridge")
    private var listener: NWListener?
    private var latestSnapshot: Data?

    private init() {}

    func start() {
        queue.async { [weak self] in
            guard let self, self.listener == nil else { return }
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(
                host: .ipv4(.loopback),
                port: 58_743
            )
            guard let listener = try? NWListener(using: parameters) else { return }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                if case .failed = state {
                    listener?.cancel()
                    self?.listener = nil
                }
            }
            self.listener = listener
            listener.start(queue: self.queue)
        }
    }

    func publish(_ snapshot: WidgetUsageSnapshot) {
        guard let data = try? WidgetSnapshotCodec.encode(snapshot) else { return }
        queue.async { [weak self] in
            self?.latestSnapshot = data
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) {
            [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            guard request.hasPrefix("GET /snapshot ") else {
                self.respond(status: "404 Not Found", body: nil, on: connection)
                return
            }
            guard let body = self.latestSnapshot else {
                self.respond(status: "503 Service Unavailable", body: nil, on: connection)
                return
            }
            self.respond(status: "200 OK", body: body, on: connection)
        }
    }

    private func respond(status: String, body: Data?, on connection: NWConnection) {
        let payload = body ?? Data()
        let header = Data(
            "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8
        )
        connection.send(content: header + payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
