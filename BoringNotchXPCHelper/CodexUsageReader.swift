import Darwin
import Foundation

// A bounded, one-shot reader. It never sends prompts, changes accounts, consumes
// resets or reads authentication files. Codex owns its existing sign-in.
enum CodexUsageReader {
    static func fetch(executable: URL? = nil, timeout: TimeInterval = 15) throws -> CodexUsageSnapshot {
        let rpc = try CodexUsageRPC(executable: executable ?? locateExecutable(), timeout: timeout)
        defer { rpc.stop() }
        _ = try rpc.request("initialize", id: 0, params: [
            "clientInfo": ["name": "boring-notch", "title": "Boring Notch", "version": "1.0"]
        ])
        try rpc.notify("initialized")
        let account = try rpc.request("account/read", id: 1, params: ["refreshToken": false])
        // Decode auth first, so signed-out or API-key-only users get an accurate
        // setup state without waiting for an unnecessary remote quota request.
        let identity = try JSONSerialization.jsonObject(with: account) as? [String: Any]
        guard let details = identity?["account"] as? [String: Any] else { throw CodexUsageError.signedOut }
        if ["apiKey", "amazonBedrock"].contains(details["type"] as? String ?? "") {
            throw CodexUsageError.unsupportedAccount
        }
        let limits = try rpc.request("account/rateLimits/read", id: 2)
        do { return try CodexUsageSnapshot.decodeRPC(account: account, limits: limits) }
        catch let error as CodexUsageError { throw error }
        catch { throw CodexUsageError.invalidResponse }
    }

    static func locateExecutable() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths: [String] = []
        for root in ["/Applications", "\(home)/Applications", "/System/Applications"] {
            for app in ["ChatGPT.app", "Codex.app"] {
                paths += ["\(root)/\(app)/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                          "\(root)/\(app)/Contents/Resources/codex"]
            }
        }
        paths += ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex",
                  "\(home)/.npm-global/bin/codex"]
        paths += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw CodexUsageError.notInstalled
        }
        return URL(fileURLWithPath: path)
    }
}

private final class CodexUsageRPC {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private let deadline: TimeInterval

    init(executable: URL, timeout: TimeInterval) throws {
        deadline = ProcessInfo.processInfo.systemUptime + timeout
        process.executableURL = executable
        process.arguments = ["-s", "read-only", "-a", "never", "app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw CodexUsageError.unavailable }
        let fd = output.fileHandleForReading.fileDescriptor
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
    }

    func notify(_ method: String) throws { try send(["method": method]) }

    func request(_ method: String, id: Int, params: [String: Any]? = nil) throws -> Data {
        var message: [String: Any] = ["method": method, "id": id]
        if let params { message["params"] = params }
        try send(message)
        while ProcessInfo.processInfo.systemUptime < deadline {
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let reply = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      reply["id"] as? Int == id else { continue }
                if let error = reply["error"] as? [String: Any] {
                    let text = (error["message"] as? String ?? "").lowercased()
                    let needsLogin = ["401", "unauthorized", "not logged in", "not authenticated"].contains { text.contains($0) }
                    throw needsLogin ? CodexUsageError.signedOut : CodexUsageError.unavailable
                }
                guard let result = reply["result"] as? [String: Any] else { throw CodexUsageError.invalidResponse }
                return try JSONSerialization.data(withJSONObject: result)
            }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 {
                if errno == EINTR { continue }
                throw CodexUsageError.unavailable
            }
            if ready > 0 {
                var bytes = [UInt8](repeating: 0, count: 16_384)
                let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor.fd, $0.baseAddress, $0.count) }
                if count > 0 {
                    buffer.append(contentsOf: bytes.prefix(count))
                    guard buffer.count < 2_000_000 else { throw CodexUsageError.invalidResponse }
                } else if count == 0 { throw CodexUsageError.unavailable }
                else if errno != EAGAIN && errno != EINTR { throw CodexUsageError.unavailable }
            }
        }
        throw CodexUsageError.timeout
    }

    private func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(10)
        do { try input.fileHandleForWriting.write(contentsOf: data) }
        catch { throw CodexUsageError.unavailable }
    }

    func stop() {
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            let until = ProcessInfo.processInfo.systemUptime + 0.5
            while process.isRunning && ProcessInfo.processInfo.systemUptime < until { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        try? output.fileHandleForReading.close()
    }
}
