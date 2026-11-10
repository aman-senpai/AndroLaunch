//
//  ShortcutNaming.swift
//  AndroLaunch
//
//  Deterministic file naming for generated desktop shortcuts. Foundation-only
//  so the naming rules are covered by the logic tests.
//

import Foundation

enum ShortcutNaming {
    /// Characters macOS rejects or Finder silently mangles in a bundle name.
    private static let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>\u{0000}")
        .union(.controlCharacters)

    /// Trims, collapses whitespace and drops characters a file name cannot hold.
    static func sanitizedComponent(_ raw: String) -> String {
        let cleaned = raw.unicodeScalars
            .map { forbidden.contains($0) ? " " : String($0) }
            .joined()
        let collapsed = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return trimmed
    }

    /// The `.app` bundle name for one app. Empty fragments fall back to the package.
    static func bundleName(
        appName: String,
        deviceName: String?,
        packageID: String
    ) -> String {
        let app = sanitizedComponent(appName)
        let appFallback = app.isEmpty ? sanitizedComponent(packageID) : app
        let device = sanitizedComponent(deviceName ?? "")
        let base: String
        if device.isEmpty {
            base = appFallback.isEmpty ? "Android App" : appFallback
        } else {
            base = appFallback.isEmpty ? "Android App on \(device)" : "\(appFallback) on \(device)"
        }
        return String(base.prefix(120)).trimmingCharacters(in: .whitespaces)
    }

    /// Adds " 2", " 3", … until the name is free. `existingNames` are bundle
    /// names already present on the Desktop (with or without `.app`).
    static func uniqueBundleName(
        appName: String,
        deviceName: String?,
        packageID: String,
        existingNames: [String]
    ) -> String {
        let base = bundleName(appName: appName, deviceName: deviceName, packageID: packageID)
        let taken = Set(existingNames.map { normalized($0) })
        guard taken.contains(normalized(base)) else { return base }
        var index = 2
        while index < 1000 {
            let candidate = "\(base) \(index)"
            if !taken.contains(normalized(candidate)) { return candidate }
            index += 1
        }
        return "\(base) \(UUID().uuidString.prefix(6))"
    }

    /// Bundle identifier fragment derived from the device/app pair. Stable, so
    /// replacing a shortcut keeps the same identity.
    static func identifierSuffix(deviceID: String, packageID: String) -> String {
        let seed = "\(deviceID)|\(packageID)"
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325  // FNV-1a 64
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    private static func normalized(_ name: String) -> String {
        var value = name.lowercased()
        if value.hasSuffix(".app") { value.removeLast(4) }
        return value.trimmingCharacters(in: .whitespaces)
    }
}
