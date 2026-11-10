//
//  ClipboardMenuSection.swift
//  AndroLaunch
//
//  Owned by the clipboard feature. A small top-level "Clipboard" hub plus one
//  "Send Clipboard to Device" row per device; all state comes from ClipboardBridge.
//

import AppKit
import Combine

final class ClipboardMenuSection: NSObject, MenuSectionProviding {
    let sectionID = "clipboard"
    var topLevelOrder: Int { 10 }

    let viewModel: MenuViewModel

    private let bridge: ClipboardBridge
    private var topLevelItem: NSMenuItem?
    private var deviceEntries: [DeviceEntry] = []
    private var cancellables = Set<AnyCancellable>()

    private var isInstalling = false

    private struct DeviceEntry {
        let deviceID: String
        let name: String
        let statusItem: NSMenuItem
    }

    init(viewModel: MenuViewModel, bridge: ClipboardBridge = .shared) {
        self.viewModel = viewModel
        self.bridge = bridge
        super.init()

        // Keep companion detection warm so the menu never has to guess a device's state.
        viewModel.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.bridge.refresh(devices: devices)
            }
            .store(in: &cancellables)

        // Bridge events may land while the menu is open; refresh the retained labels.
        bridge.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateRetainedItems()
            }
            .store(in: &cancellables)
    }

    // MARK: - MenuSectionProviding

    func topLevelItems() -> [NSMenuItem] {
        topLevelItem = nil
        deviceEntries = []

        let devices = viewModel.devices
        guard !devices.isEmpty else { return [] }

        let clipboardItem = NSMenuItem(title: "Clipboard", action: nil, keyEquivalent: "")
        clipboardItem.image = symbolImage(named: "doc.on.clipboard")
        clipboardItem.submenu = NSMenu(title: "Clipboard")

        topLevelItem = clipboardItem
        rebuildSubmenu()
        bridge.refresh(devices: devices)
        return [clipboardItem]
    }

    func deviceItems(for device: AndroidDevice) -> [NSMenuItem] {
        // Keep the cached companion state current for the enabled-ness decision.
        bridge.refreshCompanionStatus(for: device.id)

        let item = NSMenuItem(
            title: "Send Clipboard to Device",
            action: #selector(sendClipboardToDevice(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = device.id
        item.image = symbolImage(named: "doc.on.clipboard")

        let pasteboardText = NSPasteboard.general.string(forType: .string)
        let hasText = !(pasteboardText ?? "").isEmpty
        let companionMissing = bridge.state(for: device.id).companionInstalled == false

        item.isEnabled = hasText && !companionMissing
        if companionMissing {
            item.toolTip =
                "AndroLaunch Comp is not installed on this device, so text cannot be delivered."
        } else if !hasText {
            item.toolTip = "Copy some text on this Mac first."
        } else {
            item.toolTip =
                "Sends the text currently on this Mac's clipboard to the device through AndroLaunch Comp."
        }

        // Images are explicit one-shot actions, clearly marked as images: sending
        // every screenshot automatically would be noise, and pulling is limited by
        // Android's background-clipboard rule.
        let hasImage = bridge.pasteboardHasImage

        let sendImage = NSMenuItem(
            title: "Send Clipboard Image to Device",
            action: #selector(sendClipboardImageToDevice(_:)), keyEquivalent: "")
        sendImage.target = self
        sendImage.representedObject = device.id
        sendImage.image = symbolImage(named: "photo")
        sendImage.isEnabled = hasImage && !companionMissing
        if companionMissing {
            sendImage.toolTip = "AndroLaunch Comp is required to paste images on the phone."
        } else if !hasImage {
            sendImage.toolTip = "Copy an image or screenshot on this Mac first."
        } else {
            sendImage.toolTip =
                "Puts the image from this Mac's clipboard on the phone clipboard as a real image (up to 8 MB, downscaled if needed)."
        }

        let pullImage = NSMenuItem(
            title: "Pull Image from Device",
            action: #selector(pullImageFromDevice(_:)), keyEquivalent: "")
        pullImage.target = self
        pullImage.representedObject = device.id
        pullImage.image = symbolImage(named: "photo.badge.arrow.down")
        pullImage.isEnabled = !companionMissing
        pullImage.toolTip = companionMissing
            ? "AndroLaunch Comp is required to read the phone clipboard."
            : "Copies an image from the phone clipboard to this Mac. Android only allows this while AndroLaunch Comp is open on the phone."

        return [item, sendImage, pullImage]
    }

    func menuWillOpen() {
        guard topLevelItem != nil else { return }
        bridge.refresh(devices: viewModel.devices)
        rebuildSubmenu()
    }

    // MARK: - Submenu

    private func rebuildSubmenu() {
        guard let submenu = topLevelItem?.submenu else { return }

        submenu.removeAllItems()
        deviceEntries = []

        let devices = viewModel.devices

        for device in devices {
            let toggleItem = NSMenuItem()
            toggleItem.view = makeToggleView(
                deviceID: device.id, deviceName: device.name,
                isOn: bridge.state(for: device.id).enabled)
            submenu.addItem(toggleItem)

            let statusText = statusLine(forDeviceID: device.id, name: device.name)
            let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            statusItem.attributedTitle = statusTitle(statusText)
            submenu.addItem(statusItem)

            deviceEntries.append(
                DeviceEntry(deviceID: device.id, name: device.name, statusItem: statusItem))
        }

        if !devices.isEmpty {
            let imageNote = NSMenuItem(
                title: "Images: PNG/JPEG up to 8 MB, through AndroLaunch Comp",
                action: nil, keyEquivalent: "")
            imageNote.isEnabled = false
            imageNote.attributedTitle = statusTitle(imageNote.title)
            submenu.insertItem(imageNote, at: submenu.numberOfItems)
        }

        // The companion ships inside the app; installing it is one adb command.
        if let target = devices.first(where: {
            bridge.state(for: $0.id).companionInstalled == false
        }) {
            submenu.addItem(NSMenuItem.separator())

            let installRow = NSMenuItem(
                title: "Install AndroLaunch Comp",
                action: #selector(installCompanion(_:)),
                keyEquivalent: ""
            )
            installRow.target = self
            installRow.representedObject = target.id
            installRow.image = symbolImage(named: "arrow.down.app")
            installRow.isEnabled = bridge.canInstallCompanion && !isInstalling
            installRow.toolTip = bridge.canInstallCompanion
                ? "Installs the bundled AndroLaunch Comp app on \(target.name) over ADB."
                : "This build does not include the AndroLaunch Comp APK."
            submenu.addItem(installRow)

            if isInstalling {
                let progress = NSMenuItem(
                    title: "Installing AndroLaunch Comp…", action: nil, keyEquivalent: "")
                progress.isEnabled = false
                submenu.addItem(progress)
            }
        }
    }

    private func makeToggleView(deviceID: String, deviceName: String, isOn: Bool)
        -> ToggleMenuItemView
    {
        ToggleMenuItemView(
            title: "Share clipboard · \(deviceName)",
            icon: "doc.on.clipboard",
            isOn: isOn
        ) { [weak self] isOn in
            self?.bridge.setEnabled(isOn, for: deviceID)
        }
    }

    /// Refreshes retained rows in place (status labels and enabled state) without rebuilding.
    private func updateRetainedItems() {
        guard topLevelItem != nil else { return }

        for entry in deviceEntries {
            let statusText = statusLine(forDeviceID: entry.deviceID, name: entry.name)
            entry.statusItem.title = statusText
            entry.statusItem.attributedTitle = statusTitle(statusText)
        }

        topLevelItem?.isEnabled = !viewModel.devices.isEmpty
    }

    // MARK: - Helpers

    private func statusLine(forDeviceID deviceID: String, name: String) -> String {
        let status = bridge.statusText(for: deviceID)
        // With several devices the status row needs to name the device it describes.
        return viewModel.devices.count > 1 ? "\(name) · \(status)" : status
    }

    private func statusTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.menuFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
    }

    private func symbolImage(named name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.size = NSSize(width: 16, height: 16)
        image?.isTemplate = true
        return image
    }

    // MARK: - Actions

    @objc private func sendClipboardToDevice(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        bridge.sendCurrentClipboard(to: deviceID)
    }

    @objc private func sendClipboardImageToDevice(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        bridge.sendCurrentImage(to: deviceID)
    }

    @objc private func pullImageFromDevice(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        bridge.pullImage(from: deviceID)
    }

    @objc private func installCompanion(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        guard !isInstalling else { return }
        isInstalling = true
        rebuildSubmenu()

        CompanionClient.shared.install(deviceID: deviceID) { [weak self] result in
            guard let self else { return }
            self.isInstalling = false
            switch result {
            case .success:
                // Re-check through the existing path so the row disappears.
                self.bridge.refreshCompanionStatus(for: deviceID, force: true)
            case .failure(let error):
                AlertPresenter.showWarning(
                    message: "AndroLaunch Comp could not be installed: \(error.localizedDescription)")
            }
            self.rebuildSubmenu()
        }
    }
}
