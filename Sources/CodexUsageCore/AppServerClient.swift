import Darwin
import Foundation

public enum AppServerClientError: LocalizedError {
    case codexNotFound
    case launchFailed
    case stateUnavailable
    case timeout(String)
    case serverExited
    case malformedResponse
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "Codex was not found. Install Codex or set CODEX_BIN to its executable."
        case .launchFailed:
            return "Codex app-server could not be started."
        case .stateUnavailable:
            return "Codex could not access its local state. Check access to ~/.codex."
        case .timeout(let method):
            return "Codex timed out while handling \(method)."
        case .serverExited:
            return "Codex app-server exited unexpectedly."
        case .malformedResponse:
            return "Codex returned an invalid protocol response."
        case .requestFailed(let message):
            return message
        }
    }
}

public final class AppServerClient {
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private let timeout: TimeInterval
    private var nextRequestID = 1
    private var readBuffer = Data()

    public init(codexURL: URL? = nil, timeout: TimeInterval = 15) throws {
        self.timeout = timeout
        process.executableURL = try codexURL ?? Self.locateCodex()
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw AppServerClientError.launchFailed
        }
    }

    deinit {
        close()
    }

    public static func fetchUsage(
        codexURL: URL? = nil,
        timeout: TimeInterval = 15,
        now: Date = Date()
    ) throws -> UsageSnapshot {
        let client = try AppServerClient(codexURL: codexURL, timeout: timeout)
        defer { client.close() }
        try client.initialize()
        let payload = try client.readRateLimits()
        return try UsageNormalizer.normalize(payload, now: now)
    }

    public static func locateCodex() throws -> URL {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment

        if let override = environment["CODEX_BIN"], !override.isEmpty {
            let expanded = NSString(string: override).expandingTildeInPath
            if fileManager.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
            throw AppServerClientError.codexNotFound
        }

        let knownPaths = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        for path in knownPaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        for directory in environment["PATH", default: ""].split(separator: ":") {
            let path = String(directory) + "/codex"
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        throw AppServerClientError.codexNotFound
    }

    public func initialize() throws {
        _ = try request(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "codex_usage_monitor",
                    "title": "AI Usage Monitor",
                    "version": "0.5.0",
                ]
            ]
        )
        try send(["method": "initialized"])
    }

    public func readRateLimits() throws -> [String: Any] {
        let result = try request(method: "account/rateLimits/read", params: nil)
        guard let payload = result as? [String: Any] else {
            throw AppServerClientError.malformedResponse
        }
        return payload
    }

    public func close() {
        try? inputPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }

    private func request(method: String, params: [String: Any]?) throws -> Any {
        let requestID = nextRequestID
        nextRequestID += 1
        var message: [String: Any] = ["method": method, "id": requestID]
        if let params { message["params"] = params }
        try send(message)

        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let response = try readMessage(deadline: deadline, method: method)
            guard let responseID = integer(response["id"]), responseID == requestID else {
                continue
            }
            if let error = response["error"] as? [String: Any] {
                let serverMessage = (error["message"] as? String) ?? "Unknown app-server error"
                throw AppServerClientError.requestFailed(
                    "\(method) failed: \(String(serverMessage.prefix(240)))"
                )
            }
            guard let result = response["result"] else {
                throw AppServerClientError.malformedResponse
            }
            return result
        }
    }

    private func send(_ message: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(message) else {
            throw AppServerClientError.malformedResponse
        }
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        inputPipe.fileHandleForWriting.write(data)
    }

    private func readMessage(deadline: Date, method: String) throws -> [String: Any] {
        while true {
            if let newline = readBuffer.firstIndex(of: 0x0A) {
                let line = readBuffer[..<newline]
                let afterNewline = readBuffer.index(after: newline)
                readBuffer.removeSubrange(readBuffer.startIndex..<afterNewline)
                guard !line.isEmpty,
                      let object = try? JSONSerialization.jsonObject(with: Data(line)),
                      let message = object as? [String: Any]
                else {
                    throw AppServerClientError.malformedResponse
                }
                return message
            }

            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                throw AppServerClientError.timeout(method)
            }
            var descriptor = pollfd(
                fd: Int32(outputPipe.fileHandleForReading.fileDescriptor),
                events: Int16(POLLIN),
                revents: 0
            )
            let timeoutMillis = Int32(min(remaining * 1_000, Double(Int32.max)))
            let pollResult = Darwin.poll(&descriptor, 1, max(timeoutMillis, 1))
            if pollResult == 0 {
                throw AppServerClientError.timeout(method)
            }
            if pollResult < 0 {
                if errno == EINTR { continue }
                throw AppServerClientError.serverExited
            }

            let data = outputPipe.fileHandleForReading.availableData
            guard !data.isEmpty else {
                throw exitError()
            }
            readBuffer.append(data)
        }
    }

    private func exitError() -> AppServerClientError {
        guard !process.isRunning else { return .serverExited }
        let stderr = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: stderr, encoding: .utf8) ?? ""
        if text.contains("failed to initialize sqlite state runtime") {
            return .stateUnavailable
        }
        return .serverExited
    }

    private func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        guard double.rounded() == double,
              double >= Double(Int.min),
              double <= Double(Int.max)
        else {
            return nil
        }
        return Int(double)
    }
}
