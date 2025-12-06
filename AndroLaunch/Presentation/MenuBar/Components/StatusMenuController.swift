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
            .sink { [weak self] _ in
            }
            .store(in: &cancellables)
            
        viewModel.$quickActionsStates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAllQuickActionsSubmenus()
            }
            .store(in: &cancellables)
    }
    
    private func updateMenu() {
        // If menu doesn't exist, create it
        guard let menu = statusItem.menu else {
            rebuildMenu()
            return
        }
        
        let deviceItems = menu.items.filter { $0.representedObject is String }
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
    
    private func rebuildMenu() {
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
