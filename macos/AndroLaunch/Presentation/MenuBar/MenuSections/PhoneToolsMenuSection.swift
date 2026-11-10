//
//  PhoneToolsMenuSection.swift
//  AndroLaunch
//
//  Per-device phone tools in the status menu: Ring Phone, Storage…, and copying
//  a verification code that arrived as a notification. Owned by phone-companion.
//
//  Everything here is honest about readiness: rows that need AndroLaunch Comp are
//  disabled with a tooltip saying so when the app is missing, and the code row
//  explains that notification mirroring must be on before it can read anything.
//

import AppKit
import Combine

final class PhoneToolsMenuSection: MenuSectionProviding {
    let sectionID = "phone-tools"
    var topLevelOrder: Int { 60 }

    private let viewModel: MenuViewModel
    private var cancellables = Set<AnyCancellable>()

    /// Rows for one device, retained so `menuWillOpen()` can refresh in place.
    private struct DeviceRows {
        let deviceID: String
        let deviceName: String
        let ringItem: NSMenuItem
        let storageItem: NSMenuItem
        let codeItem: NSMenuItem
    }

    private var rowsByDevice: [String: DeviceRows] = [:]

    init(viewModel: MenuViewModel) {
        self.viewModel = viewModel
        // Ring state changes while the menu is open must relabel the row.
        RingService.shared.$ringingUntil
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshRingRows() }
            .store(in: &cancellables)
    }

    // MARK: - MenuSectionProviding

    func topLevelItems() -> [NSMenuItem] { [] }

    func deviceItems(for device: AndroidDevice) -> [NSMenuItem] {
        let separator = NSMenuItem.separator()

        let ring = NSMenuItem(
            title: "Ring Phone", action: #selector(ringPhone(_:)), keyEquivalent: "")
        ring.target = self
        ring.representedObject = device.id
        ring.image = symbol("bell.badge.fill")

        let storage = NSMenuItem(
            title: "Storage…", action: #selector(showStorage(_:)), keyEquivalent: "")
        storage.target = self
        storage.representedObject = device.id
        storage.image = symbol("internaldrive")

        let code = NSMenuItem(
            title: "Copy Verification Code",
            action: #selector(copyVerificationCode(_:)), keyEquivalent: "")
        code.target = self
        code.representedObject = device.id
        code.image = symbol("number.square")

        rowsByDevice[device.id] = DeviceRows(
            deviceID: device.id, deviceName: device.name,
            ringItem: ring, storageItem: storage, codeItem: code)
        refresh(deviceID: device.id)
        return [separator, ring, storage, code]
    }

    func menuWillOpen() {
        for device in viewModel.devices {
            refresh(deviceID: device.id)
        }
    }

    // MARK: - Refreshing

    private func refreshRingRows() {
        for deviceID in rowsByDevice.keys {
            refresh(deviceID: deviceID)
        }
    }

    private func refresh(deviceID: String) {
        guard let rows = rowsByDevice[deviceID] else { return }
        let state = CompanionClient.shared.state(for: deviceID)
        let companionMissing: Bool
        if case .notInstalled = state {
            companionMissing = true
        } else {
            companionMissing = false
        }

        let ringing = RingService.shared.isRinging(deviceID: deviceID)
        rows.ringItem.title = ringing ? "Stop Ringing" : "Ring Phone"
        rows.ringItem.image = symbol(ringing ? "bell.slash.fill" : "bell.badge.fill")
        rows.ringItem.isEnabled = !companionMissing
        rows.ringItem.toolTip = companionMissing
            ? "AndroLaunch Comp is not installed on \(rows.deviceName)."
            : (ringing
                ? "Stops ringing the phone."
                : "Rings \(rows.deviceName) at alarm volume for up to 30 seconds. Do Not Disturb may still silence it on some phones.")

        rows.storageItem.isEnabled = true
        rows.storageItem.toolTip = "Shows used space, folders and the largest media files on \(rows.deviceName)."

        // Notification text is only available while mirroring is on for this device;
        // the tooltip says so instead of silently doing nothing.
        let code = latestVerificationCode(deviceID: deviceID)
        if let code {
            rows.codeItem.title = "Copy Verification Code: \(code)"
            rows.codeItem.isEnabled = true
            rows.codeItem.toolTip = "Copies \(code) to the Mac clipboard."
        } else {
            rows.codeItem.title = "Copy Verification Code"
            rows.codeItem.isEnabled = false
            rows.codeItem.toolTip =
                "No code found yet. Turn on notification mirroring for this device in the Notifications menu to alert AndroLaunch to incoming codes."
        }
    }

    /// Newest notification that carries a one-time code, ignoring sensitive apps.
    private func latestVerificationCode(deviceID: String) -> String? {
        guard let device = viewModel.devices.first(where: { $0.id == deviceID }) else { return nil }
        let records = NotificationMirror.shared.latestRecords(for: device)
        let sorted = records.sorted { $0.postTime > $1.postTime }
        for record in sorted {
            if record.isSensitive { continue }
            if NotificationMirror.isSensitivePackage(record.packageName) { continue }
            guard let text = record.displayText else { continue }
            if let code = VerificationCode.extract(from: text) { return code }
        }
        return nil
    }

    // MARK: - Actions

    @objc private func ringPhone(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        RingService.shared.toggle(deviceID: deviceID)
        refresh(deviceID: deviceID)
    }

    @objc private func showStorage(_ sender: NSMenuItem) {
        guard sender.representedObject is String else { return }
        PanelRouter.openStorageAnalytics()
    }

    @objc private func copyVerificationCode(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String,
            let code = latestVerificationCode(deviceID: deviceID)
        else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        refresh(deviceID: deviceID)
    }

    // MARK: - Helpers

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.size = NSSize(width: 16, height: 16)
        image?.isTemplate = true
        return image
    }
}
