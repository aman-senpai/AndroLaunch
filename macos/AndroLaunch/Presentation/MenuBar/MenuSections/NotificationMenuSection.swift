//
//  NotificationMenuSection.swift
//  AndroLaunch
//
//  Owned by the notifications feature: one top-level "Notifications" submenu
//  with an opt-in toggle plus a status line per connected device, and a
//  deep-link into macOS Notification settings. Nothing is mirrored until the
//  per-device toggle is on (see NotificationMirror).
//

import AppKit
import Combine

final class NotificationMenuSection: NSObject, MenuSectionProviding {
    let sectionID = "notifications"
    var topLevelOrder: Int { 40 }
    let viewModel: MenuViewModel

    private let mirror = NotificationMirror.shared
    private var cancellables = Set<AnyCancellable>()

    /// Retained so `menuWillOpen()` can refresh the rows in place.
    private var notificationsSubmenu: NSMenu?
    private var builtDeviceIDs: [String] = []
    private var deviceRows: [String: ToggleMenuItemView] = [:]
    private var rowStates: [String: Bool] = [:]
    private var statusItems: [String: NSMenuItem] = [:]

    init(viewModel: MenuViewModel) {
        self.viewModel = viewModel
        super.init()

        // App labels come from scrcpy's cached app list when it happens to be
        // loaded; otherwise the mirror falls back to the package name. No extra
        // ADB call is made for labels.
        mirror.appLabelProvider = { [weak viewModel] packageID in
            guard let viewModel else { return nil }
            for apps in viewModel.deviceApps.values {
                if let app = apps.first(where: { $0.packageName == packageID }) {
                    return app.name
                }
            }
            return nil
        }

        // Keep mirroring state in sync with the live device list, so a
        // disconnected device never keeps polling.
        viewModel.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.mirror.syncDevices(devices)
            }
            .store(in: &cancellables)
    }

    // MARK: - MenuSectionProviding

    func topLevelItems() -> [NSMenuItem] {
        let devices = viewModel.devices
        mirror.syncDevices(devices)

        guard !devices.isEmpty else {
            notificationsSubmenu = nil
            builtDeviceIDs = []
            deviceRows.removeAll()
            rowStates.removeAll()
            statusItems.removeAll()
            return []
        }

        let item = NSMenuItem(title: "Notifications", action: nil, keyEquivalent: "")
        item.image = Self.templateImage(symbolName: "bell")

        let submenu = NSMenu(title: "Notifications")
        submenu.autoenablesItems = false
        submenu.delegate = self
        fill(submenu, devices: devices)
        item.submenu = submenu

        notificationsSubmenu = submenu
        return [item]
    }

    /// No per-device rows in the device submenu; mirroring lives in one place.
    func deviceItems(for device: AndroidDevice) -> [NSMenuItem] {
        []
    }

    func menuWillOpen() {
        refreshRows()
    }

    // MARK: - Row building / refreshing

    private func refreshRows() {
        let devices = viewModel.devices
        mirror.syncDevices(devices)
        guard let submenu = notificationsSubmenu, !devices.isEmpty else { return }
        fill(submenu, devices: devices)
    }

    private func fill(_ menu: NSMenu, devices: [AndroidDevice]) {
        let stableIDs = devices.map { $0.stableID }
        if stableIDs != builtDeviceIDs || rowsNeedRebuild(devices) {
            rebuild(menu, devices: devices, stableIDs: stableIDs)
        }
        updateStatusItems(devices)
    }

    private func rebuild(
        _ menu: NSMenu, devices: [AndroidDevice], stableIDs: [String]
    ) {
        menu.removeAllItems()
        deviceRows.removeAll()
        rowStates.removeAll()
        statusItems.removeAll()

        for device in devices {
            let isOn = mirror.isEnabled(for: device)

            let rowItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            let rowView = ToggleMenuItemView(
                title: "Mirror notifications · \(device.name)",
                icon: isOn ? "bell.badge" : "bell",
                isOn: isOn
            ) { [weak self] isOn in
                self?.mirror.setDeviceEnabled(isOn, for: device)
                self?.refreshRows()
            }
            rowItem.view = rowView
            let rowHelp =
                "Reads Android notification text over ADB and posts it in macOS Notification Center. Off by default for this device."
            rowItem.toolTip = rowHelp
            rowView.toolTip = rowHelp
            menu.addItem(rowItem)
            deviceRows[device.stableID] = rowView
            rowStates[device.stableID] = isOn

            let statusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            statusItem.indentationLevel = 1
            menu.addItem(statusItem)
            statusItems[device.stableID] = statusItem
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Open Notification Settings",
            action: #selector(openNotificationSettings(_:)),
            keyEquivalent: ""
        )
        settingsItem.target = self
        settingsItem.image = Self.templateImage(symbolName: "gearshape")
        settingsItem.toolTip =
            "Choose how AndroLaunch banners appear in macOS Notification Center."
        menu.addItem(settingsItem)

        builtDeviceIDs = stableIDs
    }

    private func rowsNeedRebuild(_ devices: [AndroidDevice]) -> Bool {
        for device in devices where rowStates[device.stableID] != mirror.isEnabled(for: device) {
            return true
        }
        return false
    }

    private func updateStatusItems(_ devices: [AndroidDevice]) {
        for device in devices {
            guard let item = statusItems[device.stableID] else { continue }
            item.attributedTitle = NSAttributedString(
                string: mirror.statusText(for: device),
                attributes: [
                    .font: NSFont.menuFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            )
            let state = mirror.state(for: device)
            item.toolTip = state.lastError
        }
    }

    // MARK: - Actions

    @objc private func openNotificationSettings(_ sender: Any?) {
        let candidates = [
            // Contract URL: the classic Notification pane identifier.
            "x-apple.systempreferences:com.apple.preference.notifications",
            // Current System Settings pane identifiers, as a fallback.
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?",
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
        let settingsURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(
            at: settingsURL, configuration: configuration, completionHandler: nil)
    }

    // MARK: - Helpers

    private static func templateImage(symbolName: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.size = NSSize(width: 16, height: 16)
        image?.isTemplate = true
        return image
    }
}

// MARK: - NSMenuDelegate

extension NotificationMenuSection: NSMenuDelegate {
    /// Fires when the Notifications submenu itself opens (the main menu's
    /// `menuWillOpen` already reaches us through `MenuSectionProviding`).
    func menuWillOpen(_ menu: NSMenu) {
        refreshRows()
    }
}
