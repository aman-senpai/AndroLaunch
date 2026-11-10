//
//  SpotlightService.swift
//  AndroLaunch
//
//  Spotlights the selected phone's apps in macOS search, and generates tiny
//  Desktop `.app` shortcuts that deep-link back into per-app windows.
//  Indexing is best-effort and reports its real state; nothing about it is
//  simulated.
//

import AppKit
import Combine
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

final class SpotlightService: ObservableObject {
    static let shared = SpotlightService()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var indexedCount = 0
    @Published private(set) var lastError: String?
    @Published private(set) var lastShortcutURL: URL?
    @Published private(set) var lastShortcutName: String?

    private let defaults = UserDefaults.standard
    private let enabledKey = "spotlight.enabled"
    private let domainIdentifier = "com.senpai.AndroLaunch.apps"
    private let index = CSSearchableIndex.default()
    /// Unique identifiers last indexed per ADB device, so stale apps can be removed.
    private var indexedIdentifiersByDevice: [String: Set<String>] = [:]
    private var cancellables = Set<AnyCancellable>()

    private init() {
        isEnabled = defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    // MARK: - State

    var isIndexingAvailable: Bool { CSSearchableIndex.isIndexingAvailable() }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: enabledKey)
        if enabled {
            reindexSelectedDevice()
        } else {
            clearIndex()
        }
    }

    /// Re-indexes the currently selected phone (used when Spotlight is enabled
    /// from Settings, so the user does not have to switch devices first).
    func reindexSelectedDevice() {
        guard isEnabled, let device = HubStore.shared.selectedDevice else { return }
        rebuildIndex(apps: HubStore.shared.apps, deviceID: device.id)
    }

    func clearMessages() {
        lastError = nil
        lastShortcutURL = nil
        lastShortcutName = nil
    }

    // MARK: - Indexing

    func rebuildIndex(apps: [AndroidApp], deviceID: String) {
        guard isEnabled else { return }
        guard !HubStore.shared.isPreview else { return }
        guard isIndexingAvailable else {
            lastError = "Spotlight indexing isn't available on this Mac."
            return
        }

        let deviceName = HubStore.shared.devices
            .first(where: { $0.id == deviceID || $0.stableID == deviceID })?.name
        var items: [CSSearchableItem] = []
        var identifiers = Set<String>()

        for app in apps {
            guard
                let url = AppDeepLink.makeURL(
                    deviceID: deviceID,
                    packageID: app.packageName,
                    appName: app.name,
                    mode: .meldWindow)
            else { continue }

            // The unique identifier *is* the deep link, so a Spotlight result
            // still resolves after the app relaunches (no in-memory registry).
            let identifier = url.absoluteString
            identifiers.insert(identifier)

            let attributes = CSSearchableItemAttributeSet(
                itemContentType: UTType.data.identifier)
            attributes.title = app.name
            attributes.displayName = app.name
            attributes.contentDescription =
                "\(app.name) — \(app.packageName)"
                + (deviceName.map { " on \($0)" } ?? "")
            attributes.keywords = [app.name, app.packageName, deviceName, "Android", "AndroLaunch"]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            attributes.kind = "Android App"

            let item = CSSearchableItem(
                uniqueIdentifier: identifier,
                domainIdentifier: domainIdentifier,
                attributeSet: attributes)
            items.append(item)
        }

        let previous = indexedIdentifiersByDevice[deviceID] ?? []
        let stale = previous.subtracting(identifiers)

        index.indexSearchableItems(items) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.lastError =
                        "Spotlight indexing failed: \(error.localizedDescription)"
                    return
                }
                self.indexedIdentifiersByDevice[deviceID] = identifiers
                self.indexedCount = self.indexedIdentifiersByDevice.values.reduce(0) {
                    $0 + $1.count
                }
                self.lastError = nil
                if !stale.isEmpty {
                    self.index.deleteSearchableItems(withIdentifiers: Array(stale)) { _ in }
                }
            }
        }
    }

    func clearIndex() {
        index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.indexedIdentifiersByDevice.removeAll()
                self.indexedCount = 0
                if let error {
                    self.lastError =
                        "Spotlight index couldn't be cleared: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Desktop shortcuts

    /// Creates a Desktop `.app` that opens this app's Frame Mode window.
    func addDesktopShortcut(app: AndroidApp, deviceID: String) {
        lastError = nil
        lastShortcutURL = nil
        lastShortcutName = nil
        guard !HubStore.shared.isPreview else {
            lastError = "Snapshot mode doesn't create shortcuts."
            return
        }
        guard
            let device = HubStore.shared.devices.first(where: {
                $0.id == deviceID || $0.stableID == deviceID
            })
        else {
            lastError = "That phone is no longer connected."
            return
        }

        do {
            let url = try DesktopShortcutBuilder.create(app: app, device: device)
            lastShortcutURL = url
            lastShortcutName = url.deletingPathExtension().lastPathComponent
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    // MARK: - Deep links

    /// Handles `androlaunch://launch?serial=…&pkg=…` from shortcuts and the URL scheme.
    static func handle(_ url: URL) -> Bool {
        guard let request = AppDeepLink.parse(url) else { return false }
        return open(request)
    }

    /// Handles a Spotlight/CoreSpotlight or NSUserActivity continuation.
    static func handle(activityType: String, userInfo: [String: Any]) -> Bool {
        if activityType == AppDeepLink.activityType,
            let request = AppDeepLink.parse(userInfo: userInfo)
        {
            return open(request)
        }

        // CoreSpotlight delivers its own activity type plus the item identifier;
        // our identifier is the deep link itself.
        if activityType == CSSearchableItemActionType
            || activityType == CSQueryContinuationActionType
            || userInfo[CSSearchableItemActivityIdentifier] != nil
        {
            if let identifier = userInfo[CSSearchableItemActivityIdentifier] as? String,
                let url = URL(string: identifier),
                let request = AppDeepLink.parse(url)
            {
                return open(request)
            }
        }

        // A user activity that carries our own keys is safe to accept as well.
        if let request = AppDeepLink.parse(userInfo: userInfo) {
            return open(request)
        }
        return false
    }

    private static func open(_ request: AppLaunchRequest) -> Bool {
        let attempt = { () -> Bool in
            guard !HubStore.shared.isPreview else { return false }
            if let device = resolveDevice(for: request) {
                return launch(request, on: device)
            }
            // The URL can arrive while the first device refresh is still in
            // flight (the app is launched by the shortcut). Wait for the phone
            // instead of reporting a false "not connected".
            retryOpening(request, attemptsLeft: 12)
            return true
        }
        if Thread.isMainThread {
            return attempt()
        }
        DispatchQueue.main.async { _ = attempt() }
        return true
    }

    private static func retryOpening(_ request: AppLaunchRequest, attemptsLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard !HubStore.shared.isPreview else { return }
            if let device = resolveDevice(for: request) {
                _ = launch(request, on: device)
                return
            }
            guard attemptsLeft > 0 else {
                shared.lastError =
                    "The shortcut's phone isn't connected. Reconnect \(request.deviceID) and try again."
                return
            }
            retryOpening(request, attemptsLeft: attemptsLeft - 1)
        }
    }

    private static func resolveDevice(for request: AppLaunchRequest) -> AndroidDevice? {
        HubStore.shared.devices.first {
            $0.id == request.deviceID || $0.stableID == request.deviceID
        }
    }

    private static func launch(_ request: AppLaunchRequest, on device: AndroidDevice) -> Bool {
        let app = HubStore.shared.apps.first {
            $0.packageName == request.packageID || $0.id == request.packageID
        }
        let appName = request.appName ?? app?.name ?? request.packageID
        return AppWindowController.shared.openApp(
            packageID: request.packageID,
            appName: appName,
            deviceID: device.id,
            mode: request.mode ?? .meldWindow)
    }

}
