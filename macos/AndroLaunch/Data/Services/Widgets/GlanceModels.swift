//
//  GlanceModels.swift
//  AndroLaunch
//
//  Value types for the Glance desktop board: device status, battery, storage
//  usage, quick-app shortcuts and their persistence.
//
//  WidgetKit is not shippable in this build (it needs a separate signed extension
//  target), so Glance is a real floating desktop surface instead. This file is
//  Foundation-only so its parsing and ordering logic is testable without a device.
//

import Foundation

// MARK: - Quick app shortcut

struct GlanceAppShortcut: Identifiable, Equatable {
    let packageName: String
    let name: String
    let iconName: String

    var id: String { packageName }
}

// MARK: - Transport

enum GlanceTransport: String, Equatable {
    case usb
    case wireless

    var label: String {
        switch self {
        case .usb: return "USB"
        case .wireless: return "Wi-Fi"
        }
    }

    var icon: String {
        switch self {
        case .usb: return "cable.connector"
        case .wireless: return "wifi"
        }
    }

    static func classify(deviceID: String) -> GlanceTransport {
        let lowered = deviceID.lowercased()
        if lowered.contains(":") || lowered.contains("_tcp") || lowered.contains("_udp")
            || lowered.contains(".local")
        {
            return .wireless
        }
        return .usb
    }
}

// MARK: - Storage

struct GlanceStorageUsage: Equatable {
    let totalBytes: Int64
    let usedBytes: Int64
    let freeBytes: Int64

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }

    var summary: String {
        "\(GlanceStorageProbe.formatBytes(usedBytes)) of \(GlanceStorageProbe.formatBytes(totalBytes)) used"
    }
}

enum GlanceStorageProbe {
    /// Parses `df -k /data` (1 KiB blocks). Tolerates toybox and toolbox layouts
    /// by locating the `/data` row and reading the three numeric columns after the
    /// filesystem name.
    static func parseDataPartition(dfOutput: String) -> GlanceStorageUsage? {
        for rawLine in dfOutput.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let columns = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard columns.count >= 5 else { continue }
            guard let mountIndex = columns.firstIndex(of: "/data") else { continue }
            // Filesystem … total used available [use%] /data
            guard mountIndex >= 4 else { continue }
            let numbers = columns[1..<mountIndex].compactMap { Int64($0) }
            guard numbers.count >= 3 else { continue }
            let totalKiB = numbers[0]
            let usedKiB = numbers[1]
            let freeKiB = numbers[2]
            guard totalKiB > 0, usedKiB >= 0, freeKiB >= 0 else { continue }
            return GlanceStorageUsage(
                totalBytes: totalKiB * 1024,
                usedBytes: usedKiB * 1024,
                freeBytes: freeKiB * 1024)
        }
        return nil
    }

    static func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 GB" }
        let gigabytes = Double(bytes) / 1_000_000_000
        if gigabytes >= 1 { return String(format: "%.0f GB", gigabytes) }
        let megabytes = Double(bytes) / 1_000_000
        if megabytes >= 1 { return String(format: "%.0f MB", megabytes) }
        let kilobytes = Double(bytes) / 1_000
        return String(format: "%.0f KB", max(1, kilobytes))
    }
}

// MARK: - Quick apps

enum GlanceQuickApps {
    static let limit = 8

    /// Recently used apps first, then the phone's alphabetical catalog, capped to
    /// a 4 × 2 grid.
    static func ordered(apps: [GlanceAppShortcut], pinned: [String]) -> [GlanceAppShortcut] {
        guard !apps.isEmpty else { return [] }
        let byPackage = Dictionary(apps.map { ($0.packageName, $0) }, uniquingKeysWith: { first, _ in
            first
        })
        var result: [GlanceAppShortcut] = []
        var seen = Set<String>()
        for package in pinned {
            guard let app = byPackage[package], !seen.contains(package) else { continue }
            result.append(app)
            seen.insert(package)
        }
        for app in apps where !seen.contains(app.packageName) {
            result.append(app)
            seen.insert(app.packageName)
        }
        return Array(result.prefix(limit))
    }

    /// Moves a used app to the front of the recents list and trims to the limit.
    static func recordingUse(_ packageName: String, pinned: [String]) -> [String] {
        guard !packageName.isEmpty else { return Array(pinned.prefix(limit)) }
        var updated = pinned.filter { $0 != packageName }
        updated.insert(packageName, at: 0)
        return Array(updated.prefix(limit))
    }
}

/// Persists the quick-app order so Glance reopens with the shortcuts the user
/// actually uses.
struct GlanceShortcutStore {
    static let key = "platform.glance.quickAppOrder"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var pinned: [String] {
        let stored = defaults.stringArray(forKey: Self.key) ?? []
        return Array(stored.prefix(GlanceQuickApps.limit))
    }

    @discardableResult
    func recordUse(_ packageName: String) -> [String] {
        let updated = GlanceQuickApps.recordingUse(packageName, pinned: pinned)
        defaults.set(updated, forKey: Self.key)
        return updated
    }

    func reset() {
        defaults.removeObject(forKey: Self.key)
    }
}

// MARK: - Board state

struct GlanceBoardState: Equatable {
    var deviceID: String?
    var deviceName: String = "Glance"
    var transport: GlanceTransport?
    var isConnected = false
    var batteryLevel: Int?
    var isCharging: Bool?
    var storageFraction: Double?
    var storageSummary: String?
    var apps: [GlanceAppShortcut] = []
    var isLoadingStorage = false
    var hideUntilConnected = false
    var note: String?

    var hasDevice: Bool { deviceID != nil }

    var statusText: String {
        isConnected ? "Connected" : (deviceID == nil ? "No device" : "Disconnected")
    }

    var batteryText: String {
        guard let batteryLevel else { return "—" }
        return "\(batteryLevel)%"
    }

    var chargingText: String? {
        isCharging == true ? "Charging" : nil
    }

    /// Semantic tone name for the battery bar ("success", "warning", "danger",
    /// "accent"). Kept as a string so this file stays Foundation-only.
    var batteryTone: String {
        if isCharging == true { return "success" }
        guard let batteryLevel else { return "accent" }
        if batteryLevel <= 20 { return "danger" }
        if batteryLevel <= 40 { return "warning" }
        return "accent"
    }

    var storageText: String {
        if let storageSummary { return storageSummary }
        if isLoadingStorage { return "Checking storage…" }
        return hasDevice ? "Storage unavailable" : "—"
    }

    var storageEmptyNote: String? {
        guard hasDevice, storageSummary == nil, !isLoadingStorage else { return nil }
        return "Phone storage couldn't be read yet."
    }

    var quickAppsCaption: String {
        apps.isEmpty
            ? "App shortcuts appear when the phone's apps finish loading."
            : "Open on your Mac"
    }
}

// MARK: - Actions

struct GlanceBoardActions {
    var openApp: (GlanceAppShortcut) -> Void = { _ in }
    var openHub: () -> Void = {}
    var close: () -> Void = {}
    var setHideUntilConnected: (Bool) -> Void = { _ in }
    var refresh: () -> Void = {}
}
