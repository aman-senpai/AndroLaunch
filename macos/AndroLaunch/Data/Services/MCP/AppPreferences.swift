//
//  AppPreferences.swift
//  AndroLaunch
//
//  One observable store for the Settings surface's toggles. Keys live under the
//  documented `pref.*` namespace and are announced through
//  `Notification.Name.appPreferencesDidChange` so features owned by other
//  modules can react without coupling to this view.
//
//  The values here are honest product preferences, not cached device state:
//  device-specific settings stay in `DeviceScopedPreferences`.
//

import Combine
import Foundation
import ServiceManagement

// MARK: - Change notification

extension Notification.Name {
    /// Posted after any Settings preference is persisted. `object` is the
    /// `AppPreferences` instance; `userInfo["key"]` is the changed defaults key.
    static let appPreferencesDidChange = Notification.Name(
        "com.senpai.AndroLaunch.AppPreferencesDidChange")
}

// MARK: - Keys

enum AppPreferenceKeys {
    // Fusion mode
    static let meldModeEnabled = "pref.fusion.meldModeEnabled"
    static let openLinksOnMac = "pref.fusion.openLinksOnMac"
    static let handoffEnabled = "pref.fusion.handoff"

    // Devices
    static let deviceConnectionNotifications = "pref.devices.connectionNotifications"
    static let ignoreSystemFiles = "pref.devices.ignoreSystemFiles"

    // Notifications
    static let inlineReply = "pref.notifications.inlineReply"
    static let alertDeviceConnections = "pref.notifications.alert.deviceConnections"
    static let alertFileIssues = "pref.notifications.alert.fileIssues"
    static let alertClipboard = "pref.notifications.alert.clipboard"
    static let alertMeldMode = "pref.notifications.alert.meldMode"
}

// MARK: - Feature alerts

enum AppFeatureAlert: String, CaseIterable, Identifiable {
    case deviceConnections
    case fileIssues
    case clipboard
    case meldMode

    var id: String { rawValue }

    var defaultsKey: String {
        switch self {
        case .deviceConnections: return AppPreferenceKeys.alertDeviceConnections
        case .fileIssues: return AppPreferenceKeys.alertFileIssues
        case .clipboard: return AppPreferenceKeys.alertClipboard
        case .meldMode: return AppPreferenceKeys.alertMeldMode
        }
    }

    var title: String {
        switch self {
        case .deviceConnections: return "Device connections"
        case .fileIssues: return "File operations"
        case .clipboard: return "Clipboard"
        case .meldMode: return "Frame Mode"
        }
    }

    var subtitle: String {
        switch self {
        case .deviceConnections: return "When a device becomes available"
        case .fileIssues: return "When writes fail or a work profile needs access"
        case .clipboard: return "When copies finish or the device needs unlocking"
        case .meldMode: return "When an app opens on the phone screen instead"
        }
    }

    var icon: String {
        switch self {
        case .deviceConnections: return "iphone.gen3.radiowaves.left.and.right"
        case .fileIssues: return "doc.badge.exclamationmark"
        case .clipboard: return "doc.on.clipboard"
        case .meldMode: return "rectangle.on.rectangle"
        }
    }
}

// MARK: - Store

final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    /// Deterministic instance used by the snapshot renderer and previews.
    static let preview = AppPreferences(isPreview: true)

    // Fusion mode
    @Published var meldModeEnabled: Bool {
        didSet { persist(meldModeEnabled, AppPreferenceKeys.meldModeEnabled) }
    }
    @Published var openLinksOnMac: Bool {
        didSet { persist(openLinksOnMac, AppPreferenceKeys.openLinksOnMac) }
    }
    @Published var handoffEnabled: Bool {
        didSet { persist(handoffEnabled, AppPreferenceKeys.handoffEnabled) }
    }

    // Devices
    @Published var deviceConnectionNotifications: Bool {
        didSet {
            persist(deviceConnectionNotifications, AppPreferenceKeys.deviceConnectionNotifications)
        }
    }
    @Published var ignoreSystemFiles: Bool {
        didSet { persist(ignoreSystemFiles, AppPreferenceKeys.ignoreSystemFiles) }
    }

    // Notifications
    @Published var inlineReply: Bool {
        didSet { persist(inlineReply, AppPreferenceKeys.inlineReply) }
    }

    let launchAtLogin: LaunchAtLoginController

    private let defaults: UserDefaults
    private let isPreview: Bool

    init(defaults: UserDefaults = .standard, isPreview: Bool = false) {
        self.defaults = defaults
        self.isPreview = isPreview
        self.launchAtLogin = LaunchAtLoginController(isPreview: isPreview)
        self.meldModeEnabled = Self.read(defaults, AppPreferenceKeys.meldModeEnabled, true, isPreview)
        self.openLinksOnMac = Self.read(defaults, AppPreferenceKeys.openLinksOnMac, true, isPreview)
        self.handoffEnabled = Self.read(defaults, AppPreferenceKeys.handoffEnabled, true, isPreview)
        self.deviceConnectionNotifications = Self.read(
            defaults, AppPreferenceKeys.deviceConnectionNotifications, true, isPreview)
        self.ignoreSystemFiles = Self.read(
            defaults, AppPreferenceKeys.ignoreSystemFiles, true, isPreview)
        self.inlineReply = Self.read(defaults, AppPreferenceKeys.inlineReply, true, isPreview)
    }

    // MARK: Feature alerts

    func isAlertEnabled(_ alert: AppFeatureAlert) -> Bool {
        Self.read(defaults, alert.defaultsKey, true, isPreview)
    }

    func setAlert(_ alert: AppFeatureAlert, enabled: Bool) {
        if !isPreview {
            defaults.set(enabled, forKey: alert.defaultsKey)
        }
        announce(alert.defaultsKey)
    }

    // MARK: Persistence

    /// macOS metadata that should never be pushed to a phone when the user keeps
    /// "Ignore system files" on. Extend this list deliberately: it is a product
    /// setting, not a general hidden-file filter.
    static func isSystemMetadataFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name == ".DS_Store" || name.hasPrefix("._") { return true }
        switch name {
        case ".Spotlight-V100", ".fseventsd", ".Trashes", ".TemporaryItems",
            ".apdisk", ".VolumeIcon.icns", "Icon\r":
            return true
        default:
            return false
        }
    }

    private static func read(
        _ defaults: UserDefaults, _ key: String, _ fallback: Bool, _ isPreview: Bool
    ) -> Bool {
        if isPreview { return fallback }
        if let stored = defaults.object(forKey: key) as? Bool { return stored }
        return fallback
    }

    private func persist(_ value: Bool, _ key: String) {
        guard !isPreview else { return }
        guard (defaults.object(forKey: key) as? Bool) != value else { return }
        defaults.set(value, forKey: key)
        announce(key)
    }

    private func announce(_ key: String) {
        guard !isPreview else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .appPreferencesDidChange, object: self, userInfo: ["key": key])
        }
    }
}

// MARK: - Launch at login

enum LaunchAtLoginState: Equatable {
    case off
    case on
    case requiresApproval
    case notFound
    case unavailable(String)

    var isRequested: Bool {
        switch self {
        case .on, .requiresApproval: return true
        case .off, .notFound, .unavailable: return false
        }
    }

    var title: String {
        switch self {
        case .off: return "Off"
        case .on: return "On"
        case .requiresApproval: return "Approval needed"
        case .notFound: return "Not available"
        case .unavailable: return "Unavailable"
        }
    }

    var detail: String {
        switch self {
        case .off:
            return "AndroLaunch stays closed until you open it."
        case .on:
            return "AndroLaunch opens automatically when you log in."
        case .requiresApproval:
            return "Approve AndroLaunch in System Settings → General → Login Items to finish."
        case .notFound:
            return "macOS could not find AndroLaunch's registered app bundle. Reinstall the app."
        case .unavailable(let message):
            return message
        }
    }
}

/// Thin, testable wrapper around `SMAppService.mainApp`. No privilege is
/// requested here; macOS may surface an approval prompt for the user.
final class LaunchAtLoginController: ObservableObject {
    static let shared = LaunchAtLoginController()

    @Published private(set) var state: LaunchAtLoginState = .off

    private let isPreview: Bool

    init(isPreview: Bool = false) {
        self.isPreview = isPreview
        if !isPreview { refresh() }
    }

    func refresh() {
        guard !isPreview else { return }
        switch SMAppService.mainApp.status {
        case .notRegistered: state = .off
        case .enabled: state = .on
        case .requiresApproval: state = .requiresApproval
        case .notFound: state = .notFound
        @unknown default: state = .unavailable("macOS reported an unknown login item state.")
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard !isPreview else {
            state = enabled ? .on : .off
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            state = .unavailable(
                "macOS could not update the login item: \(error.localizedDescription)")
        }
    }

    func openLoginItemsSettings() {
        guard !isPreview else { return }
        SMAppService.openSystemSettingsLoginItems()
    }
}
