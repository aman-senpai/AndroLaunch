//
//  MCPToolPlanner.swift
//  AndroLaunch
//
//  Turns a `tools/call` name + arguments object into one concrete device action.
//  This layer is pure: it validates arguments, escapes text for `adb shell` and
//  decides which transport each tool uses. The executor in `MCPToolExecutor`
//  only runs the plan. Keeping it pure means the security-relevant rules (text
//  limits, package/serial validation, key mapping) are testable without ADB.
//

import Foundation

// MARK: - Errors

enum MCPToolError: Error, Equatable, CustomStringConvertible {
    case unknownTool(String)
    case missingArgument(String)
    case invalidArgument(String)
    case textTooLong(field: String, max: Int)
    case noDevice(String)
    case adbUnavailable(String)
    case companionUnavailable(String)
    case executionFailed(String)
    case disabled
    case stopped

    var description: String {
        switch self {
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .missingArgument(let field):
            return "Missing required argument: \(field)"
        case .invalidArgument(let message):
            return message
        case .textTooLong(let field, let max):
            return "\(field) is too long (maximum \(max) characters)"
        case .noDevice(let message):
            return message
        case .adbUnavailable(let message):
            return "ADB is unavailable: \(message)"
        case .companionUnavailable(let message):
            return "AndroLaunch Comp is unavailable: \(message)"
        case .executionFailed(let message):
            return message
        case .disabled:
            return "Android Use is turned off. Turn it on in AndroLaunch → Settings → AI."
        case .stopped:
            return "Android Use was stopped from AndroLaunch Settings"
        }
    }
}

// MARK: - Plan

enum MCPToolPlan: Equatable {
    /// `arguments` is the full ADB argument list, already including `-s serial`
    /// when a serial is known.
    case adb(serial: String?, arguments: [String], timeout: TimeInterval, requiresDevice: Bool)
    case screenshot(serial: String?)
    case companion(serial: String?, command: String, argument: String)
    case notifications(serial: String?)
    case launchApp(serial: String?, package: String)

    var serial: String? {
        switch self {
        case .adb(let serial, _, _, _): return serial
        case .screenshot(let serial): return serial
        case .companion(let serial, _, _): return serial
        case .notifications(let serial): return serial
        case .launchApp(let serial, _): return serial
        }
    }

    var requiresDevice: Bool {
        switch self {
        case .adb(_, _, _, let requiresDevice): return requiresDevice
        case .screenshot, .companion, .notifications, .launchApp: return true
        }
    }
}

// MARK: - Planner

enum MCPToolPlanner {
    static let defaultTimeout: TimeInterval = 25
    static let screenshotTimeout: TimeInterval = 30
    static let companionTimeout: TimeInterval = 8

    static func plan(tool: String, arguments: [String: Any]) throws -> MCPToolPlan {
        switch tool {
        case "phone_list_devices":
            return .adb(
                serial: nil,
                arguments: ["devices", "-l"],
                timeout: 15,
                requiresDevice: false)

        case "phone_device_info":
            let serial = try optionalSerial(arguments)
            return .adb(
                serial: serial,
                arguments: adbArguments(
                    serial,
                    ["shell", "getprop ro.product.model; getprop ro.build.version.release; "
                        + "getprop ro.build.version.sdk; getprop ro.serialno; dumpsys battery"]),
                timeout: defaultTimeout,
                requiresDevice: true)

        case "phone_screenshot":
            return .screenshot(serial: try optionalSerial(arguments))

        case "phone_tap":
            let serial = try optionalSerial(arguments)
            let x = try requiredInt(arguments, "x", minimum: 0, maximum: 20000)
            let y = try requiredInt(arguments, "y", minimum: 0, maximum: 20000)
            return .adb(
                serial: serial,
                arguments: adbArguments(
                    serial, ["shell", "input tap \(x) \(y)"]),
                timeout: defaultTimeout,
                requiresDevice: true)

        case "phone_swipe":
            let serial = try optionalSerial(arguments)
            let x1 = try requiredInt(arguments, "x1", minimum: 0, maximum: 20000)
            let y1 = try requiredInt(arguments, "y1", minimum: 0, maximum: 20000)
            let x2 = try requiredInt(arguments, "x2", minimum: 0, maximum: 20000)
            let y2 = try requiredInt(arguments, "y2", minimum: 0, maximum: 20000)
            let duration = try optionalInt(
                arguments, "duration_ms", minimum: 1, maximum: 10000, fallback: 300)
            return .adb(
                serial: serial,
                arguments: adbArguments(
                    serial,
                    ["shell", "input swipe \(x1) \(y1) \(x2) \(y2) \(duration)"]),
                timeout: defaultTimeout,
                requiresDevice: true)

        case "phone_input_text":
            let serial = try optionalSerial(arguments)
            let text = try requiredString(arguments, "text", maxLength: 2000)
            let quoted = try MCPInputEscaping.inputText(text)
            return .adb(
                serial: serial,
                arguments: adbArguments(serial, ["shell", "input text \(quoted)"]),
                timeout: defaultTimeout,
                requiresDevice: true)

        case "phone_press_key":
            let serial = try optionalSerial(arguments)
            let rawKey = try requiredString(arguments, "key", maxLength: 32)
            let keyCode = try MCPInputEscaping.keyEvent(rawKey)
            return .adb(
                serial: serial,
                arguments: adbArguments(serial, ["shell", "input keyevent \(keyCode)"]),
                timeout: defaultTimeout,
                requiresDevice: true)

        case "phone_shell":
            let serial = try optionalSerial(arguments)
            let command = try requiredString(arguments, "command", maxLength: 4096)
            guard !command.contains("\0") else {
                throw MCPToolError.invalidArgument("command contains a NUL byte")
            }
            return .adb(
                serial: serial,
                arguments: adbArguments(serial, ["shell", command]),
                timeout: 40,
                requiresDevice: true)

        case "phone_list_apps":
            let serial = try optionalSerial(arguments)
            let includeSystem = try optionalBool(
                arguments, "include_system", fallback: false)
            let command = includeSystem ? "pm list packages" : "pm list packages -3"
            return .adb(
                serial: serial,
                arguments: adbArguments(serial, ["shell", command]),
                timeout: defaultTimeout,
                requiresDevice: true)

        case "phone_launch_app":
            let serial = try optionalSerial(arguments)
            let package = try requiredString(arguments, "package", maxLength: 255)
            guard MCPPackageName.isValid(package) else {
                throw MCPToolError.invalidArgument(
                    "package must be an Android package name, for example com.android.settings")
            }
            return .launchApp(serial: serial, package: package)

        case "phone_clipboard_get":
            return .companion(
                serial: try optionalSerial(arguments),
                command: "clip.get",
                argument: "")

        case "phone_clipboard_set":
            let text = try requiredString(arguments, "text", maxLength: 32000)
            return .companion(
                serial: try optionalSerial(arguments),
                command: "clip.set",
                argument: text)

        case "phone_notifications":
            return .notifications(serial: try optionalSerial(arguments))

        case "phone_open_url":
            let serial = try optionalSerial(arguments)
            let rawURL = try requiredString(arguments, "url", maxLength: 2048)
            guard MCPURL.isOpenable(rawURL) else {
                throw MCPToolError.invalidArgument(
                    "url must be an absolute http or https URL")
            }
            return .adb(
                serial: serial,
                arguments: adbArguments(
                    serial,
                    ["shell", "am start -a android.intent.action.VIEW -d "
                        + MCPInputEscaping.shellQuote(rawURL)]),
                timeout: defaultTimeout,
                requiresDevice: true)

        case "phone_ui_dump":
            let serial = try optionalSerial(arguments)
            return .adb(
                serial: serial,
                arguments: adbArguments(
                    serial,
                    [
                        "shell",
                        "uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1; "
                            + "cat /sdcard/window_dump.xml",
                    ]),
                timeout: 30,
                requiresDevice: true)

        default:
            throw MCPToolError.unknownTool(tool)
        }
    }

    // MARK: - Argument helpers

    static func optionalSerial(_ arguments: [String: Any]) throws -> String? {
        guard let raw = arguments["serial"], !(raw is NSNull) else { return nil }
        guard let serial = raw as? String else {
            throw MCPToolError.invalidArgument("serial must be a string")
        }
        let trimmed = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, MCPDeviceID.isValid(trimmed) else {
            throw MCPToolError.invalidArgument(
                "serial contains characters that are not allowed in an ADB serial")
        }
        return trimmed
    }

    static func requiredString(
        _ arguments: [String: Any], _ key: String, maxLength: Int
    ) throws -> String {
        guard let raw = arguments[key] else {
            throw MCPToolError.missingArgument(key)
        }
        guard let value = raw as? String else {
            throw MCPToolError.invalidArgument("\(key) must be a string")
        }
        guard !value.isEmpty else {
            throw MCPToolError.invalidArgument("\(key) must not be empty")
        }
        guard value.count <= maxLength else {
            throw MCPToolError.textTooLong(field: key, max: maxLength)
        }
        return value
    }

    static func requiredInt(
        _ arguments: [String: Any], _ key: String, minimum: Int, maximum: Int
    ) throws -> Int {
        guard let raw = arguments[key] else {
            throw MCPToolError.missingArgument(key)
        }
        return try intValue(raw, key: key, minimum: minimum, maximum: maximum)
    }

    static func optionalInt(
        _ arguments: [String: Any], _ key: String, minimum: Int, maximum: Int, fallback: Int
    ) throws -> Int {
        guard let raw = arguments[key], !(raw is NSNull) else { return fallback }
        return try intValue(raw, key: key, minimum: minimum, maximum: maximum)
    }

    static func optionalBool(
        _ arguments: [String: Any], _ key: String, fallback: Bool
    ) throws -> Bool {
        guard let raw = arguments[key], !(raw is NSNull) else { return fallback }
        if let value = raw as? Bool { return value }
        if let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue
        }
        throw MCPToolError.invalidArgument("\(key) must be a boolean")
    }

    private static func intValue(
        _ raw: Any, key: String, minimum: Int, maximum: Int
    ) throws -> Int {
        let value: Int
        if let number = raw as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        {
            let double = number.doubleValue
            guard double.rounded() == double else {
                throw MCPToolError.invalidArgument("\(key) must be a whole number")
            }
            value = Int(double)
        } else {
            throw MCPToolError.invalidArgument("\(key) must be a number")
        }
        guard value >= minimum, value <= maximum else {
            throw MCPToolError.invalidArgument(
                "\(key) must be between \(minimum) and \(maximum)")
        }
        return value
    }

    private static func adbArguments(_ serial: String?, _ rest: [String]) -> [String] {
        guard let serial else { return rest }
        return ["-s", serial] + rest
    }
}

// MARK: - Escaping

/// Shell/text escaping rules for `adb shell` on Android's `input` command.
enum MCPInputEscaping {
    /// POSIX single-quote escaping. Inside single quotes every character is
    /// literal except `'`, which is closed, escaped and reopened.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Android's `input text` converts `%s` to a space; spaces inside the shell
    /// argument are therefore encoded rather than sent raw. Newlines cannot be
    /// typed with `input text`, so they are rejected instead of silently lost.
    static func inputText(_ text: String) throws -> String {
        guard !text.contains("\n"), !text.contains("\r") else {
            throw MCPToolError.invalidArgument("text must be a single line")
        }
        let encoded = text.replacingOccurrences(of: " ", with: "%s")
        return shellQuote(encoded)
    }

    /// Name → Android keycode. Numeric keycodes pass through when in range.
    static let keyCodes: [String: String] = [
        "home": "3",
        "back": "4",
        "recents": "187",
        "recentapps": "187",
        "appswitch": "187",
        "enter": "66",
        "power": "26",
        "volumeup": "24",
        "volumedown": "25",
        "mute": "164",
        "menu": "82",
        "camera": "27",
        "delete": "67",
        "del": "67",
        "tab": "61",
        "escape": "111",
        "esc": "111",
        "space": "62",
        "wakeup": "224",
        "sleep": "223",
        "dpadup": "19",
        "dpaddown": "20",
        "dpadleft": "21",
        "dpadright": "22",
        "dpadcenter": "23",
        "mediaplaypause": "85",
    ]

    static func keyEvent(_ key: String) throws -> String {
        let normalized =
            key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "keycode_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        if let code = keyCodes[normalized] { return code }
        if let number = Int(normalized), (1...999).contains(number) {
            return String(number)
        }
        throw MCPToolError.invalidArgument(
            "Unknown key \"\(key)\". Use a key name such as home, back, recents, enter "
                + "or a numeric keycode.")
    }
}

// MARK: - Validators

enum MCPDeviceID {
    /// ADB serials are USB serials, `host:port` pairs or mDNS service names.
    /// Reject anything that could confuse argument parsing or the device shell.
    static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 256 else { return false }
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

enum MCPPackageName {
    static func isValid(_ value: String) -> Bool {
        let pattern = "^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}

enum MCPURL {
    static func isOpenable(_ value: String) -> Bool {
        guard value.count <= 2048,
            !value.contains("\n"), !value.contains("\r"), !value.contains("\0")
        else { return false }
        guard let components = URLComponents(string: value),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = components.host, !host.isEmpty
        else { return false }
        return true
    }
}

// MARK: - Activity detail sanitizing

enum MCPTextSanitizer {
    /// Activity rows are metadata only. Details are forced onto one line and
    /// bounded so a tool result can never be stored verbatim in the JSONL log.
    static func detail(_ value: String, max: Int = 160) -> String {
        let single =
            value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard single.count > max else { return single }
        return String(single.prefix(max)) + "…"
    }
}
