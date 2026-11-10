//
//  StatusMenuController.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 11/29/25.
//

import AppKit
import Combine
import SwiftUI

final class StatusMenuController: NSObject, NSSearchFieldDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let viewModel: MenuViewModel
    var cancellables = Set<AnyCancellable>()
    var currentDeviceID: String?
    var pairingWindow: NSWindow?
    var manageCommandsWindow: NSWindow?
    var emulatorManagerWindow: NSWindow?
    var fileExplorerWindows: [String: NSWindow] = [:]
    /// Feature-owned menu contributions, in display order.
    var sections: [MenuSectionProviding] = []
    /// Set when the device list or a section changed while the menu was on screen.
    private var needsMenuRebuild = false
    /// The legacy right-click menu. It is only attached to the status item while
    /// it is on screen; left click opens the glass dashboard panel instead.
    private var legacyMenu: NSMenu?
    private var legacyMenuNeedsRebuild = true
    private var panelCloseObserver: NSObjectProtocol?
    private var panelOpenObserver: NSObjectProtocol?
    /// Fallback for right-clicks on the status item: AppKit only routes right
    /// mouse events through `sendAction(on:)` on some system versions, so a
    /// local monitor guarantees the legacy menu opens either way.
    private var rightClickMonitor: Any?
    
    init(viewModel: MenuViewModel) {
        self.viewModel = viewModel
        super.init()
        #if DEBUG
            // Headless panel design review. Runs before the menu bar item is
            // configured so the snapshot process exits without live services.
            // The controller is created on the main thread; the renderer is
            // main-actor isolated because ImageRenderer requires it.
            if MainActor.assumeIsolated({ MenuBarPanelSnapshotRenderer.renderIfRequested() }) {
                exit(0)
            }
        #endif
        sections = MenuSectionRegistry.makeSections(viewModel: viewModel)
        setupMenu()
        bindViewModel()
        panelCloseObserver = NotificationCenter.default.addObserver(
            forName: .menuBarPanelDidClose, object: nil, queue: .main
        ) { [weak self] _ in
            self?.statusItem.button?.highlight(false)
        }
        panelOpenObserver = NotificationCenter.default.addObserver(
            forName: .openMenuBarPanelRequested, object: nil, queue: .main
        ) { [weak self] _ in
            self?.showMenuBarPanel()
        }


        #if DEBUG
            if CommandLine.arguments.contains("--capture-menu-bar-panel") {
                let wantsNotifications = CommandLine.arguments.contains(
                    "--capture-menu-bar-panel-notifications")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.showMenuBarPanel(
                        initialTab: wantsNotifications ? .notifications : .apps)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
                    let args = CommandLine.arguments
                    let path =
                        args.firstIndex(of: "--capture-menu-bar-panel").flatMap { index in
                            args.indices.contains(index + 1) ? args[index + 1] : nil
                        } ?? "/tmp/androlaunch-panel.png"
                    _ = MenuBarPanelController.shared.captureLiveWindow(
                        to: URL(fileURLWithPath: path))
                    exit(0)
                }
            }
            if let index = CommandLine.arguments.firstIndex(of: "--open-panel-feature"),
                CommandLine.arguments.indices.contains(index + 1),
                let page = PanelFeaturePage(rawValue: CommandLine.arguments[index + 1])
            {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    PanelFeaturePageRouter.open(page)
                }
            }
            if CommandLine.arguments.contains("--open-legacy-menu") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.showLegacyMenu()
                }
            }
        #endif

        // Available in Release too: a launch flag is the easiest way to open the
        // panel for support/testing without synthesizing a status-item click.
        if CommandLine.arguments.contains("--open-menu-bar-panel") {
            // Let the accessory app finish installing its status item first; a
            // synchronous show during init can race AppKit's menu-bar layout.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.showPanelOnPrimaryScreen()
            }
        }
    }

    deinit {
        if let panelCloseObserver {
            NotificationCenter.default.removeObserver(panelCloseObserver)
        }
        if let panelOpenObserver {
            NotificationCenter.default.removeObserver(panelOpenObserver)
        }
        if let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
        }
    }
    
    private func setupMenu() {
        if let button = statusItem.button {
            if let menuIcon = NSImage(named: "MenuIcons") {
                menuIcon.size = NSSize(width: 18, height: 18)
                menuIcon.isTemplate = true
                button.image = menuIcon
            } else {
                let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
                button.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "AndroLaunch")?.withSymbolConfiguration(config)
            }
            button.imagePosition = .imageOnly
            button.title = ""
            button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            button.setAccessibilityLabel("AndroLaunch")
            button.setAccessibilityHelp(
                "Click for the device dashboard. Right-click for the full menu.")
            button.toolTip = "AndroLaunch — click for the dashboard, right-click for the menu"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updatePresence()
        refreshDevices()
    }
    
    /// Presence at a glance: the icon stays dimmed until a device is available, so the
    /// menu bar answers "is anything connected?" without opening the menu. The tooltip
    /// carries the detail (device count, charging, transport) instead of adding chrome.
    func updatePresence() {
        guard let button = statusItem.button else { return }
        let devices = viewModel.devices
        button.alphaValue = devices.isEmpty ? 0.55 : 1.0
        
        guard !devices.isEmpty else {
            button.toolTip = "AndroLaunch — no device connected"
            button.setAccessibilityLabel("AndroLaunch, no device connected")
            return
        }
        
        let charging = devices.filter { $0.isCharging == true }.count
        let wireless = devices.filter { $0.isWirelessTransport }.count
        var summary = devices.count == 1 ? devices[0].name : "\(devices.count) devices"
        if devices.count > 1 {
            summary = "\(summary) connected"
        }
        var details: [String] = []
        if charging > 0 { details.append("\(charging) charging") }
        if wireless > 0 { details.append("\(wireless) wireless") }
        if !details.isEmpty { summary += " · " + details.joined(separator: ", ") }
        
        button.toolTip = "AndroLaunch — \(summary)"
        button.setAccessibilityLabel("AndroLaunch, \(summary)")
    }
    
    private func bindViewModel() {
        viewModel.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePresence()
                self?.updateMenu()
            }
            .store(in: &cancellables)
        
        viewModel.$deviceApps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] appsMap in
                // Update submenus for all devices that have apps loaded
                // Ideally we would know which one changed, but iterating is cheap enough for a menu
                for (deviceID, _) in appsMap {
                    self?.updateDeviceSubmenu(for: deviceID)
                }
            }
            .store(in: &cancellables)

        
        viewModel.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenu() }
            .store(in: &cancellables)
        
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                // When loading state changes, update the current device's submenu if we know it
                if let currentDeviceID = self?.currentDeviceID {
                    self?.updateDeviceSubmenu(for: currentDeviceID)
                }
            }
            .store(in: &cancellables)
        
        viewModel.$isLoadingApps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoadingApps in
                if let currentDeviceID = self?.currentDeviceID {
                    // Update submenu to show/hide loader
                    self?.updateDeviceSubmenu(for: currentDeviceID)
                }
            }
            .store(in: &cancellables)
            
        // Listen for object changes (like audio toggle) to update specific rows without full rebuild
        viewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { _ in
            }
            .store(in: &cancellables)
            
        viewModel.$quickActionsStates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAllQuickActionsSubmenus()
            }
            .store(in: &cancellables)

        viewModel.$previousDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updatePreviousDevicesSection() }
            .store(in: &cancellables)

        viewModel.$connectingDeviceID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateConnectingState() }
            .store(in: &cancellables)
    }
    
    private func updateMenu() {
        // Rebuilding an open menu shifts AppKit's highlighted row and leaves the old
        // one painted as selected. Defer until the menu closes.
        if MenuTrackingState.isOpen {
            needsMenuRebuild = true
            return
        }
        // The legacy menu is built on demand for a right click. Live updates do
        // not need to keep a hidden menu in sync.
        guard let menu = statusItem.menu else {
            legacyMenuNeedsRebuild = true
            return
        }
        
        let deviceItems = menu.items.filter {
            if let id = $0.representedObject as? String {
                return !id.hasPrefix("previous_")
            }
            return false
        }
        let currentDeviceIDs = Set(viewModel.devices.map { $0.id })
        let menuDeviceIDs = Set(deviceItems.compactMap { $0.representedObject as? String })
        
        if currentDeviceIDs != menuDeviceIDs {
            rebuildMenu()
            return
        }
        
        // Update existing items in place
        for device in viewModel.devices {
            guard let item = menu.items.first(where: { ($0.representedObject as? String) == device.id }) else { continue }
            
            if let submenu = item.submenu {
                configureDeviceSubmenu(submenu, for: device)
            }
        }
        
        // Update Error Item if needed
        if viewModel.devices.isEmpty {
            if let item = menu.items.first(where: { $0.identifier?.rawValue == "DeviceConnectionStatus" }),
                let statusView = item.view as? MenuTextItemView
            {
                statusView.update(text: connectionStatusText())
            }
        }
    }

    /// Previous-device rows stay plain menu items so the submenu chevron keeps working.
    /// Their names are shortened instead of being allowed to widen the whole menu.
    private func menuTitle(forDeviceName name: String, limit: Int = 32) -> String {
        guard name.count > limit else { return name }
        return String(name.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Text for the empty device list. Kept short enough for two lines at the menu width.
    private func connectionStatusText() -> String {
        viewModel.error ?? "No authorized devices connected"
    }

    /// Update only the previous device items' connecting state without rebuilding the menu.
    private func updateConnectingState() {
        // Rebuilding previous-device submenus while they are on screen would reset the
        // highlight, so record the change and let the post-close rebuild pick it up.
        guard !MenuTrackingState.isOpen else {
            needsMenuRebuild = true
            return
        }
        guard let menu = statusItem.menu else {
            legacyMenuNeedsRebuild = true
            return
        }
        for item in menu.items {
            guard let id = item.representedObject as? String,
                id.hasPrefix("previous_")
            else { continue }
            let serial = String(id.dropFirst("previous_".count))
            if let prevDevice = viewModel.previousDevices.first(where: { $0.serialNumber == serial }),
                let submenu = item.submenu
            {
                configurePreviousDeviceSubmenu(submenu, previousDevice: prevDevice)
            }
        }
    }

    /// Rebuild only the "Previous Devices" section without touching connected device items.
    private func updatePreviousDevicesSection() {
        // Inserting or removing rows in the live menu corrupts highlight tracking.
        guard !MenuTrackingState.isOpen else {
            needsMenuRebuild = true
            return
        }
        guard let menu = statusItem.menu else {
            legacyMenuNeedsRebuild = true
            return
        }

        // Remove all previous device items (identified by "previous_" prefix or the header)
        var toRemove: [NSMenuItem] = []
        var foundPreviousSection = false
        for item in menu.items {
            if item.title == "Previous Devices" && !item.isEnabled {
                foundPreviousSection = true
                toRemove.append(item)
                continue
            }
            if foundPreviousSection {
                if let id = item.representedObject as? String, id.hasPrefix("previous_") {
                    toRemove.append(item)
                } else if item.isSeparatorItem {
                    // Stop at the next separator (before Emulator Manager)
                    break
                }
            }
        }
        for item in toRemove {
            menu.removeItem(item)
        }

        // Find the insertion point: after the last connected device item,
        // which is right before the separator before "Emulator Manager".
        var insertIndex = menu.items.count
        for (i, item) in menu.items.enumerated().reversed() {
            if item.title == "Emulator Manager" || item.title == "Previous Devices" {
                insertIndex = i
                break
            }
        }

        // Insert previous devices section
        guard !viewModel.previousDevices.isEmpty else { return }

        let separator = NSMenuItem.separator()
        let header = NSMenuItem(title: "Previous Devices", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(
            string: "Previous Devices",
            attributes: [
                .font: NSFont.menuFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )

        menu.insertItem(separator, at: insertIndex)
        menu.insertItem(header, at: insertIndex + 1)

        var offset = 2
        for prevDevice in viewModel.previousDevices {
            let isConnecting = viewModel.connectingDeviceID == prevDevice.serialNumber
            let prevItem = NSMenuItem(
                title: menuTitle(forDeviceName: prevDevice.name),
                action: nil,
                keyEquivalent: ""
            )
            prevItem.representedObject = "previous_\(prevDevice.serialNumber)"
            prevItem.image = NSImage(
                systemSymbolName: isConnecting ? "arrow.triangle.2.circlepath" : "clock.arrow.circlepath",
                accessibilityDescription: "Previous Device")
            prevItem.image?.size = NSSize(width: 16, height: 16)

            let submenu = NSMenu()
            configurePreviousDeviceSubmenu(submenu, previousDevice: prevDevice)
            prevItem.submenu = submenu
            menu.insertItem(prevItem, at: insertIndex + offset)
            offset += 1
        }
    }

    func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // The menu bar icon itself opens the one dashboard panel; the classic
        // menu is the right-click fallback and contains no separate Hub entry.
        addUtilityMenuItems(to: menu)
        menu.addItem(NSMenuItem.separator())

        // Refresh Item with icon
        let refreshItem = NSMenuItem(
            title: "Refresh Devices",
            action: #selector(refreshDevices),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        refreshItem.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(refreshItem)
        menu.addItem(NSMenuItem.separator())
        
        // Device List
        if viewModel.devices.isEmpty {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.view = MenuTextItemView(
                text: connectionStatusText(),
                textColor: .secondaryLabelColor)
            item.isEnabled = false
            item.identifier = NSUserInterfaceItemIdentifier("DeviceConnectionStatus")
            menu.addItem(item)
        } else {
            for device in viewModel.devices {
                // Determine if device is wireless
                let isWireless = device.id.contains(":") || 
                                device.id.contains("_tcp") || 
                                device.id.contains("_udp")
                
                let deviceItem = NSMenuItem(
                    title: "\(device.name)",
                    action: nil,
                    keyEquivalent: ""
                )
                deviceItem.representedObject = device.id
                deviceItem.toolTip = "\(device.name) is ready. Device ID: \(device.id)"
                
                // Create a custom view for the device item with connection indicator and hover effect
                let itemView = DeviceMenuItemView(
                    deviceName: device.name,
                    isWireless: isWireless
                )
                
                deviceItem.view = itemView
                
                let submenu = NSMenu()
                self.configureDeviceSubmenu(submenu, for: device)
                deviceItem.submenu = submenu
                menu.addItem(deviceItem)
            }
        }

        // Help is not a device action: separate it from the list above.
        menu.addItem(NSMenuItem.separator())

        let connectionHelp = NSMenuItem(title: "USB Connection Help…", action: #selector(showUSBConnectionHelp), keyEquivalent: "")
        connectionHelp.target = self
        connectionHelp.image = NSImage(systemSymbolName: "cable.connector", accessibilityDescription: "USB connection help")
        menu.addItem(connectionHelp)

        // Previous Devices Section
        if !viewModel.previousDevices.isEmpty {
            menu.addItem(NSMenuItem.separator())

            let prevHeader = NSMenuItem(title: "Previous Devices", action: nil, keyEquivalent: "")
            prevHeader.isEnabled = false
            prevHeader.attributedTitle = NSAttributedString(
                string: "Previous Devices",
                attributes: [
                    .font: NSFont.menuFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            )
            menu.addItem(prevHeader)

            for prevDevice in viewModel.previousDevices {
                let isConnecting = viewModel.connectingDeviceID == prevDevice.serialNumber

                let prevItem = NSMenuItem(
                    title: menuTitle(forDeviceName: prevDevice.name),
                    action: nil,
                    keyEquivalent: ""
                )
                prevItem.representedObject = "previous_\(prevDevice.serialNumber)"
                prevItem.image = NSImage(
                    systemSymbolName: isConnecting ? "arrow.triangle.2.circlepath" : "clock.arrow.circlepath",
                    accessibilityDescription: "Previous Device")
                prevItem.image?.size = NSSize(width: 16, height: 16)

                let submenu = NSMenu()
                configurePreviousDeviceSubmenu(submenu, previousDevice: prevDevice)
                prevItem.submenu = submenu
                menu.addItem(prevItem)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Feature sections: clipboard, transfers, connection, notifications,
        // calls, media, phone tools, platform extras. Sections may retain their
        // NSMenuItems across rebuilds to update them in place; an item that still
        // belongs to the previous menu must be detached before AppKit will accept
        // it in the new one ("Item to be inserted into menu already is in another
        // menu"). Detaching here keeps that contract safe for every section.
        let sectionItems = sections.flatMap { $0.topLevelItems() }
        if !sectionItems.isEmpty {
            sectionItems.forEach { item in
                item.menu?.removeItem(item)
                menu.addItem(item)
            }
            menu.addItem(NSMenuItem.separator())
        }
        
        // Emulator Manager Item
        let emulatorManagerItem = NSMenuItem(
            title: "Emulator Manager",
            action: #selector(openEmulatorManager(_:)),
            keyEquivalent: "e"
        )
        emulatorManagerItem.target = self
        emulatorManagerItem.image = NSImage(systemSymbolName: "iphone.gen3", accessibilityDescription: "Emulator Manager")
        emulatorManagerItem.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(emulatorManagerItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Pair Device Item
        let pairItem = NSMenuItem(
            title: "Wireless Pair",
            action: #selector(pairDeviceWirelessly),
            keyEquivalent: "p"
        )
        pairItem.target = self
        pairItem.image = NSImage(systemSymbolName: "qrcode", accessibilityDescription: "Pair")
        pairItem.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(pairItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Manage Shell Commands
        let manageShellItem = NSMenuItem(
            title: "Manage Commands",
            action: #selector(manageShellCommands(_:)),
            keyEquivalent: ""
        )
        manageShellItem.target = self
        manageShellItem.image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Manage Shell")
        manageShellItem.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(manageShellItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // About Item
        let aboutItem = NSMenuItem(
            title: "About",
            action: #selector(openGitHub),
            keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About")
        aboutItem.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit Item with icon
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApp.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        quitItem.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(quitItem)

        legacyMenu = menu
        legacyMenuNeedsRebuild = false
        // Assign only while the legacy menu is on screen; the status item itself
        // stays click-driven so left click can open the glass panel.
        if statusItem.menu != nil {
            statusItem.menu = menu
        }
    }

    // MARK: - Status item clicks

    @objc private func statusItemClicked(_ sender: Any?) {
        // The panel is the only surface. Right/control click behaves the same.
        toggleMenuBarPanel()
    }

    /// Launch helper: bypass the status-item geometry (which can be stale in a
    /// fresh accessory process) and anchor at the primary screen's menu bar.
    private func showPanelOnPrimaryScreen(attempt: Int = 0) {
        guard !MenuBarPanelController.shared.isVisible else { return }
        guard let screen = NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let anchor = CGRect(
            x: visible.midX, y: visible.maxY - 22, width: 1, height: 1)
        MenuBarPanelController.shared.show(
            anchor: anchor, actions: makePanelActions())
        guard attempt < 12 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self,
                !MenuBarPanelController.shared.isVisible
            else { return }
            self.showPanelOnPrimaryScreen(attempt: attempt + 1)
        }
    }

    private func showMenuBarPanel(initialTab: DeviceDashboardTab = .apps) {
        guard let button = statusItem.button, let window = button.window else { return }
        let rectInWindow = button.convert(button.bounds, to: nil)
        let anchor = MenuBarPanelGeometry.anchor(
            buttonFrameInWindow: rectInWindow, windowFrame: window.frame)
        MenuBarPanelController.shared.show(
            anchor: anchor, actions: makePanelActions(), initialTab: initialTab)
        button.highlight(true)
    }

    private func toggleMenuBarPanel() {
        guard let button = statusItem.button, let window = button.window else { return }
        if MenuBarPanelController.shared.closedRecently {
            button.highlight(false)
            return
        }
        let rectInWindow = button.convert(button.bounds, to: nil)
        let anchor = MenuBarPanelGeometry.anchor(
            buttonFrameInWindow: rectInWindow, windowFrame: window.frame)
        MenuBarPanelController.shared.toggle(
            anchor: anchor, actions: makePanelActions())
        button.highlight(MenuBarPanelController.shared.isVisible)
    }

    private func showLegacyMenu() {
        MenuBarPanelController.shared.close()
        if legacyMenu == nil || legacyMenuNeedsRebuild {
            rebuildMenu()
        }
        guard let menu = legacyMenu, let button = statusItem.button,
            let window = button.window
        else { return }
        let rectInWindow = button.convert(button.bounds, to: nil)
        let anchor = MenuBarPanelGeometry.anchor(
            buttonFrameInWindow: rectInWindow, windowFrame: window.frame)

        statusItem.menu = menu
        button.highlight(true)
        // No view: the location is in screen coordinates. The menu's top edge
        // lands on the bottom edge of the status item, so it drops downward.
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: anchor.minX, y: anchor.minY),
            in: nil)
        statusItem.menu = nil
        button.highlight(false)
    }

    /// Closes the panel before another surface takes focus.
    private func dismissPanel(then action: @escaping () -> Void) {
        MenuBarPanelController.shared.close()
        DispatchQueue.main.async(execute: action)
    }

    private func makePanelActions() -> MenuBarPanelActions {
        MenuBarPanelActions(
            openMirrorControls: { [weak self] in
                self?.dismissPanel { self?.openMirrorControls() }
            },
            openStorageAnalytics: { [weak self] in
                self?.dismissPanel { self?.openStorageAnalytics() }
            },
            openFinderMirror: { [weak self] in
                self?.dismissPanel { self?.openFinderMirrorFromPanel() }
            },
            copyClipboardToAndroid: { [weak self] in
                self?.copyClipboardToAndroidFromPanel()
                    ?? "Connect a phone before copying."
            },
            closePanel: {
                MenuBarPanelController.shared.close()
            })
    }

    private func copyClipboardToAndroidFromPanel() -> String {
        guard let deviceID = primaryDeviceID else {
            return "Connect a phone before copying."
        }
        guard
            let text = NSPasteboard.general.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return "Copy some text on the Mac first."
        }
        guard CopyToAndroidService.shared.copy(text, deviceID: deviceID) else {
            return "Couldn't copy to Android. Check the phone connection."
        }
        let name = viewModel.devices.first(where: { $0.id == deviceID })?.name ?? "the phone"
        return "Copied the Mac clipboard to \(name)."
    }

    private func openFinderMirrorFromPanel() {
        guard let deviceID = primaryDeviceID else {
            AlertPresenter.showWarning(
                message: "Connect an Android device to open its Finder mirror.")
            return
        }
        FinderMirrorService.shared.refresh(deviceID: deviceID, scope: .userFiles) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let location):
                    NSWorkspace.shared.activateFileViewerSelecting([location.fileURL])
                case .failure(let error):
                    AlertPresenter.showWarning(
                        message:
                            "Couldn't open the Finder mirror: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func openDashboardPanel() {
        PanelRouter.openDashboard()
    }

    private func addUtilityMenuItems(to menu: NSMenu) {
        let dashboard = NSMenuItem(
            title: "Device Dashboard",
            action: #selector(openDashboard),
            keyEquivalent: "d")
        dashboard.target = self
        dashboard.image = NSImage(
            systemSymbolName: "iphone.gen3", accessibilityDescription: "Device Dashboard")
        dashboard.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(dashboard)

        let storage = NSMenuItem(
            title: "Storage Analytics",
            action: #selector(openStorageAnalytics),
            keyEquivalent: "")
        storage.target = self
        storage.image = NSImage(
            systemSymbolName: "chart.pie.fill", accessibilityDescription: "Storage Analytics")
        storage.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(storage)

        let controls = NSMenuItem(
            title: "Mirror Controls",
            action: #selector(openMirrorControls),
            keyEquivalent: "")
        controls.target = self
        controls.image = NSImage(
            systemSymbolName: "slider.horizontal.3",
            accessibilityDescription: "Mirror Controls")
        controls.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(controls)
    }

    private var primaryDeviceID: String? {
        viewModel.devices.first(where: \.isConnected)?.id ?? viewModel.devices.first?.id
    }

    @objc private func openDashboard() {
        PanelRouter.openDashboard()
    }

    @objc private func openStorageAnalytics() {
        guard primaryDeviceID != nil else {
            AlertPresenter.showWarning(
                message: "Connect an Android device to inspect its storage.")
            return
        }
        PanelRouter.openStorageAnalytics()
    }

    @objc private func openMirrorControls() {
        guard let id = primaryDeviceID else {
            AlertPresenter.showWarning(
                message: "Connect an Android device to configure a mirror.")
            return
        }
        MirrorControlsController.shared.show(deviceID: id)
    }

    @objc private func showUSBConnectionHelp() {
        let alert = NSAlert()
        alert.messageText = "Connect and authorize your Android device"
        alert.informativeText = "1. Enable Developer options and USB debugging on Android.\n2. Connect a data-capable USB cable and keep the device unlocked.\n3. On Android, approve “Allow USB debugging?” for this Mac. Only choose “Always allow” if you trust this Mac.\n4. Choose Refresh Devices in AndroLaunch.\n\nSuccess: your device appears by name. Open its menu and choose Mirror Screen or Browse Files.\n\nNo authorization prompt? Check the cable and USB connection mode. In Android Developer options, revoke USB debugging authorizations, reconnect, and approve again. This revokes trust for previously authorized computers.\n\nADB must be installed. scrcpy is also required for screen mirroring and clipboard sharing. Wireless pairing is available for Android 11 and later."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        if let id = menu.identifier?.rawValue, id.starts(with: "QuickActions-") {
            let deviceID = String(id.dropFirst("QuickActions-".count))
            viewModel.fetchQuickActionsState(for: deviceID)
            return
        }
        guard menu == statusItem.menu else { return }

        // Sections may still insert rows here: the menu is populated but not tracked.
        sections.forEach { $0.menuWillOpen() }
        clearRowHoverEffects()
        MenuTrackingState.isOpen = true
        // Trigger refresh when main menu opens
        viewModel.refresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu == statusItem.menu else { return }
        MenuTrackingState.isOpen = false
        statusItem.button?.highlight(false)
        guard needsMenuRebuild else { return }
        needsMenuRebuild = false
        // Let AppKit finish tearing the menu down before rebuilding the cached menu.
        DispatchQueue.main.async { [weak self] in
            self?.rebuildMenu()
        }
    }

    /// A row's custom hover overlay can survive a close that skipped `mouseExited`.
    private func clearRowHoverEffects() {
        for item in statusItem.menu?.items ?? [] {
            (item.view as? DeviceMenuItemView)?.resetHover()
        }
    }
}

extension StatusMenuController: NSMenuDelegate {
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard let deviceID = item?.representedObject as? String,
            !deviceID.hasPrefix("previous_"),
            viewModel.devices.contains(where: { $0.id == deviceID })
        else { return }
        guard deviceID != currentDeviceID else { return }
        currentDeviceID = deviceID
        viewModel.fetchApps(for: deviceID)
        self.updateDeviceSubmenu(for: deviceID, isLoadingOverride: true)
    }
}
