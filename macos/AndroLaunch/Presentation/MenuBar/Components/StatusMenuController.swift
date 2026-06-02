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
    
    init(viewModel: MenuViewModel) {
        self.viewModel = viewModel
        super.init()
        setupMenu()
        bindViewModel()
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
        }
        refreshDevices()
        updateMenu()
    }
    
    private func bindViewModel() {
        viewModel.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenu() }
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
        // If menu doesn't exist, create it
        guard let menu = statusItem.menu else {
            rebuildMenu()
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
            if let item = menu.items.first, item.action == nil, item.representedObject == nil {
                 item.title = viewModel.error ?? "No devices found"
            }
        }
    }

    /// Update only the previous device items' connecting state without rebuilding the menu.
    private func updateConnectingState() {
        guard let menu = statusItem.menu else { return }
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
        guard let menu = statusItem.menu else { return }

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
                title: prevDevice.name,
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
            let item = NSMenuItem(
                title: viewModel.error ?? "No devices found",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
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
                    title: prevDevice.name,
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
        
        statusItem.menu = menu
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        if let id = menu.identifier?.rawValue, id.starts(with: "QuickActions-") {
            let deviceID = String(id.dropFirst("QuickActions-".count))
            viewModel.fetchQuickActionsState(for: deviceID)
        } else if menu == statusItem.menu {
            // Trigger refresh when main menu opens
            viewModel.refresh()
        }
    }
}

extension StatusMenuController: NSMenuDelegate {
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        if let deviceID = item?.representedObject as? String {
            if deviceID != currentDeviceID {
                currentDeviceID = deviceID
                viewModel.fetchApps(for: deviceID)
                self.updateDeviceSubmenu(for: deviceID, isLoadingOverride: true)
            }
        }
    }
}
