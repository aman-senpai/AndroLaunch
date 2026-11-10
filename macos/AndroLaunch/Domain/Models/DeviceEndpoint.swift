//
//  DeviceEndpoint.swift
//  AndroLaunch
//
//  One reachable transport for a physical Android device. A device can expose
//  several endpoints at once (USB cable, LAN address, Bonjour service, a manual
//  or VPN address), so endpoints are recorded per device identity and raced
//  against each other instead of every endpoint being its own "device".
//

import Foundation

enum TransportKind: String, Codable, CaseIterable {
    case usb
    case wireless
    case mdns
    case manual

    var displayName: String {
        switch self {
        case .usb: return "USB"
        case .wireless: return "Wi-Fi"
        case .mdns: return "Bonjour"
        case .manual: return "Network"
        }
    }

    var symbolName: String {
        switch self {
        case .usb: return "cable.connector"
        case .wireless: return "wifi"
        case .mdns: return "bonjour"
        case .manual: return "network"
        }
    }

    var isWireless: Bool { self != .usb }

    /// Ranking used when racing endpoints: a wired link is preferred, Bonjour
    /// is preferred over a remembered IP because DHCP makes stored addresses stale.
    var raceRank: Int {
        switch self {
        case .usb: return 0
        case .mdns: return 1
        case .wireless: return 2
        case .manual: return 3
        }
    }

    /// Classifies an ADB serial the way `adb devices` reports it.
    static func classify(_ address: String) -> TransportKind {
        if isMDNSService(address) { return .mdns }
        if isHostAndPort(address) { return .wireless }
        return .usb
    }

    static func isMDNSService(_ address: String) -> Bool {
        let lowered = address.lowercased()
        return lowered.contains("._adb")
            || lowered.contains("_tcp")
            || lowered.contains("_udp")
    }

    /// `host:port` with a numeric port. USB serials and `emulator-5554` never contain a colon.
    static func isHostAndPort(_ address: String) -> Bool {
        guard let colon = address.lastIndex(of: ":") else { return false }
        let host = address[..<colon]
        let port = address[address.index(after: colon)...]
        guard !host.isEmpty, let portNumber = Int(port), (1...65535).contains(portNumber) else {
            return false
        }
        return true
    }
}

struct DeviceEndpoint: Codable, Identifiable, Hashable {
    var address: String
    var kind: TransportKind
    var lastSeen: Date
    var lastConnected: Date?
    var successfulConnections: Int
    var failedAttempts: Int
    var isUserAdded: Bool

    init(
        address: String,
        kind: TransportKind? = nil,
        lastSeen: Date = Date(),
        lastConnected: Date? = nil,
        successfulConnections: Int = 0,
        failedAttempts: Int = 0,
        isUserAdded: Bool = false
    ) {
        self.address = address
        self.kind = kind ?? TransportKind.classify(address)
        self.lastSeen = lastSeen
        self.lastConnected = lastConnected
        self.successfulConnections = successfulConnections
        self.failedAttempts = failedAttempts
        self.isUserAdded = isUserAdded
    }

    var id: String { address }
    var isWireless: Bool { kind.isWireless }

    /// Health used to decide whether an endpoint is still worth racing.
    var isTrusted: Bool { successfulConnections > 0 && failedAttempts < 3 }

    var isStale: Bool {
        guard failedAttempts >= 3 else { return false }
        let age = Date().timeIntervalSince(lastSeen)
        return age > 60 * 60 * 24
    }

    /// Short label for menus: "Wi-Fi 192.168.1.5:5555".
    var shortLabel: String {
        if kind == .mdns {
            let head = address.split(separator: ".").first.map(String.init) ?? address
            return "Bonjour \(head)"
        }
        return "\(kind.displayName) \(address)"
    }
}
