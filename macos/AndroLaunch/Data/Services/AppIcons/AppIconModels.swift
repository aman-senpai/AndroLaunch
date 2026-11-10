//
//  AppIconModels.swift
//  AndroLaunch
//
//  Foundation-only model + pure logic for real app icons (protocol v4).
//
//  The `app-icons` command answers JSON:
//
//      {"c":"app-icons","icons":[
//        {"package":"com.example","label":"Example","pngBase64":"iVBOR…"}
//      ]}
//
//  Keeping decoding, cache-key sanitising and batch splitting here (no AppKit,
//  no networking) means the logic tests exercise exactly the code the app runs,
//  and a malformed payload degrades to "no icons" instead of a crash.
//

import Foundation

// MARK: - Icon payload

/// One icon returned by the companion.
struct CompanionAppIcon: Equatable {
    let packageName: String
    let label: String
    let pngData: Data
}

enum AppIconPayload {

    /// Largest single icon accepted. A 96 px PNG is a few KB; the cap only exists
    /// to bound a broken/hostile payload.
    static let maxIconBytes = 512 * 1024
    /// Largest number of icons accepted from one response (matches the phone bound).
    static let maxIconCount = 64

    /// Decodes a response envelope.
    ///
    /// Returns `nil` only when the envelope itself is unusable (not JSON, or no
    /// `icons` array) so the caller can surface a real error. Entries that are
    /// malformed, duplicated or not PNG are skipped individually.
    static func decode(_ json: String) -> [CompanionAppIcon]? {
        guard let data = json.data(using: .utf8),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        if let command = object["c"] as? String, command != "app-icons" { return nil }
        guard let raw = object["icons"] as? [[String: Any]] else { return nil }

        var seen = Set<String>()
        var icons: [CompanionAppIcon] = []
        for entry in raw {
            guard icons.count < maxIconCount else { break }
            guard let packageName = (entry["package"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !packageName.isEmpty
            else { continue }
            guard seen.insert(packageName).inserted else { continue }
            guard let base64 = entry["pngBase64"] as? String,
                let png = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
                !png.isEmpty,
                png.count <= maxIconBytes,
                isPNG(png)
            else { continue }
            let label = (entry["label"] as? String) ?? ""
            icons.append(
                CompanionAppIcon(
                    packageName: packageName,
                    label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                    pngData: png))
        }
        return icons
    }

    /// PNG signature check: `89 50 4E 47 0D 0A 1A 0A`.
    static func isPNG(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= signature.count else { return false }
        return Array(data.prefix(signature.count)) == signature
    }
}

// MARK: - Cache keys

/// Turns device identifiers and package names into safe, stable file-system
/// components. Package names are normally `[a-z0-9._]`, but cache keys are built
/// from remote input, so traversal, separators and case collisions are handled
/// here rather than trusted.
enum AppIconCacheKey {

    static let maxComponentLength = 64

    /// `<device>/<package>.png` relative path used on disk and as the memory key.
    static func relativePath(deviceID: String, packageName: String) -> String {
        "\(deviceComponent(deviceID))/\(fileComponent(packageName))"
    }

    /// In-memory key. Kept explicit so a device switch never shows another
    /// device's icon (identical packages across phones is common).
    static func memoryKey(deviceID: String, packageName: String) -> String {
        "\(deviceID)|\(packageName)"
    }

    /// Directory name for one device. Lowercased because macOS volumes are
    /// case-insensitive by default, and bounded so a long Bonjour name cannot
    /// exceed a path component limit.
    static func deviceComponent(_ deviceID: String) -> String {
        let sanitized = sanitize(deviceID, lowercase: true)
        return sanitized.isEmpty ? "device" : String(sanitized.prefix(maxComponentLength))
    }

    /// File name for one package, including the `.png` extension.
    static func fileComponent(_ packageName: String) -> String {
        let sanitized = sanitize(packageName, lowercase: true)
        return (sanitized.isEmpty ? "app" : String(sanitized.prefix(maxComponentLength))) + ".png"
    }

    private static func sanitize(_ value: String, lowercase: Bool) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            let isAllowed =
                (scalar >= "a" && scalar <= "z") || (scalar >= "A" && scalar <= "Z")
                || (scalar >= "0" && scalar <= "9") || scalar == "." || scalar == "_"
                || scalar == "-"
            if isAllowed {
                out.unicodeScalars.append(scalar)
            } else {
                out.append("-")
            }
        }
        // Collapse traversal-ish runs and never produce a hidden or parent name.
        while out.contains("..") {
            out = out.replacingOccurrences(of: "..", with: ".")
        }
        while out.contains("--") {
            out = out.replacingOccurrences(of: "--", with: "-")
        }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        if out.isEmpty || out == "." || out == ".." { return "" }
        if out.hasPrefix(".") { out = "_" + out.dropFirst() }
        return lowercase ? out.lowercased() : out
    }
}

// MARK: - Batching

enum AppIconBatches {

    /// Package batches per `app-icons` request. The companion accepts 64; 24 keeps
    /// one response comfortably small and lets icons appear incrementally.
    static let defaultBatchSize = 24
    static let maximumBatchSize = 64

    /// Deduplicates, drops blanks and splits into fixed-size batches.
    static func split(_ packages: [String], size: Int = defaultBatchSize) -> [[String]] {
        let batchSize = max(1, min(maximumBatchSize, size))
        var seen = Set<String>()
        var cleaned: [String] = []
        for package in packages {
            let trimmed = package.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            cleaned.append(trimmed)
        }
        guard !cleaned.isEmpty else { return [] }
        var batches: [[String]] = []
        var index = 0
        while index < cleaned.count {
            let end = min(index + batchSize, cleaned.count)
            batches.append(Array(cleaned[index..<end]))
            index = end
        }
        return batches
    }
}
