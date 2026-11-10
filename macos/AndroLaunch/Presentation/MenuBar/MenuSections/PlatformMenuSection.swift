//
//  PlatformMenuSection.swift
//  AndroLaunch
//
//  Trackpad, Glance board and camera preview in the status menu.
//  Owned by platform-extras.
//
//  Items are created once per menu rebuild and then updated in place from
//  `menuWillOpen()`, matching the no-rebuild-while-open rule in
//  `MenuSection.swift`. Top-level rows act on the currently selected device;
//  per-device rows target one specific phone.
//

import AppKit
import Combine

final class PlatformMenuSection: NSObject, MenuSectionProviding {
    let sectionID = "platform-extras"
    var topLevelOrder: Int { 70 }

    private let viewModel: MenuViewModel

    private var retainedItems: [NSMenuItem] = []
    private var deviceItemsByID: [String: [NSMenuItem]] = [:]

    private var trackpadItem: NSMenuItem?
    private var glanceItem: NSMenuItem?
    private var cameraItem: NSMenuItem?
    private var cameraPreviewBackItem: NSMenuItem?
    private var cameraPreviewFrontItem: NSMenuItem?
    private var cameraStopItem: NSMenuItem?
    private var cameraExtensionItem: NSMenuItem?

    init(viewModel: MenuViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    // MARK: - MenuSectionProviding

    func topLevelItems() -> [NSMenuItem] {
        retainedItems = []
        deviceItemsByID = [:]

        let trackpad = makeItem(
            "Trackpad…", action: #selector(showTrackpad(_:)), symbol: "hand.draw")
        trackpad.toolTip = "Send Android navigation gestures from a floating Mac panel."
        trackpadItem = trackpad

        let glance = makeItem(
            "Show Glance Widgets", action: #selector(toggleGlance(_:)),
            symbol: "rectangle.on.rectangle.angled")
        glance.toolTip = "Floating board with battery, storage and quick apps."
        glanceItem = glance

        let camera = makeItem(
            "Camera Preview", action: nil, symbol: "camera")
        camera.toolTip = "Preview the phone's camera in a scrcpy window."
        let cameraSubmenu = NSMenu()
        let backCamera = makeItem(
            "Back Camera", action: #selector(previewCamera(_:)), symbol: "camera.fill")
        backCamera.tag = 0
        let frontCamera = makeItem(
            "Front Camera", action: #selector(previewCamera(_:)), symbol: "person.crop.square.fill")
        frontCamera.tag = 1
        let stopCamera = makeItem(
            "Stop Preview", action: #selector(stopCamera(_:)), symbol: "stop.fill")
        let extensionRow = makeItem(
            "Camera Extension…", action: #selector(openCameraExtension(_:)),
            symbol: "video.badge.plus")
        cameraSubmenu.addItem(backCamera)
        cameraSubmenu.addItem(frontCamera)
        cameraSubmenu.addItem(NSMenuItem.separator())
        cameraSubmenu.addItem(stopCamera)
        cameraSubmenu.addItem(NSMenuItem.separator())
        cameraSubmenu.addItem(extensionRow)
        camera.submenu = cameraSubmenu
        cameraItem = camera
        cameraPreviewBackItem = backCamera
        cameraPreviewFrontItem = frontCamera
        cameraStopItem = stopCamera
        cameraExtensionItem = extensionRow

        retainedItems = [trackpad, glance, camera]
        refreshState()
        return retainedItems
    }

    func deviceItems(for device: AndroidDevice) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        let trackpad = makeItem(
            "Trackpad…", action: #selector(showTrackpadForDevice(_:)), symbol: "hand.draw")
        trackpad.representedObject = device.id
        trackpad.toolTip = "Send gestures to \(device.name)."
        items.append(trackpad)

        let camera = NSMenuItem(title: "Camera Preview", action: nil, keyEquivalent: "")
        camera.image = symbolImage("camera")
        let submenu = NSMenu()

        let back = makeItem(
            "Back Camera", action: #selector(previewCamera(_:)), symbol: "camera.fill")
        back.representedObject = device.id
        back.tag = 0
        let front = makeItem(
            "Front Camera", action: #selector(previewCamera(_:)), symbol: "person.crop.square.fill")
        front.representedObject = device.id
        front.tag = 1
        let stop = makeItem(
            "Stop Preview", action: #selector(stopCamera(_:)), symbol: "stop.fill")
        let extensionRow = makeItem(
            "Camera Extension…", action: #selector(openCameraExtension(_:)),
            symbol: "video.badge.plus")
        submenu.addItem(back)
        submenu.addItem(front)
        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(stop)
        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(extensionRow)
        camera.submenu = submenu
        items.append(camera)

        let glance = makeItem(
            "Glance Widgets", action: #selector(toggleGlance(_:)),
            symbol: "rectangle.on.rectangle.angled")
        items.append(glance)

        deviceItemsByID[device.id] = [trackpad, back, front, stop, glance]
        return items
    }

    func menuWillOpen() {
        refreshState()
    }

    // MARK: - State

    private var currentDevice: AndroidDevice? {
        let devices = viewModel.devices
        if let id = viewModel.currentDeviceID ?? HubStore.shared.selectedDeviceID,
            let match = devices.first(where: { $0.id == id })
        {
            return match
        }
        return devices.first
    }

    private func refreshState() {
        let device = currentDevice
        let camera = CameraController.shared
        let glance = GlanceBoardController.shared

        trackpadItem?.isEnabled = device != nil
        glanceItem?.isEnabled = true
        let boardVisible = glance.isVisible
        glanceItem?.title = boardVisible ? "Hide Glance Widgets" : "Show Glance Widgets"
        glanceItem?.state = boardVisible ? .on : .off

        cameraItem?.isEnabled = device != nil || camera.isPreviewing
        let canPreviewSelected = device.map { camera.canPreview(deviceID: $0.id) } ?? false
        cameraPreviewBackItem?.isEnabled = canPreviewSelected
        cameraPreviewFrontItem?.isEnabled = canPreviewSelected
        cameraStopItem?.isEnabled = camera.isPreviewing
        cameraExtensionItem?.isEnabled = true

        for (deviceID, items) in deviceItemsByID {
            let available = camera.canPreview(deviceID: deviceID)
            for item in items {
                switch item.title {
                case "Stop Preview":
                    item.isEnabled = camera.isPreviewing
                case "Glance Widgets":
                    item.isEnabled = true
                default:
                    item.isEnabled = available
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func showTrackpad(_ sender: NSMenuItem) {
        TrackpadController.shared.show(deviceID: currentDevice?.id)
    }

    @objc private func showTrackpadForDevice(_ sender: NSMenuItem) {
        TrackpadController.shared.show(deviceID: sender.representedObject as? String)
    }

    @objc private func toggleGlance(_ sender: NSMenuItem) {
        let controller = GlanceBoardController.shared
        controller.toggle()
        controller.setEnabled(controller.isVisible)
        refreshState()
    }

    @objc private func previewCamera(_ sender: NSMenuItem) {
        let lens: CameraLens = sender.tag == 1 ? .front : .back
        let controller = CameraController.shared
        controller.setLens(lens)

        if let deviceID = sender.representedObject as? String {
            controller.preview(deviceID: deviceID)
        } else if let device = currentDevice {
            controller.preview(deviceID: device.id)
        } else {
            controller.preview()
        }
        refreshState()
    }

    @objc private func stopCamera(_ sender: NSMenuItem) {
        CameraController.shared.stopPreview()
        refreshState()
    }

    @objc private func openCameraExtension(_ sender: NSMenuItem) {
        CameraController.shared.openExtensionSettings()
    }

    // MARK: - Helpers

    private func makeItem(_ title: String, action: Selector?, symbol: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = symbolImage(symbol)
        return item
    }

    private func symbolImage(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.size = NSSize(width: 16, height: 16)
        return image
    }
}
