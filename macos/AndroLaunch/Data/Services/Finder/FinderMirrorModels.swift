//
//  FinderMirrorModels.swift
//  AndroLaunch
//
//  Foundation-only models and path-safety logic for the Finder mirror.
//
//  The mirror is a local copy under Application Support plus a stable symlink in
//  `~/AndroLaunch` for the Finder sidebar. It is explicitly **not** a system File
//  Provider mount: that needs a separately signed extension target.
//

import Foundation

// MARK: - Scopes

enum FinderMirrorScope: String, CaseIterable, Identifiable, Equatable {
    case camera
    case sdCard
    case root
    case userFiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: return "Camera"
        case .sdCard: return "SD Card"
        case .root: return "Root"
        case .userFiles: return "User files"
        }
    }

    /// Folder name used inside the device mirror (and therefore in Finder).
    var directoryName: String {
        switch self {
        case .camera: return "Camera"
        case .sdCard: return "SD Card"
        case .root: return "Root"
        case .userFiles: return "User files"
        }
    }

    var icon: String {
        switch self {
        case .camera: return "camera.fill"
        case .sdCard: return "sdcard.fill"
        case .root: return "folder.fill"
        case .userFiles: return "person.crop.rectangle.stack.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .camera: return "DCIM/Camera"
        case .sdCard: return "Removable volume"
        case .root: return "Shared storage, safe folders"
        case .userFiles: return "Pictures, Downloads, Documents…"
        }
    }
}

// MARK: - Limits

enum FinderMirrorLimits {
    /// Per-scope copy budget. Bigger folders are refused with an explanation
    /// instead of silently copying gigabytes.
    static let maxBytesPerScope: Int64 = 2 * 1024 * 1024 * 1024
    /// Wall-clock cap for one scope refresh.
    static let maxDuration: TimeInterval = 240
    /// Reuse a mirror refreshed within this window instead of pulling again.
    static let refreshInterval: TimeInterval = 10 * 60
    static let maxDeviceFolderNameLength = 64
}

/// Folders copied for the "Root" / "User files" scopes. `Android/` is excluded:
/// it is app data, mostly unreadable, and not "user files".
enum FinderMirrorSafeFolders {
    static let names: [String] = [
        "DCIM", "Pictures", "Download", "Documents", "Movies", "Music",
        "Podcasts", "Recordings", "Ringtones", "Alarms", "Notifications",
        "Audiobooks", "Books", "Templates",
    ]

    static func contains(_ name: String) -> Bool { names.contains(name) }

    /// Filters `ls` output down to safe, user-facing folder names.
    static func filtered(fromListing listing: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for rawLine in listing.components(separatedBy: .newlines) {
            let name = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard FinderMirrorLogic.isSafeComponent(name) else { continue }
            guard names.contains(name) else { continue }
            guard seen.insert(name).inserted else { continue }
            result.append(name)
        }
        return result
    }
}

// MARK: - Location

struct FinderMirrorLocation: Equatable {
    /// Safe device folder name (also the sidebar link name).
    let deviceFolderName: String
    let deviceDirectory: String
    let scopeDirectory: String
    let eyebrow: String

    var fileURL: URL { URL(fileURLWithPath: scopeDirectory, isDirectory: true) }
    var deviceURL: URL { URL(fileURLWithPath: deviceDirectory, isDirectory: true) }
}

// MARK: - Logic

enum FinderMirrorLogic {
    /// Makes a device name safe for a single path component: strips separators,
    /// control characters and leading dots, collapses whitespace and caps length.
    static func sanitizedDeviceFolderName(
        _ raw: String,
        fallback: String = "Android device"
    ) -> String {
        let collapsed =
            raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        var filtered = ""
        filtered.reserveCapacity(collapsed.count)
        for scalar in collapsed.unicodeScalars {
            let isForbidden: Bool =
                scalar == "/" || scalar == "\\" || scalar == ":" || scalar == "\0"
                || scalar.properties.generalCategory == .control
                || scalar.properties.generalCategory == .format
            if !isForbidden { filtered.unicodeScalars.append(scalar) }
        }
        filtered = filtered.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if filtered.isEmpty { filtered = fallback }
        if filtered.count > FinderMirrorLimits.maxDeviceFolderNameLength {
            filtered = String(filtered.prefix(FinderMirrorLimits.maxDeviceFolderNameLength))
                .trimmingCharacters(in: .whitespaces)
        }
        // "." and ".." are path components, never names.
        if filtered == "." || filtered == ".." { filtered = fallback }
        return filtered
    }

    /// `~/Library/Application Support/AndroLaunch/Finder`
    static func mirrorLibraryRoot(
        homeDirectory: String = NSHomeDirectory(),
        applicationSupportDirectory: String? = nil
    ) -> String {
        let support: String
        if let applicationSupportDirectory, !applicationSupportDirectory.isEmpty {
            support = applicationSupportDirectory
        } else {
            support = (homeDirectory as NSString)
                .appendingPathComponent("Library/Application Support")
        }
        return (support as NSString).appendingPathComponent("AndroLaunch/Finder")
    }

    /// `~/AndroLaunch` — the stable user-visible root for Finder sidebar use.
    static func sidebarRoot(homeDirectory: String = NSHomeDirectory()) -> String {
        (homeDirectory as NSString).appendingPathComponent("AndroLaunch")
    }

    static func location(
        deviceName: String?,
        deviceID: String,
        scope: FinderMirrorScope,
        homeDirectory: String = NSHomeDirectory(),
        applicationSupportDirectory: String? = nil
    ) -> FinderMirrorLocation {
        let folderName = sanitizedDeviceFolderName(
            deviceName ?? deviceID, fallback: sanitizedDeviceFolderName(deviceID))
        let root = mirrorLibraryRoot(
            homeDirectory: homeDirectory,
            applicationSupportDirectory: applicationSupportDirectory)
        let deviceDirectory = (root as NSString).appendingPathComponent(folderName)
        let scopeDirectory = (deviceDirectory as NSString)
            .appendingPathComponent(scope.directoryName)
        return FinderMirrorLocation(
            deviceFolderName: folderName,
            deviceDirectory: deviceDirectory,
            scopeDirectory: scopeDirectory,
            eyebrow: scope.title)
    }

    /// True when `candidate` is the same as, or inside, `root`. Uses standardized
    /// (lexical) paths and requires a path-component boundary, so `/a/bc` is not
    /// treated as inside `/a/b`.
    static func isContained(_ candidate: String, within root: String) -> Bool {
        let normalizedCandidate = (candidate as NSString).standardizingPath
        let normalizedRoot = (root as NSString).standardizingPath
        if normalizedCandidate == normalizedRoot { return true }
        let rootWithSlash =
            normalizedRoot.hasSuffix("/") ? normalizedRoot : normalizedRoot + "/"
        return normalizedCandidate.hasPrefix(rootWithSlash)
    }

    /// A single remote child name that is safe to pass to a shell and to use as a
    /// local folder name.
    static func isSafeComponent(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != ".." else { return false }
        guard !name.contains("/"), !name.contains("\\"), !name.contains("\0") else {
            return false
        }
        guard !name.hasPrefix(".") else { return false }
        guard !name.contains(":") else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            scalar.properties.generalCategory != .control
        }
    }

    static func fitsCap(
        estimatedBytes: Int64,
        limit: Int64 = FinderMirrorLimits.maxBytesPerScope
    ) -> Bool {
        guard estimatedBytes >= 0, limit > 0 else { return false }
        return estimatedBytes <= limit
    }

    static func capDescription(bytes: Int64, limit: Int64 = FinderMirrorLimits.maxBytesPerScope)
        -> String
    {
        "\(PhoneFormat.bytes(bytes)) is larger than the \(PhoneFormat.bytes(limit)) Finder mirror limit."
    }

    static func progressFraction(completedBytes: Int64, totalBytes: Int64) -> Double {
        guard totalBytes > 0, completedBytes > 0 else { return 0 }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }

    /// Parses `adb pull` progress such as `[ 42%] /sdcard/DCIM/Camera/a.jpg`.
    static func pullProgressPercent(from line: String) -> Int? {
        guard let open = line.firstIndex(of: "["),
            let close = line.firstIndex(of: "]"),
            close > open
        else { return nil }
        let inner = line[line.index(after: open)..<close]
            .trimmingCharacters(in: .whitespaces)
        let digits = inner.replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Int(digits), (0...100).contains(value) else { return nil }
        return value
    }

    /// Converts `du -sk` output to bytes for the pre-copy cap check. Returns the
    /// largest total when several entries are printed.
    static func estimatedBytes(fromDU output: String?) -> Int64? {
        guard let output else { return nil }
        var total: Int64 = 0
        var found = false
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let head = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).first
            guard let head, let kb = Int64(head), kb >= 0 else { continue }
            total += kb * 1024
            found = true
        }
        return found ? total : nil
    }
}
