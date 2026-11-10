//
//  MCPADB.swift
//  AndroLaunch
//
//  Blocking ADB + companion transport for the stdio MCP server. The server is a
//  headless process that starts before the app's services, so it cannot reuse
//  `ADBService` (whose API is completion-based on the main run loop). It uses a
//  small synchronous process runner with a deadline, and checks the Settings
//  stop sentinel while a command is running so "Stop server" aborts work.
//

import Foundation
#if canImport(Darwin)
    import Darwin
#endif

// MARK: - Device

struct MCPADBDevice: Equatable {
    let serial: String
    let state: String
    let model: String?
    let product: String?
    let transportID: String?

    var isReady: Bool { state == "device" }

    var transportLabel: String {
        if serial.contains(":") || serial.contains(".local") || serial.contains("_adb-tls") {
            return "Wi-Fi"
        }
        return "USB"
    }

    var displayName: String {
        if let model, !model.isEmpty { return model }
        return serial
    }
}

// MARK: - Result

struct MCPADBRunResult {
    let status: Int32
    let stdout: Data
    let stderr: String
    let elapsed: TimeInterval

    var stdoutText: String { String(decoding: stdout, as: UTF8.self) }

    var trimmedOutput: String {
        stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedError: String {
        stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Client

final class MCPADBClient {
    private let log: MCPActivityLog
    private let fileManager: FileManager
    private var locatedBinary: String??

    /// Per-serial host port assigned by `adb forward tcp:0`. The adb server's
    /// forward table is process-global, so a single fixed port would route a
    /// second phone's companion calls to the first phone's forward.
    private var companionPorts: [String: UInt16] = [:]

    init(log: MCPActivityLog = MCPActivityLog(), fileManager: FileManager = .default) {
        self.log = log
        self.fileManager = fileManager
    }

    // MARK: Binary discovery

    var binaryPath: String? {
        if let locatedBinary { return locatedBinary }
        let found = Self.locateADB(fileManager: fileManager)
        locatedBinary = found
        return found
    }

    static func locateADB(fileManager: FileManager = .default) -> String? {
        var candidates: [String] = []
        if let bundled = Bundle.main.url(forResource: "adb", withExtension: nil)?.path {
            candidates.append(bundled)
        }
        let environment = ProcessInfo.processInfo.environment
        if let configured = environment["ANDROLAUNCH_ADB_PATH"], !configured.isEmpty {
            candidates.append(configured)
        }
        let home = NSHomeDirectory()
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "/usr/bin/adb",
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "\(home)/Documents/android/platform-tools/adb",
            "/Library/Android/sdk/platform-tools/adb",
        ])
        if let path = environment["PATH"] {
            for directory in path.split(separator: ":") {
                candidates.append(String(directory) + "/adb")
            }
        }
        for candidate in candidates
        where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    // MARK: Process runner

    func run(arguments: [String], timeout: TimeInterval) throws -> MCPADBRunResult {
        guard let binary = binaryPath else {
            throw MCPToolError.adbUnavailable(
                "ADB was not found. Install Android platform-tools or make `adb` available "
                    + "on PATH, then reconnect.")
        }
        let startedAt = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice
        process.environment = ProcessInfo.processInfo.environment

        do {
            try process.run()
        } catch {
            throw MCPToolError.executionFailed(
                "Could not launch ADB: \(error.localizedDescription)")
        }

        // Drain both pipes concurrently: screenshots and dumps can exceed a pipe
        // buffer, and a blocked child would otherwise look like a timeout.
        let outputBox = MCPDataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputBox.stdout = outputPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputBox.stderr = errorPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let deadline = startedAt.addingTimeInterval(timeout)
        var timedOut = false
        var stopped = false
        var sentinelCheckedAt = Date.distantPast
        while process.isRunning {
            let now = Date()
            // The sentinel check is cheap, but not per-50ms cheap on a slow disk.
            if now.timeIntervalSince(sentinelCheckedAt) >= 0.2 {
                sentinelCheckedAt = now
                if log.stopRequested {
                    stopped = true
                    break
                }
            }
            if now >= deadline {
                timedOut = true
                break
            }
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            if !waitForExit(process, within: 2) {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()
        _ = group.wait(timeout: .now() + 5)

        if stopped { throw MCPToolError.stopped }
        if timedOut {
            throw MCPToolError.executionFailed(
                "ADB did not finish within \(Int(timeout.rounded())) seconds.")
        }

        return MCPADBRunResult(
            status: process.terminationStatus,
            stdout: outputBox.stdout,
            stderr: String(decoding: outputBox.stderr, as: UTF8.self),
            elapsed: Date().timeIntervalSince(startedAt))
    }

    private func waitForExit(_ process: Process, within seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        return !process.isRunning
    }

    // MARK: Devices

    func devices() throws -> [MCPADBDevice] {
        let result = try run(arguments: ["devices", "-l"], timeout: 15)
        return Self.parseDevices(result.stdoutText)
    }

    static func parseDevices(_ output: String) -> [MCPADBDevice] {
        var devices: [MCPADBDevice] = []
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                !line.hasPrefix("List of devices"),
                !line.hasPrefix("*")
            else { continue }
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard tokens.count >= 2 else { continue }
            let serial = String(tokens[0])
            let state = String(tokens[1])
            var model: String?
            var product: String?
            var transportID: String?
            for token in tokens.dropFirst(2) {
                let parts = token.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = String(parts[0])
                let value = String(parts[1])
                switch key {
                case "model": model = value.replacingOccurrences(of: "_", with: " ")
                case "product": product = value.replacingOccurrences(of: "_", with: " ")
                case "transport_id": transportID = value
                default: break
                }
            }
            devices.append(
                MCPADBDevice(
                    serial: serial, state: state, model: model, product: product,
                    transportID: transportID))
        }
        return devices
    }

    /// Resolves the device for a tool call: an explicit serial must be online;
    /// without one, exactly one ready device must exist.
    func resolveSerial(_ serial: String?, devices: [MCPADBDevice]? = nil) throws -> String {
        let known: [MCPADBDevice]
        if let devices {
            known = devices
        } else {
            known = try self.devices()
        }
        if let serial {
            guard let match = known.first(where: { $0.serial == serial }) else {
                throw MCPToolError.noDevice(
                    "Device \(serial) is not connected. Call phone_list_devices for current devices.")
            }
            guard match.isReady else {
                throw MCPToolError.noDevice(
                    "Device \(serial) is \(match.state). Unlock the phone and accept the USB "
                        + "debugging prompt, then try again.")
            }
            return match.serial
        }
        let ready = known.filter(\.isReady)
        switch ready.count {
        case 0:
            let joined =
                known.isEmpty
                ? "No Android device is connected."
                : "No authorized Android device is connected (found: "
                    + known.map { "\($0.serial) \($0.state)" }.joined(separator: ", ") + ")."
            throw MCPToolError.noDevice(
                joined + " Connect a device with USB debugging enabled and call "
                    + "phone_list_devices again.")
        case 1:
            return ready[0].serial
        default:
            throw MCPToolError.noDevice(
                "Multiple devices are connected. Pass serial explicitly. Connected: "
                    + ready.map(\.serial).joined(separator: ", "))
        }
    }

    // MARK: Screenshot

    func screenshot(serial: String) throws -> Data {
        let result = try run(
            arguments: ["-s", serial, "exec-out", "screencap", "-p"],
            timeout: MCPToolPlanner.screenshotTimeout)
        let data = result.stdout
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        if data.count >= pngSignature.count,
            Array(data.prefix(pngSignature.count)) == pngSignature
        {
            return data
        }
        if result.status != 0 || !result.trimmedError.isEmpty {
            throw MCPToolError.executionFailed(
                "Screenshot failed: \(result.trimmedError.isEmpty ? result.trimmedOutput : result.trimmedError)")
        }
        throw MCPToolError.executionFailed(
            "ADB returned no PNG. This adb version may not support exec-out; update "
                + "platform-tools.")
    }

    // MARK: Companion bridge (clipboard + notifications)

    func companionCall(
        serial: String, command: String, argument: String = "",
        timeout: TimeInterval = MCPToolPlanner.companionTimeout
    ) throws -> String {
        let companionPort = try companionPort(for: serial)

        if !companionReady.contains(serial) {
            _ = try? run(
                arguments: [
                    "-s", serial, "shell", "am", "start-foreground-service", "-n",
                    "com.senpai.androlaunch.companion/.CompanionService",
                    "--es", "token", CompanionAuth.token,
                ], timeout: 10)
            Thread.sleep(forTimeInterval: 0.35)
        }

        var lastError: Error = MCPToolError.companionUnavailable(
            "AndroLaunch Comp did not answer.")
        for attempt in 0..<3 {
            do {
                let response = try tcpRequest(
                    port: companionPort,
                    line: Self.companionRequestLine(command: command, argument: argument),
                    timeout: timeout)
                let payload = try Self.parseCompanionResponse(response)
                companionReady.insert(serial)
                return payload
            } catch {
                lastError = error
                companionReady.remove(serial)
                if attempt < 2 {
                    Thread.sleep(forTimeInterval: 0.3)
                }
            }
        }
        companionPorts.removeValue(forKey: serial)
        if case MCPToolError.companionUnavailable(let message) = lastError {
            throw MCPToolError.companionUnavailable(
                message
                    + " Install and start AndroLaunch Comp from the Hub → Wi-Fi → Mobile app tab.")
        }
        throw lastError
    }

    /// Asks adb for a free host port and remembers it per connected phone.
    private func companionPort(for serial: String) throws -> UInt16 {
        if let existing = companionPorts[serial] { return existing }
        let result = try run(
            arguments: ["-s", serial, "forward", "tcp:0", "tcp:27777"], timeout: 10)
        let raw = result.trimmedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = UInt16(raw), port > 0 else {
            throw MCPToolError.executionFailed(
                "Could not allocate a local ADB port for \(serial): "
                    + (raw.isEmpty ? result.trimmedError : raw))
        }
        companionPorts[serial] = port
        return port
    }

    private var companionReady: Set<String> = []

    static func companionRequestLine(command: String, argument: String) -> String {
        let id = CompanionAuth.requestID()
        let encoded = Data(argument.utf8).base64EncodedString()
        return "\(id)\t\(command)\t\(encoded)\n"
    }

    static func parseCompanionResponse(_ line: String) throws -> String {
        let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            throw MCPToolError.companionUnavailable(
                "Malformed response from AndroLaunch Comp.")
        }
        let status = String(parts[1])
        let payload: String
        if parts.count > 2 {
            let data = Data(base64Encoded: String(parts[2])) ?? Data()
            payload = String(decoding: data, as: UTF8.self)
        } else {
            payload = ""
        }
        if status == "ok" { return payload }
        throw MCPToolError.companionUnavailable(
            payload.isEmpty ? "AndroLaunch Comp reported an error." : payload)
    }

    // MARK: Loopback TCP

    #if canImport(Darwin)
        private func tcpRequest(port: UInt16, line: String, timeout: TimeInterval) throws -> String {
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            guard descriptor >= 0 else {
                throw MCPToolError.companionUnavailable("Could not create a loopback socket.")
            }
            defer { close(descriptor) }

            var receiveTimeout = timeval(
                tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
            var sendTimeout = receiveTimeout
            setsockopt(
                descriptor, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout,
                socklen_t(MemoryLayout<timeval>.size))
            setsockopt(
                descriptor, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout,
                socklen_t(MemoryLayout<timeval>.size))

            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let connectResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard connectResult == 0 else {
                throw MCPToolError.companionUnavailable(
                    "Could not reach AndroLaunch Comp over the ADB forward.")
            }

            let bytes = Array(line.utf8)
            var written = 0
            while written < bytes.count {
                let count = bytes.withUnsafeBytes { buffer -> Int in
                    let base = buffer.baseAddress!.advanced(by: written)
                    return write(descriptor, base, bytes.count - written)
                }
                guard count > 0 else {
                    throw MCPToolError.companionUnavailable(
                        "AndroLaunch Comp closed the connection while sending.")
                }
                written += count
            }

            var response = Data()
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
                let count = read(descriptor, &buffer, buffer.count)
                if count <= 0 { break }
                response.append(contentsOf: buffer[0..<count])
                if response.contains(0x0A) { break }
                if response.count > 8 * 1024 * 1024 {
                    throw MCPToolError.companionUnavailable(
                        "AndroLaunch Comp response was too large.")
                }
            }
            guard let newline = response.firstIndex(of: 0x0A) else {
                throw MCPToolError.companionUnavailable(
                    response.isEmpty
                        ? "AndroLaunch Comp returned no response."
                        : "AndroLaunch Comp returned an incomplete response.")
            }
            return String(decoding: response[..<newline], as: UTF8.self)
        }
    #else
        private func tcpRequest(port: UInt16, line: String, timeout: TimeInterval) throws -> String {
            throw MCPToolError.companionUnavailable(
                "The loopback companion bridge is only available on macOS.")
        }
    #endif
}

// MARK: - Pipe collection

private final class MCPDataBox {
    var stdout = Data()
    var stderr = Data()
}
