//
//  StorageAnalyticsModels.swift
//  AndroLaunch
//
//  Foundation-only models and parsers for storage analytics: volumes, category
//  breakdowns and donut geometry, plus the txt parsers used by `StorageService`.
//
//  Keeping this file free of AppKit/Combine lets `scripts/test-macos-logic.sh`
//  compile the exact parsing the app performs.
//

import Foundation

// MARK: - Categories

enum StorageCategoryRole: String, CaseIterable, Identifiable, Equatable {
    case apps
    case userFiles
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: return "Apps"
        case .userFiles: return "User files"
        case .system: return "System & Others"
        }
    }

    var icon: String {
        switch self {
        case .apps: return "square.grid.2x2.fill"
        case .userFiles: return "folder.fill"
        case .system: return "gearshape.2.fill"
        }
    }

    /// Palette role name; the SwiftUI layer maps it onto HubTheme tokens.
    var tone: String {
        switch self {
        case .apps: return "accent"
        case .userFiles: return "success"
        case .system: return "tertiary"
        }
    }

    /// Explanation shown when a category cannot be drilled into on Android.
    var drilldownNote: String? {
        switch self {
        case .apps:
            return
                "Android does not expose per-app sizes to adb without root. Open Apps to see installed packages, or use the phone's own Settings → Storage for per-app detail."
        case .system:
            return "System & Others is the remainder of the volume: system image, caches, filesystem overhead and data Android does not expose to adb."
        case .userFiles:
            return nil
        }
    }
}

struct StorageCategory: Identifiable, Equatable {
    let role: StorageCategoryRole
    let bytes: Int64
    /// True when the number could not be measured completely.
    let isPartial: Bool

    init(role: StorageCategoryRole, bytes: Int64, isPartial: Bool = false) {
        self.role = role
        self.bytes = max(0, bytes)
        self.isPartial = isPartial
    }

    var id: String { role.rawValue }
    var title: String { role.title }
}

// MARK: - Volumes

enum StorageVolumeKind: String, Equatable {
    case internalStorage
    case sharedStorage
    case removable

    var title: String {
        switch self {
        case .internalStorage: return "Internal storage"
        case .sharedStorage: return "Shared storage"
        case .removable: return "SD card"
        }
    }
}

struct StorageVolume: Identifiable, Equatable {
    let id: String
    let kind: StorageVolumeKind
    let title: String
    /// Device path this volume was measured from.
    let mountPath: String
    let totalBytes: Int64
    let usedBytes: Int64
    let freeBytes: Int64
    let categories: [StorageCategory]
    let folders: [StorageFolder]
    let isPartial: Bool

    var isRemovable: Bool { kind == .removable }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }

    var freeFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(freeBytes) / Double(totalBytes)))
    }

    var usedPercentText: String {
        "\(Int((usedFraction * 100).rounded()))%"
    }

    var usedOfTotalText: String {
        PhoneFormat.usedOfTotal(used: usedBytes, total: totalBytes)
    }

    var freeText: String {
        "\(PhoneFormat.bytes(freeBytes)) free"
    }

    /// A measurable volume has its own capacity from `df`.
    var hasOwnCapacity: Bool { totalBytes > 0 }

    func fraction(for folder: StorageFolder) -> Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(folder.bytes) / Double(totalBytes))
    }
}

// MARK: - Snapshot

struct StorageSnapshot: Equatable {
    enum Source: String, Equatable {
        case companion
        case adb
    }

    // Compatibility fields used by the storage sheet and menu rows.
    let deviceID: String
    let totalBytes: Int64
    let usedBytes: Int64
    let freeBytes: Int64
    let folders: [StorageFolder]
    let largestItems: [StorageItem]
    let scannedAt: Date
    let source: Source
    let folderListComplete: Bool

    // Expanded analytics.
    let internalVolume: StorageVolume?
    let sharedStorage: StorageVolume?
    let removableVolumes: [StorageVolume]
    let partialReasons: [String]

    init(
        deviceID: String,
        totalBytes: Int64,
        usedBytes: Int64,
        freeBytes: Int64,
        folders: [StorageFolder],
        largestItems: [StorageItem],
        scannedAt: Date,
        source: Source,
        folderListComplete: Bool,
        internalVolume: StorageVolume? = nil,
        sharedStorage: StorageVolume? = nil,
        removableVolumes: [StorageVolume] = [],
        partialReasons: [String] = []
    ) {
        self.deviceID = deviceID
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
        self.folders = folders
        self.largestItems = largestItems
        self.scannedAt = scannedAt
        self.source = source
        self.folderListComplete = folderListComplete
        self.internalVolume = internalVolume
        self.sharedStorage = sharedStorage
        self.removableVolumes = removableVolumes
        self.partialReasons = partialReasons
    }

    var isPartial: Bool {
        !partialReasons.isEmpty || !folderListComplete
            || internalVolume?.isPartial == true
            || removableVolumes.contains { $0.isPartial }
    }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }

    var freeFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(freeBytes) / Double(totalBytes)))
    }

    var usedOfTotalText: String {
        PhoneFormat.usedOfTotal(used: usedBytes, total: totalBytes)
    }

    var freeText: String {
        "\(PhoneFormat.bytes(freeBytes)) free"
    }

    func fraction(for folder: StorageFolder) -> Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(folder.bytes) / Double(totalBytes))
    }

    /// Every measured volume, internal first.
    var allVolumes: [StorageVolume] {
        [internalVolume].compactMap { $0 } + removableVolumes
    }
}

// MARK: - Donut geometry

struct StorageDonutArc: Identifiable, Equatable {
    let role: StorageCategoryRole
    /// Fractions of the full circle, already offset for the visual gap.
    let start: Double
    let end: Double

    var id: String { role.rawValue }
    var span: Double { max(0, end - start) }
}

enum StorageDonutMath {
    /// Fraction of the volume that is used. Clamped so a bad `df` row cannot draw
    /// outside the ring.
    static func usedFraction(usedBytes: Int64, totalBytes: Int64) -> Double {
        guard totalBytes > 0, usedBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }

    static func freeFraction(usedBytes: Int64, totalBytes: Int64) -> Double {
        1 - usedFraction(usedBytes: usedBytes, totalBytes: totalBytes)
    }

    /// Category arcs occupy the used part of the ring; free space stays empty.
    /// A tiny visual gap separates arcs, but never enough to erase a small one.
    static func arcs(
        categories: [StorageCategory],
        usedBytes: Int64,
        totalBytes: Int64
    ) -> [StorageDonutArc] {
        guard totalBytes > 0 else { return [] }
        let usedFraction = usedFraction(usedBytes: usedBytes, totalBytes: totalBytes)
        let categoryTotal = categories.reduce(Int64(0)) { $0 + $1.bytes }
        guard categoryTotal > 0, usedFraction > 0 else { return [] }

        var arcs: [StorageDonutArc] = []
        var cursor = 0.0
        for category in categories where category.bytes > 0 {
            let span = usedFraction * Double(category.bytes) / Double(categoryTotal)
            var start = cursor
            var end = min(usedFraction, cursor + span)
            if span > 0.012 {
                let gap = min(0.004, span * 0.2)
                start += gap
                end -= gap
            }
            if end > start {
                arcs.append(StorageDonutArc(role: category.role, start: start, end: end))
            }
            cursor += span
        }
        return arcs
    }
}

// MARK: - Folder detail

struct StorageFolderDetail: Equatable {
    let path: String
    let title: String
    let folders: [StorageFolder]
    let isPartial: Bool
}

// MARK: - Parsers

/// Pure parsers for the shell commands `StorageService` runs. Every parser
/// degrades to "no data" on malformed output; nothing is invented.
enum StorageAnalyticsParsers {

    struct DFMount: Equatable {
        let filesystem: String
        let mountPath: String
        let totalBytes: Int64
        let usedBytes: Int64
        let freeBytes: Int64
    }

    /// `df -k` for every mounted filesystem.
    static func parseAllDFMounts(_ output: String?) -> [DFMount] {
        guard let output else { return [] }
        var mounts: [DFMount] = []
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard fields.count >= 6 else { continue }
            guard let totalKB = Int64(fields[1]),
                let usedKB = Int64(fields[2]),
                let freeKB = Int64(fields[3]),
                totalKB >= 0, usedKB >= 0, freeKB >= 0
            else { continue }
            let mountPath = fields[5...].joined(separator: " ")
            guard mountPath.hasPrefix("/") else { continue }
            mounts.append(
                DFMount(
                    filesystem: fields[0],
                    mountPath: mountPath,
                    totalBytes: totalKB * 1024,
                    usedBytes: usedKB * 1024,
                    freeBytes: freeKB * 1024))
        }
        return mounts
    }

    /// The internal volume: the mount on `/data`.
    static func internalMount(from mounts: [DFMount]) -> DFMount? {
        if let exact = mounts.first(where: { $0.mountPath == "/data" }) {
            return exact
        }
        return mounts.first { $0.mountPath.hasPrefix("/data/") }
    }

    /// Removable volumes live under `/storage`; emulated storage and the shell
    /// mount are part of the internal volume, so they are excluded.
    static func removableMounts(from mounts: [DFMount]) -> [DFMount] {
        var seen = Set<String>()
        var result: [DFMount] = []
        for mount in mounts {
            let path = mount.mountPath
            guard path.hasPrefix("/storage/") else { continue }
            guard !path.hasPrefix("/storage/emulated") else { continue }
            guard !path.hasPrefix("/storage/self") else { continue }
            guard path != "/storage" else { continue }
            guard mount.totalBytes > 0 else { continue }
            guard seen.insert(path).inserted else { continue }
            result.append(mount)
        }
        return result.sorted { $0.mountPath < $1.mountPath }
    }

    struct DiskStats: Equatable {
        var appBytes: Int64?
        var appDataBytes: Int64?
        var cacheBytes: Int64?
        var systemBytes: Int64?

        /// "Apps" in Settings = APK size + app data.
        var appsTotal: Int64? {
            let values = [appBytes, appDataBytes].compactMap { $0 }
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +)
        }

        /// Cache and system image are folded into System & Others.
        var systemTotal: Int64? {
            let values = [cacheBytes, systemBytes].compactMap { $0 }
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +)
        }
    }

    /// `dumpsys diskstats` prints keys such as `App Size: 49,123,456`. Values are
    /// bytes with thousands separators; anything unparsable is ignored.
    static func parseDiskStats(_ output: String?) -> DiskStats? {
        guard let output else { return nil }
        var values: [String: Int64] = [:]
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            let valueText = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, let value = leadingInteger(valueText) else { continue }
            values[key] = value
        }
        guard !values.isEmpty else { return nil }
        let stats = DiskStats(
            appBytes: values["app size"],
            appDataBytes: values["app data size"],
            cacheBytes: values["cache size"],
            systemBytes: values["system size"])
        return stats.appsTotal == nil && stats.systemTotal == nil ? nil : stats
    }

    /// Reads the first run of digits (commas allowed) from a shell value.
    private static func leadingInteger(_ text: String) -> Int64? {
        var digits = ""
        for character in text {
            if character.isNumber {
                digits.append(character)
            } else if character == "," {
                continue
            } else if digits.isEmpty && character.isWhitespace {
                continue
            } else {
                break
            }
        }
        guard !digits.isEmpty else { return nil }
        return Int64(digits)
    }

    /// Internal categories. Apps is only shown when `diskstats` measured it;
    /// otherwise it is folded into System & Others and the result is marked
    /// partial instead of inventing a split.
    static func computeInternalCategories(
        usedBytes: Int64,
        appsBytes: Int64?,
        userFilesBytes: Int64?,
        userFilesIsPartial: Bool
    ) -> [StorageCategory] {
        guard usedBytes > 0 else { return [] }
        let userFiles = max(0, min(userFilesBytes ?? 0, usedBytes))
        let userFilesPartial = userFilesBytes == nil || userFilesIsPartial

        if let appsBytes {
            // Apps is measured from `dumpsys diskstats`; clamp it first, then let
            // the folder-measured user files take only the remaining space.
            let apps = max(0, min(appsBytes, usedBytes))
            let remainingForUserFiles = max(0, usedBytes - apps)
            let userFiles = min(max(0, userFilesBytes ?? 0), remainingForUserFiles)
            let system = max(0, usedBytes - apps - userFiles)
            return [
                StorageCategory(role: .apps, bytes: apps),
                StorageCategory(role: .userFiles, bytes: userFiles, isPartial: userFilesPartial),
                StorageCategory(role: .system, bytes: system, isPartial: userFilesPartial),
            ]
        }

        // Apps could not be separated from system data; say so through the
        // partial flags rather than showing a guessed number.
        return [
            StorageCategory(role: .userFiles, bytes: userFiles, isPartial: userFilesPartial),
            StorageCategory(
                role: .system, bytes: max(0, usedBytes - userFiles),
                isPartial: true),
        ]
    }

    /// Removable volumes have no reliable app split, so only User files is
    /// measured and the remainder is System & Others.
    static func computeRemovableCategories(
        usedBytes: Int64,
        userFilesBytes: Int64?,
        userFilesIsPartial: Bool
    ) -> [StorageCategory] {
        guard usedBytes > 0 else { return [] }
        let userFiles = max(0, min(userFilesBytes ?? 0, usedBytes))
        let partial = userFilesBytes == nil || userFilesIsPartial
        return [
            StorageCategory(role: .userFiles, bytes: userFiles, isPartial: partial),
            StorageCategory(role: .system, bytes: max(0, usedBytes - userFiles), isPartial: true),
        ]
    }

    static func sumFolders(_ folders: [StorageFolder]) -> Int64 {
        folders.reduce(Int64(0)) { $0 + max(0, $1.bytes) }
    }

    static func clampBytes(_ value: Int64, to limit: Int64) -> Int64 {
        guard limit > 0 else { return 0 }
        return max(0, min(value, limit))
    }

    /// `du -sk` paths produced by `wm`/shell listings may contain a trailing
    /// slash; folder names should not.
    static func folderName(fromPath path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let name = (trimmed as NSString).lastPathComponent
        return name.isEmpty ? trimmed : name
    }
}
