//
//  AppLaunchMode.swift
//  AndroLaunch
//
//  How a phone app is opened from the Hub. Frame Mode gives each app its own
//  window on the phone's virtual display; Screen mirroring shows the phone's
//  main display with the app in the foreground. Foundation-only so the pure
//  logic tests can compile it without AppKit.
//

import Foundation

enum AppLaunchMode: String, CaseIterable, Identifiable, Equatable {
    /// A dedicated scrcpy window backed by a virtual display (Android 14+).
    case meldWindow
    /// The phone's main display, mirrored with the app in the foreground.
    case mirror

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meldWindow: return "Frame Mode window"
        case .mirror: return "Screen mirroring"
        }
    }

    var shortTitle: String {
        switch self {
        case .meldWindow: return "Meld"
        case .mirror: return "Mirror"
        }
    }

    var subtitle: String {
        switch self {
        case .meldWindow:
            return "A window of its own on Android 14+. Main display on older phones."
        case .mirror:
            return "Mirrors the phone screen with the app in front. Works on every version."
        }
    }

    var icon: String {
        switch self {
        case .meldWindow: return "macwindow.on.rectangle"
        case .mirror: return "iphone.gen3"
        }
    }

    /// Parses the `mode` query value used by desktop shortcuts.
    init?(queryValue: String?) {
        guard let queryValue = queryValue?.trimmingCharacters(in: .whitespacesAndNewlines),
            !queryValue.isEmpty
        else { return nil }
        switch queryValue.lowercased() {
        case "meld", "meldwindow", "window": self = .meldWindow
        case "mirror", "mirroring", "screen": self = .mirror
        default: return nil
        }
    }
}

/// What a "Frame Mode" launch will actually do on a given phone.
enum MeldWindowBehavior: Equatable {
    /// scrcpy `--new-display` + `--start-app` on Android 14+.
    case virtualDisplay
    /// Android 12–13 (and unknown versions) mirror the main display instead.
    case mainDisplayFallback(reason: String)

    var isVirtualDisplay: Bool {
        if case .virtualDisplay = self { return true }
        return false
    }

    /// Short pill text for the Apps tab.
    var pillText: String {
        switch self {
        case .virtualDisplay: return "Frame Mode"
        case .mainDisplayFallback:
            return "Mirror fallback"
        }
    }
}

enum MeldModeSupport {
    /// scrcpy's virtual display is only stable from Android 14 (API 34). On
    /// Android 12–13 the platform SystemUI crashes and locks the phone, so the
    /// fallback is deliberately conservative.
    static let minimumAPILevel = 34

    static func apiLevel(from rawValue: String?) -> Int? {
        guard let rawValue else { return nil }
        let digits = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { $0.isNumber }
        return Int(digits)
    }

    static func behavior(apiLevel rawAPLevel: String?) -> MeldWindowBehavior {
        guard let level = apiLevel(from: rawAPLevel) else {
            return .mainDisplayFallback(
                reason:
                    "The Android version is unknown, so the app opens on a mirrored main display. Connect once so AndroLaunch can read it."
            )
        }
        guard level >= minimumAPILevel else {
            return .mainDisplayFallback(
                reason:
                    "Frame Mode windows need Android 14 or later (this phone reports API \(level)). The app opens on a mirrored main display instead."
            )
        }
        return .virtualDisplay
    }

    static func supportsVirtualDisplay(apiLevel: String?) -> Bool {
        behavior(apiLevel: apiLevel).isVirtualDisplay
    }
}
