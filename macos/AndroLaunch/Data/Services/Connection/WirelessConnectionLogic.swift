//
//  WirelessConnectionLogic.swift
//  AndroLaunch
//
//  Foundation-only validation and response interpretation for the Wi-Fi
//  connection surfaces. Keeping this pure (no ADB, no networking, no SwiftUI)
//  means the rules the UI enforces can be exercised by the plain `swiftc`
//  logic tests instead of only by a live phone.
//

import Darwin
import Foundation

// MARK: - Addresses

/// A validated `host:port` wireless ADB endpoint.
///
/// Only numeric literals are accepted. Android's wireless ADB address is always
/// an IP address and the port shown on the phone's Wireless debugging screen;
/// accepting arbitrary hostnames here would produce a `connect` failure after
/// the user has already committed to it.
struct WirelessEndpoint: Equatable {
    enum AddressError: Error, Equatable {
        case empty
        case invalidIPv4
        case invalidIPv6
        case invalidPort
        case portRequired
        case unsupported

        /// One-line, actionable message shown directly under the field.
        var message: String {
            switch self {
            case .empty:
                return "Enter an address."
            case .invalidIPv4:
                return "Enter a valid IPv4 address."
            case .invalidIPv6:
                return "Enter IPv6 addresses as [address]:port."
            case .invalidPort:
                return "Enter a port from 1 to 65535."
            case .portRequired:
                return "Enter the port shown on the device."
            case .unsupported:
                return "Use only an IP address and port."
            }
        }

        /// Optional second line for the inline error state.
        var guidance: String? {
            switch self {
            case .empty:
                return nil
            case .invalidIPv4, .invalidIPv6:
                return "Find the address under Wireless debugging on the phone."
            case .invalidPort, .portRequired:
                return "The phone shows it as a four-digit port after the IP address."
            case .unsupported:
                return "Hostnames are not supported. Enter a numeric IP address and port."
            }
        }
    }

    let host: String
    let port: UInt16

    var isIPv6: Bool { host.contains(":") }

    /// Canonical form passed to `adb connect` and shown in the UI.
    var displayValue: String {
        isIPv6 ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    static func parse(_ raw: String) -> Result<WirelessEndpoint, AddressError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard !trimmed.contains(where: \.isWhitespace) else { return .failure(.unsupported) }

        // Bracketed IPv6: [address]:port. A zone id (fe80::1%en0) is allowed
        // inside the brackets because macOS reports link-local scoped addresses.
        if trimmed.hasPrefix("[") {
            guard let closing = trimmed.firstIndex(of: "]") else { return .failure(.invalidIPv6) }
            let host = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closing])
            guard !host.isEmpty, isIPv6Literal(host) else { return .failure(.invalidIPv6) }
            let remainder = trimmed[trimmed.index(after: closing)...]
            guard remainder.hasPrefix(":") else { return .failure(.portRequired) }
            guard let port = parsePort(String(remainder.dropFirst())) else {
                return .failure(.invalidPort)
            }
            return .success(WirelessEndpoint(host: host, port: port))
        }

        let colonCount = trimmed.filter { $0 == ":" }.count
        switch colonCount {
        case 0:
            // A bare IP (or hostname) has no port; the phone always shows one.
            return .failure(.portRequired)
        case 1:
            let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return .failure(.unsupported) }
            let host = String(parts[0])
            let portText = String(parts[1])
            guard !host.isEmpty else { return .failure(.invalidIPv4) }
            guard isIPv4Literal(host) else {
                // Letters in the host mean a hostname; tell the user exactly why
                // it is rejected instead of hiding it behind "invalid IPv4".
                return host.contains(where: { $0.isLetter })
                    ? .failure(.unsupported) : .failure(.invalidIPv4)
            }
            guard !portText.isEmpty else { return .failure(.portRequired) }
            guard let port = parsePort(portText) else { return .failure(.invalidPort) }
            return .success(WirelessEndpoint(host: host, port: port))
        default:
            // Multiple colons without brackets is either a bare IPv6 literal or
            // a malformed address; both need the bracketed form to disambiguate
            // the port.
            return .failure(.invalidIPv6)
        }
    }

    static func isValid(_ raw: String) -> Bool {
        if case .success = parse(raw) { return true }
        return false
    }

    // MARK: Parsing helpers

    private static func parsePort(_ text: String) -> UInt16? {
        guard !text.isEmpty,
            text.allSatisfy({ $0.isASCII && $0.isNumber }),
            let value = UInt16(text),
            value > 0
        else { return nil }
        return value
    }

    private static func isIPv4Literal(_ text: String) -> Bool {
        var address = in_addr()
        return text.withCString { inet_pton(AF_INET, $0, &address) } == 1
    }

    private static func isIPv6Literal(_ text: String) -> Bool {
        var addressText = text
        if let percent = addressText.firstIndex(of: "%") {
            let zone = addressText[addressText.index(after: percent)...]
            guard !zone.isEmpty,
                zone.allSatisfy({
                    $0.isASCII
                        && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".")
                })
            else { return false }
            addressText = String(addressText[..<percent])
        }
        var address = in6_addr()
        return addressText.withCString { inet_pton(AF_INET6, $0, &address) } == 1
    }
}

// MARK: - Pairing code

enum WirelessPairingCode {
    static let length = 6

    static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Android always shows six digits. Anything else is a typo or a paste of
    /// an old code, and running `adb pair` with it only wastes a pairing slot.
    static func isValid(_ raw: String) -> Bool {
        let value = normalized(raw)
        return value.count == length && value.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

// MARK: - QR payload

/// The QR payload Android's Wireless debugging scanner understands.
///
/// `T:ADB` selects the ADB pairing flow, `S` is the ADB pairing service instance
/// name, and `P` is the six-digit pairing code. Android generates the same
/// shape itself (Settings → Wireless debugging → Pair device with QR code), so
/// the scanner accepts this without any companion app.
enum ADBQRCode {
    /// Android Studio convention; Android only treats `S` as an mDNS instance
    /// name, so a unique value per QR prevents pairing against a stale service
    /// left over from an earlier attempt.
    static let servicePrefix = "studio-"

    static func randomServiceName() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let suffix = String((0..<10).map { _ in alphabet.randomElement()! })
        return servicePrefix + suffix
    }

    static func payload(password: String, serviceName: String) -> String {
        "WIFI:T:ADB;S:\(serviceName);P:\(password);;"
    }

    static func randomPassword() -> String {
        String(Int.random(in: 100_000...999_999))
    }
}

// MARK: - ADB output interpretation

/// `adb connect` and `adb pair` report failure in stdout while still exiting 0,
/// so the commands below are judged by their text. The exact phrasing differs
/// between platform-tools releases; these predicates accept the documented
/// forms and default to failure when unsure.
enum ADBCommandInterpreter {
    static func pairSucceeded(_ output: String) -> Bool {
        let text = output.lowercased()
        if text.contains("failed") || text.contains("error") { return false }
        return text.contains("successfully paired") || text.contains("already paired")
    }

    static func connectSucceeded(_ output: String) -> Bool {
        let text = output.lowercased()
        let failureMarkers = [
            "failed to connect", "cannot connect", "unable to connect",
            "connection refused", "no route to host", "connection timed out",
            "timed out", "unable to start pairing", "protocol fault",
        ]
        if failureMarkers.contains(where: { text.contains($0) }) { return false }
        return text.contains("connected to") || text.contains("already connected")
            || text.contains("reconnected to")
    }

    /// Human-readable reason for a failed `adb pair`, plus the next action the
    /// user can take. Never invents a success path.
    static func pairFailureMessage(output: String) -> String {
        let text = output.lowercased()
        if text.contains("wrong password") || text.contains("incorrect")
            || text.contains("rejected") || text.contains("failed: password")
        {
            return "Pairing code incorrect or expired. Generate a new code on the phone and try again."
        }
        if text.contains("protocol fault") || text.contains("couldn't read status")
            || text.contains("undefined 0")
        {
            return "The phone closed the pairing connection. Toggle Wireless debugging off and on, then regenerate the QR code and scan it again."
        }
        if text.contains("unable to start pairing client") || text.contains("connection refused")
            || text.contains("cannot connect")
        {
            return "Could not reach the pairing service. Keep the pairing dialog open on the phone and try again."
        }
        if text.contains("timed out") || text.contains("timeout") {
            return "The phone did not answer. Make sure both devices are on the same Wi-Fi network."
        }
        return cleanedReason(output) ?? "Could not pair with the device."
    }

    /// Human-readable reason for a failed `adb connect`.
    static func connectFailureMessage(output: String) -> String {
        let text = output.lowercased()
        if text.contains("connection refused") {
            return "The device refused the connection. The port may have changed; check Wireless debugging on the phone."
        }
        if text.contains("no route to host") || text.contains("unreachable")
            || text.contains("network is unreachable")
        {
            return "Could not reach that address. Make sure the phone is on the same Wi-Fi as this Mac."
        }
        if text.contains("timed out") || text.contains("timeout") {
            return "The connection timed out. Check the address on the phone and try again."
        }
        if text.contains("unable to connect") || text.contains("failed to connect")
            || text.contains("cannot connect")
        {
            return "Could not connect to the device. Check the current IP address and port."
        }
        return cleanedReason(output) ?? "Could not connect to the device."
    }

    private static func cleanedReason(_ output: String) -> String? {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return nil }
        let cleaned =
            first
            .replacingOccurrences(of: "adb: ", with: "")
            .replacingOccurrences(of: "error: ", with: "")
            .replacingOccurrences(of: "failed: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 160 else { return nil }
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }
}

// MARK: - `adb devices -l` parsing

/// One transport line as reported by `adb devices -l`, including devices that
/// are not usable yet (unauthorized, offline, bootloader). The Hub shows those
/// with their real state instead of hiding them.
struct ADBLinkEntry: Identifiable, Equatable {
    enum State: String, Equatable {
        case connected = "device"
        case unauthorized
        case offline
        case authorizing
        case connecting
        case recovery
        case sideload
        case bootloader
        case host
        case noPermissions = "no permissions"
        case unknown

        var displayName: String {
            switch self {
            case .connected: return "Connected"
            case .unauthorized: return "Unauthorized"
            case .offline: return "Offline"
            case .authorizing: return "Authorizing"
            case .connecting: return "Connecting"
            case .recovery: return "Recovery"
            case .sideload: return "Sideload"
            case .bootloader: return "Bootloader"
            case .host: return "Host"
            case .noPermissions: return "No permission"
            case .unknown: return "Unknown"
            }
        }

        var isUsable: Bool { self == .connected }

        /// A failed transport that the UI should explain rather than retry.
        var needsAttention: Bool {
            switch self {
            case .unauthorized, .noPermissions, .offline: return true
            default: return false
            }
        }
    }

    let id: String
    let state: State
    let model: String?

    var displayName: String {
        guard let model, !model.isEmpty else { return "Android device" }
        return model.replacingOccurrences(of: "_", with: " ")
    }
}

enum ADBDeviceListParser {
    static func parse(_ output: String) -> [ADBLinkEntry] {
        var entries: [ADBLinkEntry] = []
        var seen = Set<String>()

        output.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                !trimmed.lowercased().contains("list of devices attached"),
                !trimmed.hasPrefix("*"),
                !trimmed.hasPrefix("adb ")
            else { return }

            let tokens = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let rawID = tokens.first.map(String.init), !rawID.isEmpty else { return }

            // "no permissions (user in plugdev group; ...)" is two tokens.
            var stateToken = tokens.count > 1 ? String(tokens[1]) : ""
            if stateToken == "no", tokens.count > 2, tokens[2].hasPrefix("permissions") {
                stateToken = "no permissions"
            }
            guard let state = state(from: stateToken) else { return }
            guard seen.insert(rawID).inserted else { return }

            let model = extractModel(from: trimmed)
            entries.append(ADBLinkEntry(id: rawID, state: state, model: model))
        }
        return entries
    }

    private static func state(from token: String) -> ADBLinkEntry.State? {
        switch token {
        case "device": return .connected
        case "unauthorized": return .unauthorized
        case "offline": return .offline
        case "authorizing": return .authorizing
        case "connecting": return .connecting
        case "recovery": return .recovery
        case "sideload": return .sideload
        case "bootloader": return .bootloader
        case "host": return .host
        case "no permissions": return .noPermissions
        case "": return nil
        default: return .unknown
        }
    }

    private static func extractModel(from line: String) -> String? {
        guard let range = line.range(of: "model:") else { return nil }
        let remainder = line[range.upperBound...]
        let value = remainder.prefix { !$0.isWhitespace }
        return value.isEmpty ? nil : String(value)
    }
}
