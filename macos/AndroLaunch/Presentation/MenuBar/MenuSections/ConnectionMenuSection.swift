//
//  ConnectionMenuSection.swift
//  AndroLaunch
//
//  Owned by the connection feature. Surfaces continuity in the status menu
//  without turning it into a dashboard:
//
//  - Per connected device, a short "Change Connection" submenu lists the
//    transports AndroLaunch has seen for that phone (checkmark on the active one)
//    and lets the user add a network address (LAN, Tailscale, ZeroTier, SSH
//    forward — all just `adb connect` targets).
//  - Top level, up to three quiet "Reconnect <name>" rows appear only while a
//    remembered device is offline, so a phone that dropped off Wi-Fi is one click
//    away instead of a trip through Previous Devices.
//

import AppKit
import Combine

final class ConnectionMenuSection: MenuSectionProviding {
    let sectionID = "connection"
    var topLevelOrder: Int { 30 }
    let viewModel: MenuViewModel

    private let coordinator = ConnectionCoordinator.shared
    private var retainedTopLevelItems: [NSMenuItem] = []
    private var cancellables = Set<AnyCancellable>()

    /// The identity behind a top-level "Reconnect" row. Deliberately *not* a
    /// `String`: `StatusMenuController.updateMenu` treats String represented
    /// objects as connected-device rows, and these are continuity affordances.
    private final class ReconnectTarget: NSObject {
        let identity: String

        init(identity: String) {
            self.identity = identity
        }
    }

    /// The address of a "Change Connection" row, kept as an object because
    /// `NSMenuItem.representedObject` can only carry one value.
    private final class EndpointTarget: NSObject {
        let identity: String
        let address: String

        init(identity: String, address: String) {
            self.identity = identity
            self.address = address
        }
    }

    init(viewModel: MenuViewModel) {
        self.viewModel = viewModel
        // Keep retained rows honest while a background reconnect finishes. The
        // device list itself also updates the menu through MenuViewModel; this
        // observer only patches the rows that are already on screen.
        coordinator.$rememberedDisconnectedDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshRetainedTopLevelItems()
            }
            .store(in: &cancellables)
    }

    // MARK: - Top level (continuity affordance)

    func topLevelItems() -> [NSMenuItem] {
        retainedTopLevelItems = makeReconnectItems()
        return retainedTopLevelItems
    }

    private func makeReconnectItems() -> [NSMenuItem] {
        let remembered = coordinator.rememberedDisconnectedDevices
        guard !remembered.isEmpty else { return [] }
        return remembered.prefix(3).map { device in
            makeReconnectItem(for: device)
        }
    }

    private func makeReconnectItem(for device: RememberedDevice) -> NSMenuItem {
        let item = NSMenuItem(
            title: "",
            action: #selector(reconnectDevice(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = ReconnectTarget(identity: device.identity)
        // Device names vary in length: wrap inside the fixed menu width instead of
        // letting a long name stretch the menu.
        item.view = MenuTextItemView(
            text: reconnectTitle(for: device),
            symbolName: "arrow.triangle.2.circlepath",
            textColor: device.isReconnecting ? .secondaryLabelColor : .labelColor)
        item.isEnabled = !device.isReconnecting
        item.toolTip = "Try the remembered wireless addresses for \(device.name)"
        return item
    }

    private func reconnectTitle(for device: RememberedDevice) -> String {
        device.isReconnecting ? "Reconnecting \(device.name)…" : "Reconnect \(device.name)"
    }

    @objc private func reconnectDevice(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? ReconnectTarget else { return }
        coordinator.reconnect(identity: target.identity)
    }

    // MARK: - Per-device items

    func deviceItems(for device: AndroidDevice) -> [NSMenuItem] {
        let identity = device.stableID
        let changeItem = NSMenuItem(
            title: "Change Connection", action: nil, keyEquivalent: "")
        changeItem.image = NSImage(
            systemSymbolName: "arrow.left.arrow.right",
            accessibilityDescription: "Change Connection")
        changeItem.image?.size = NSSize(width: 16, height: 16)
        changeItem.image?.isTemplate = true

        let submenu = NSMenu(title: "Change Connection")
        let activeAddress = device.id

        var endpoints = EndpointStore.shared.endpoints(for: identity)
        if !endpoints.contains(where: { $0.address == activeAddress }) {
            // The active transport is always represented so the checkmark has a
            // home even before the endpoint store has seen this phone.
            endpoints.insert(
                DeviceEndpoint(address: activeAddress, kind: device.transportKind), at: 0)
        }
        if endpoints.isEmpty {
            let emptyItem = NSMenuItem(
                title: "No remembered transports", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for endpoint in endpoints.prefix(5) {
                submenu.addItem(
                    makeEndpointItem(
                        endpoint, identity: identity, activeAddress: activeAddress))
            }
        }

        submenu.addItem(NSMenuItem.separator())
        let addItem = NSMenuItem(
            title: "Add Network Address…",
            action: #selector(addNetworkAddress(_:)),
            keyEquivalent: ""
        )
        addItem.target = self
        addItem.representedObject = identity
        addItem.image = NSImage(
            systemSymbolName: "plus.circle", accessibilityDescription: "Add Network Address")
        addItem.image?.size = NSSize(width: 16, height: 16)
        addItem.image?.isTemplate = true
        submenu.addItem(addItem)

        changeItem.submenu = submenu
        return [changeItem]
    }

    private func makeEndpointItem(
        _ endpoint: DeviceEndpoint, identity: String, activeAddress: String
    ) -> NSMenuItem {
        let isActive = endpoint.address == activeAddress
        let item = NSMenuItem(
            title: "\(endpoint.kind.displayName) · \(endpoint.address)",
            action: isActive || endpoint.kind == .usb ? nil : #selector(useEndpoint(_:)),
            keyEquivalent: ""
        )
        item.state = isActive ? .on : .off
        item.isEnabled = !isActive && endpoint.kind != .usb
        item.image = NSImage(
            systemSymbolName: endpoint.kind.symbolName,
            accessibilityDescription: endpoint.kind.displayName)
        item.image?.size = NSSize(width: 16, height: 16)
        item.image?.isTemplate = true

        if isActive {
            item.toolTip = "This is the transport \(endpoint.kind.displayName) is using now."
        } else if endpoint.kind == .usb {
            item.toolTip = "Connect over USB by plugging the cable in."
        } else {
            item.target = self
            item.representedObject = EndpointTarget(
                identity: identity, address: endpoint.address)
            item.toolTip = "Connect to \(endpoint.address) with adb."
        }
        return item
    }

    @objc private func useEndpoint(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? EndpointTarget else { return }
        coordinator.connect(identity: target.identity, address: target.address)
    }

    @objc private func addNetworkAddress(_ sender: NSMenuItem) {
        guard let identity = sender.representedObject as? String else { return }

        let alert = NSAlert()
        alert.messageText = "Add Network Address"
        alert.informativeText = """
            Enter the host:port ADB should connect to, for example 192.168.1.42:5555. \
            Tailscale, ZeroTier and SSH-forwarded addresses work the same way — any \
            address ADB can reach is accepted.
            """
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "192.168.1.42:5555"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let address = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard coordinator.addManualEndpoint(address, for: identity) else {
            AlertPresenter.showWarning(
                message:
                    "“\(address)” is not a host:port address. Use the form 192.168.1.42:5555.",
                title: "Invalid Address")
            return
        }
    }

    // MARK: - In-place refresh

    /// Called whenever the status menu opens. Refreshes the retained continuity
    /// rows (titles and enabled state) instead of forcing a full menu rebuild.
    /// Marks a structural change that arrived while the menu was on screen.
    private var needsStructuralRefresh = false

    func menuWillOpen() {
        // The menu is not being tracked yet, so inserting items here is safe.
        if needsStructuralRefresh {
            needsStructuralRefresh = false
            rebuildRetainedTopLevelItems(Array(coordinator.rememberedDisconnectedDevices.prefix(3)))
        }
        coordinator.menuWillAppear()
        refreshRetainedTopLevelItems()
    }

    private func refreshRetainedTopLevelItems() {
        guard !retainedTopLevelItems.isEmpty else { return }
        // While the menu is on screen, touch nothing: even a title change can alter a
        // row's line count and invalidate AppKit's highlighted-row bookkeeping. The
        // state is re-read the next time the menu opens (a few seconds away at most).
        guard !MenuTrackingState.isOpen else {
            needsStructuralRefresh = true
            return
        }

        let remembered = Array(coordinator.rememberedDisconnectedDevices.prefix(3))
        let retainedIdentities = retainedTopLevelItems.compactMap {
            ($0.representedObject as? ReconnectTarget)?.identity
        }
        if retainedIdentities != remembered.map(\.identity) {
            rebuildRetainedTopLevelItems(remembered)
            return
        }

        for item in retainedTopLevelItems {
            guard let identity = (item.representedObject as? ReconnectTarget)?.identity,
                let device = remembered.first(where: { $0.identity == identity })
            else { continue }
            (item.view as? MenuTextItemView)?.update(
                text: reconnectTitle(for: device),
                textColor: device.isReconnecting ? .secondaryLabelColor : .labelColor)
            item.isEnabled = !device.isReconnecting
        }
    }

    /// Replaces the retained rows inside the menu that currently owns them, so a
    /// reconnect finishing while the menu is open updates it without rebuilding.
    private func rebuildRetainedTopLevelItems(_ remembered: [RememberedDevice]) {
        guard let menu = retainedTopLevelItems.compactMap(\.menu).first,
            let firstItem = retainedTopLevelItems.first,
            let startIndex = menu.items.firstIndex(of: firstItem)
        else { return }

        for item in retainedTopLevelItems {
            menu.removeItem(item)
        }
        retainedTopLevelItems = []
        for (offset, device) in remembered.enumerated() {
            let item = makeReconnectItem(for: device)
            menu.insertItem(item, at: startIndex + offset)
            retainedTopLevelItems.append(item)
        }
    }
}
