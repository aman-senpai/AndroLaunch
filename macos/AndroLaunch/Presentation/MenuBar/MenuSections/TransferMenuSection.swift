//
//  TransferMenuSection.swift
//  AndroLaunch
//
//  Owned by the transfer feature: the per-device "Send Files to Device…" row,
//  plus a live progress and cancel row while a batch is running. The top-level
//  menu stays quiet on purpose — transfers live one level down, with the device.
//

import AppKit
import Combine

final class TransferMenuSection: MenuSectionProviding {
    let sectionID = "transfer"
    var topLevelOrder: Int { 20 }
    let viewModel: MenuViewModel

    private let coordinator: TransferCoordinator
    private var cancellables = Set<AnyCancellable>()

    /// Rows kept per device so `menuWillOpen()` and progress changes mutate them in
    /// place instead of forcing the submenu to be rebuilt.
    private struct DeviceRows {
        let sendItem: NSMenuItem
        let progressItem: NSMenuItem
        let cancelItem: NSMenuItem
    }
    private var rowsByDevice: [String: DeviceRows] = [:]

    init(viewModel: MenuViewModel, coordinator: TransferCoordinator = .shared) {
        self.viewModel = viewModel
        self.coordinator = coordinator
        coordinator.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshRows() }
            .store(in: &cancellables)
    }

    /// The top-level menu stays quiet; transfers are a per-device action.
    func topLevelItems() -> [NSMenuItem] { [] }

    func deviceItems(for device: AndroidDevice) -> [NSMenuItem] {
        let sendItem = NSMenuItem(
            title: "Send Files to Device…",
            action: #selector(sendFilesToDevice(_:)),
            keyEquivalent: ""
        )
        sendItem.target = self
        sendItem.representedObject = device.id
        sendItem.image = menuIcon("arrow.up.doc", description: "Send Files")
        sendItem.toolTip = "Choose files to send to \(device.name)."

        let progressItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        progressItem.isEnabled = false
        progressItem.image = menuIcon("arrow.up.circle", description: "Transfer progress")

        let cancelItem = NSMenuItem(
            title: "Cancel Transfer",
            action: #selector(cancelTransfer(_:)),
            keyEquivalent: ""
        )
        cancelItem.target = self
        cancelItem.image = menuIcon("xmark.circle", description: "Cancel Transfer")

        let rows = DeviceRows(
            sendItem: sendItem, progressItem: progressItem, cancelItem: cancelItem)
        rowsByDevice[device.id] = rows
        apply(rows, deviceID: device.id)
        return [sendItem, progressItem, cancelItem]
    }

    /// Called whenever the status menu opens: refresh the retained rows in place.
    func menuWillOpen() {
        refreshRows()
    }

    // MARK: - Actions

    @objc private func sendFilesToDevice(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        let deviceName = viewModel.devices.first(where: { $0.id == deviceID })?.name ?? "Android device"

        let panel = NSOpenPanel()
        panel.title = "Send Files to \(deviceName)"
        panel.message = "Files are sent to /sdcard/Download on \(deviceName)."
        panel.prompt = "Send"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, !panel.urls.isEmpty, let self else { return }
            self.coordinator.enqueue(files: panel.urls, deviceID: deviceID)
        }
    }

    @objc private func cancelTransfer(_ sender: NSMenuItem) {
        coordinator.cancel()
    }

    // MARK: - Row state

    private func refreshRows() {
        let connectedIDs = Set(viewModel.devices.map { $0.id })
        if !connectedIDs.isEmpty {
            rowsByDevice = rowsByDevice.filter { connectedIDs.contains($0.key) }
        }
        for (deviceID, rows) in rowsByDevice {
            apply(rows, deviceID: deviceID)
        }
    }

    /// While a batch runs for the device the send row is replaced by a disabled
    /// "Sending n of m…" row and an enabled cancel row.
    private func apply(_ rows: DeviceRows, deviceID: String) {
        if let progress = coordinator.progress(for: deviceID) {
            rows.sendItem.isHidden = true
            rows.progressItem.isHidden = false
            rows.progressItem.isEnabled = false
            rows.progressItem.title = "Sending \(progress.completed) of \(progress.total)…"
            rows.cancelItem.isHidden = false
            rows.cancelItem.isEnabled = true
        } else {
            rows.sendItem.isHidden = false
            rows.progressItem.isHidden = true
            rows.cancelItem.isHidden = true
        }
    }

    private func menuIcon(_ symbol: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.size = NSSize(width: 16, height: 16)
        image?.isTemplate = true
        return image
    }
}
