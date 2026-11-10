//
//  MCPToolExecutor.swift
//  AndroLaunch
//
//  Runs validated tool plans against ADB and turns raw output into compact,
//  useful MCP content. Every call appends one activity record (metadata only;
//  no typed text, shell command or clipboard payload is ever persisted).
//

import Foundation

final class MCPToolExecutor {
    private let adb: MCPADBClient
    private let log: MCPActivityLog
    private let isEnabled: () -> Bool

    init(
        adb: MCPADBClient = MCPADBClient(),
        log: MCPActivityLog = MCPActivityLog(),
        isEnabled: @escaping () -> Bool = { MCPRuntime.isEnabled() }
    ) {
        self.adb = adb
        self.log = log
        self.isEnabled = isEnabled
    }

    // MARK: - Entry point

    func call(tool: String, arguments: [String: Any]) -> MCPCallResult {
        let startedAt = Date()
        var loggedDevice: String?
        do {
            guard isEnabled() else {
                throw MCPToolError.disabled
            }
            let plan = try MCPToolPlanner.plan(tool: tool, arguments: arguments)
            if plan.requiresDevice, plan.serial == nil {
                loggedDevice = try adb.resolveSerial(nil)
            } else {
                loggedDevice = plan.serial
            }
            let result = try execute(plan)
            record(tool: tool, device: loggedDevice, ok: !result.isError, since: startedAt,
                   detail: result.isError ? "Tool reported an error" : "Completed")
            return result
        } catch {
            let message = Self.message(for: error)
            let device = loggedDevice ?? ((try? MCPToolPlanner.optionalSerial(arguments)) ?? nil)
            record(tool: tool, device: device, ok: false, since: startedAt,
                   detail: Self.activityDetail(for: error))
            return .failure(message)
        }
    }

    // MARK: - Execution

    private func execute(_ plan: MCPToolPlan) throws -> MCPCallResult {
        switch plan {
        case .adb(let serial, let arguments, let timeout, let requiresDevice):
            let resolvedSerial = requiresDevice ? try adb.resolveSerial(serial) : serial
            var result: MCPADBRunResult
            if let resolvedSerial {
                result = try adb.run(
                    arguments: Self.adbArgumentsWithSerial(resolvedSerial, arguments),
                    timeout: timeout)
            } else {
                result = try adb.run(arguments: arguments, timeout: timeout)
            }
            return try adbResult(result, plan: plan, resolvedSerial: resolvedSerial)

        case .screenshot(let serial):
            let resolved = try adb.resolveSerial(serial)
            let data = try adb.screenshot(serial: resolved)
            let size = Self.pngDimensions(data)
            let dimensions = size.map { " · \($0.0)×\($0.1)" } ?? ""
            let caption =
                "Screenshot of \(resolved)\(dimensions) · "
                + "\(Self.byteCount(data.count)) PNG"
            return .image(base64: data.base64EncodedString(), caption: caption)

        case .companion(let serial, let command, let argument):
            let resolved = try adb.resolveSerial(serial)
            do {
                let payload = try adb.companionCall(
                    serial: resolved, command: command, argument: argument)
                switch command {
                case "clip.get":
                    let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
                    return .text(
                        text.isEmpty
                            ? "The phone clipboard is empty."
                            : "Phone clipboard (\(text.count) characters):\n\(text)")
                case "clip.set":
                    return .text(
                        "Copied \(argument.count) characters to the clipboard of \(resolved).")
                default:
                    return .text(payload.isEmpty ? "Done." : payload)
                }
            } catch {
                if let toolError = error as? MCPToolError,
                    case .companionUnavailable(let message) = toolError
                {
                    let hint: String
                    if command == "clip.get" {
                        hint =
                            " Android only allows clipboard reads while the companion has focus; "
                            + "unlock the phone and open AndroLaunch Comp, then retry."
                    } else {
                        hint = ""
                    }
                    throw MCPToolError.companionUnavailable(
                        Self.humanizeCompanionError(message) + hint)
                }
                throw error
            }

        case .notifications(let serial):
            let resolved = try adb.resolveSerial(serial)
            if let payload = try? adb.companionCall(
                serial: resolved, command: "notif.list", argument: ""),
                let formatted = Self.formatNotificationJSON(payload)
            {
                return .text(formatted)
            }
            let dump = try adb.run(
                arguments: ["-s", resolved, "shell", "dumpsys notification --noredact"],
                timeout: MCPToolPlanner.defaultTimeout)
            return .text(Self.formatDumpsysNotifications(dump.stdoutText, serial: resolved))

        case .launchApp(let serial, let package):
            let resolved = try adb.resolveSerial(serial)
            return try launchApp(package: package, serial: resolved)
        }
    }

    private func adbResult(
        _ result: MCPADBRunResult, plan: MCPToolPlan, resolvedSerial: String?
    ) throws -> MCPCallResult {
        switch plan {
        case .adb(_, let arguments, _, _):
            let command = arguments.last ?? ""
            if arguments.contains("devices") {
                let devices = MCPADBClient.parseDevices(result.stdoutText)
                return .text(Self.formatDevices(devices))
            }
            if command.contains("getprop ro.product.model") {
                return .text(
                    Self.formatDeviceInfo(
                        result.stdoutText, serial: resolvedSerial ?? "device"))
            }
            if command.contains("pm list packages") {
                return .text(Self.formatPackages(result.stdoutText))
            }
            if command.contains("uiautomator dump") {
                let xml = Self.truncate(result.trimmedOutput, max: 200_000)
                return .text(
                    xml.isEmpty
                        ? "uiautomator returned no UI hierarchy. Unlock the phone and try again."
                        : "UI hierarchy for \(resolvedSerial ?? "device"):\n\(xml)")
            }
            if command.contains("am start -a android.intent.action.VIEW") {
                guard result.status == 0, !result.trimmedOutput.lowercased().contains("error") else {
                    throw MCPToolError.executionFailed(
                        Self.firstUsefulLine(result) ?? "The device could not open that URL.")
                }
                return .text(
                    "Opened the URL on \(resolvedSerial ?? "the device").")
            }
            guard result.status == 0 else {
                throw MCPToolError.executionFailed(
                    Self.firstUsefulLine(result) ?? "ADB command failed.")
            }
            let output = Self.truncate(result.trimmedOutput, max: 200_000)
            return .text(output.isEmpty ? "Done." : output)

        default:
            return .text(result.trimmedOutput.isEmpty ? "Done." : result.trimmedOutput)
        }
    }

    private func launchApp(package: String, serial: String) throws -> MCPCallResult {
        let resolve = try adb.run(
            arguments: [
                "-s", serial, "shell", "cmd package resolve-activity --brief " + package,
            ], timeout: MCPToolPlanner.defaultTimeout)
        let component = Self.launchComponent(from: resolve.stdoutText)
        if let component {
            let start = try adb.run(
                arguments: ["-s", serial, "shell", "am start -n " + component],
                timeout: MCPToolPlanner.defaultTimeout)
            let output = start.trimmedOutput.lowercased()
            if start.status == 0, !output.contains("error") {
                return .text("Launched \(package) on \(serial) (\(component)).")
            }
            throw MCPToolError.executionFailed(
                start.trimmedError.isEmpty
                    ? "Android refused to start \(package). The app may be disabled for this user."
                    : start.trimmedError)
        }
        // Some OEM launchers do not answer resolve-activity; monkey is the
        // documented fallback for "start the launcher activity".
        let monkey = try adb.run(
            arguments: [
                "-s", serial, "shell", "monkey", "-p", package,
                "-c", "android.intent.category.LAUNCHER", "1",
            ], timeout: MCPToolPlanner.defaultTimeout)
        let output = monkey.trimmedOutput
        if monkey.status != 0
            || output.lowercased().contains("no activities found")
            || output.lowercased().contains("monkey aborted")
        {
            throw MCPToolError.executionFailed(
                "No launchable activity was found for \(package). Check the package name with "
                    + "phone_list_apps.")
        }
        return .text("Launched \(package) on \(serial).")
    }

    // MARK: - Formatting

    static func formatDevices(_ devices: [MCPADBDevice]) -> String {
        guard !devices.isEmpty else {
            return """
                No Android devices connected.
                Connect over USB with USB debugging enabled, or pair over Wi-Fi in \
                AndroLaunch → Devices, then call phone_list_devices again.
                """
        }
        var lines = ["\(devices.count) device(s):"]
        for device in devices {
            var line = "• \(device.displayName) — \(device.serial) · \(device.state) · "
                + device.transportLabel
            if let product = device.product, product != device.model {
                line += " · \(product)"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    static func formatDeviceInfo(_ raw: String, serial: String) -> String {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var model = ""
        var release = ""
        var sdk = ""
        var hardwareSerial = ""
        var battery = ""
        var charging = false
        for (index, line) in lines.enumerated() {
            if index == 0 { model = line }
            if index == 1 { release = line }
            if index == 2 { sdk = line }
            if index == 3 { hardwareSerial = line }
            if line.contains("level:") {
                battery = line.components(separatedBy: ":").last?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            if line.contains("AC powered") || line.contains("USB powered")
                || line.contains("Wireless powered")
            {
                if line.components(separatedBy: ":").last?
                    .trimmingCharacters(in: .whitespacesAndNewlines) == "true"
                {
                    charging = true
                }
            }
        }
        var output: [String] = []
        output.append("Model: \(model.isEmpty ? "Unknown" : model)")
        if !release.isEmpty {
            output.append("Android: \(release)\(sdk.isEmpty ? "" : " (API \(sdk))")")
        }
        output.append("Serial: \(hardwareSerial.isEmpty ? serial : hardwareSerial)")
        if !battery.isEmpty {
            output.append("Battery: \(battery)%\(charging ? " (charging)" : "")")
        }
        output.append("ADB transport: \(serial)")
        return output.joined(separator: "\n")
    }

    static func formatPackages(_ raw: String) -> String {
        var packages = raw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("package:") }
            .map { String($0.dropFirst("package:".count)) }
        packages.sort()
        guard !packages.isEmpty else { return "No matching installed apps were reported." }
        return "\(packages.count) package(s):\n" + packages.joined(separator: "\n")
    }

    static func formatNotificationJSON(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
            let records = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        if records.isEmpty { return "No notifications on the phone right now." }
        // The Settings → Notifications "Hide sensitive apps" filter applies to
        // every macOS surface, including the MCP notification tool. It must not
        // be possible to read a banking/authenticator notification through AI.
        let visibleRecords = records.filter { record in
            guard NotificationPrivacy.hideSensitiveApps else { return true }
            let package = record["pkg"] as? String ?? ""
            return !NotificationPrivacy.isSensitivePackage(package)
        }
        if visibleRecords.isEmpty {
            return "No notifications are available for this tool (sensitive apps are hidden)."
        }
        var lines = ["\(visibleRecords.count) notification(s):"]
        for (index, record) in visibleRecords.prefix(50).enumerated() {
            let package = record["pkg"] as? String ?? "unknown"
            let title = record["title"] as? String ?? ""
            let text = record["text"] as? String ?? ""
            var line = "\(index + 1). \(package) — "
            if title.isEmpty && text.isEmpty {
                line += "(no preview text)"
            } else if text.isEmpty {
                line += title
            } else if title.isEmpty {
                line += text
            } else {
                line += "\(title): \(text)"
            }
            lines.append(line)
        }
        if records.count > 50 {
            lines.append("…and \(records.count - 50) more.")
        }
        return lines.joined(separator: "\n")
    }

    static func formatDumpsysNotifications(_ raw: String, serial: String) -> String {
        guard let records = NotificationDumpParser.parse(raw) else {
            return
                "The device did not expose a readable notification list. Unlock the phone and "
                + "allow notification access for AndroLaunch Comp, then try again."
        }
        if records.isEmpty { return "No notifications on \(serial) right now." }
        let visibleRecords = records.filter { record in
            guard NotificationPrivacy.hideSensitiveApps else { return true }
            return !NotificationPrivacy.isSensitivePackage(record.packageName)
        }
        if visibleRecords.isEmpty {
            return "No notifications are available for this tool (sensitive apps are hidden)."
        }
        var lines = ["\(visibleRecords.count) notification(s) from \(serial):"]
        for (index, record) in visibleRecords.prefix(50).enumerated() {
            let preview = record.displayText ?? "(no preview text)"
            lines.append("\(index + 1). \(record.packageName) — \(preview)")
        }
        if visibleRecords.count > 50 { lines.append("…and \(visibleRecords.count - 50) more.") }
        lines.append("(fallback read: install AndroLaunch Comp for action-aware notifications)")
        return lines.joined(separator: "\n")
    }

    static func pngDimensions(_ data: Data) -> (Int, Int)? {
        // PNG: 8-byte signature, then IHDR length/type, then width/height at 16..<24.
        guard data.count >= 24 else { return nil }
        let width = data[16..<20].reduce(0) { ($0 << 8) | Int($1) }
        let height = data[20..<24].reduce(0) { ($0 << 8) | Int($1) }
        guard width > 0, height > 0 else { return nil }
        return (width, height)
    }

    static func launchComponent(from resolveOutput: String) -> String? {
        let lines = resolveOutput.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return lines.last { $0.contains("/") && !$0.lowercased().contains("priority=") }
    }

    // MARK: - Helpers

    private static func adbArgumentsWithSerial(_ serial: String, _ arguments: [String]) -> [String] {
        guard arguments.first != "-s" else { return arguments }
        return ["-s", serial] + arguments
    }

    private static func byteCount(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private static func truncate(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max)) + "\n…(truncated)"
    }

    private static func firstUsefulLine(_ result: MCPADBRunResult) -> String? {
        let text = result.trimmedError.isEmpty ? result.trimmedOutput : result.trimmedError
        return text.split(separator: "\n").first.map(String.init)
    }

    private static func humanizeCompanionError(_ message: String) -> String {
        switch message.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "focus_required":
            return "The phone has not given AndroLaunch Comp clipboard focus."
        case "empty":
            return "The phone clipboard is empty."
        case "clipboard_failed", "no_clipboard_service":
            return "The phone refused clipboard access."
        case "unsupported":
            return "This phone or Android version does not support that action."
        default:
            return message
        }
    }

    // MARK: - Logging

    private func record(
        tool: String, device: String?, ok: Bool, since: Date, detail: String
    ) {
        let duration = Int(Date().timeIntervalSince(since) * 1000)
        log.append(tool: tool, device: device, ok: ok, durationMs: duration, detail: detail)
    }

    static func message(for error: Error) -> String {
        if let toolError = error as? MCPToolError { return toolError.description }
        return error.localizedDescription
    }

    /// Error text safe to persist: validation/device messages are static and
    /// payload-free; raw command failures are collapsed to a category.
    static func activityDetail(for error: Error) -> String {
        guard let toolError = error as? MCPToolError else {
            return "Failed"
        }
        switch toolError {
        case .executionFailed, .adbUnavailable:
            return "Android command failed"
        case .disabled:
            return "Android Use is off"
        case .stopped:
            return "Stopped by user"
        default:
            return MCPTextSanitizer.detail(toolError.description)
        }
    }
}
