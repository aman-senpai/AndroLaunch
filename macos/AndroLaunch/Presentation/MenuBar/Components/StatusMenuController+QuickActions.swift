//
//  StatusMenuController+QuickActions.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 11/29/25.
//

import AppKit

extension StatusMenuController {
    
    func configureQuickActionsMenu(_ menu: NSMenu, deviceID: String) {
        menu.removeAllItems()
        
        // Toggles
        guard let state = viewModel.quickActionsStates[deviceID] else {
            let loading = NSMenuItem(title: "Reading device controls…", action: nil, keyEquivalent: "")
            loading.isEnabled = false
            menu.addItem(loading)
            return
        }
        
        func addToggle(title: String, icon: String, isEnabled: Bool, action: @escaping () -> Void) {
            let item = NSMenuItem()
            let view = ToggleMenuItemView(title: title, icon: icon, isOn: isEnabled) { _ in
                action()
            }
            item.view = view
            menu.addItem(item)
        }
        
        addToggle(title: "Wi-Fi", icon: "wifi", isEnabled: state.isWifiEnabled) { [weak self] in self?.viewModel.toggleWifi(for: deviceID) }
        addToggle(title: "Bluetooth", icon: "wave.3.right", isEnabled: state.isBluetoothEnabled) { [weak self] in self?.viewModel.toggleBluetooth(for: deviceID) }
        addToggle(title: "Mobile Data", icon: "antenna.radiowaves.left.and.right", isEnabled: state.isMobileDataEnabled) { [weak self] in self?.viewModel.toggleMobileData(for: deviceID) }
        addToggle(title: "Airplane Mode", icon: "airplane", isEnabled: state.isAirplaneModeEnabled) { [weak self] in self?.viewModel.toggleAirplaneMode(for: deviceID) }
        addToggle(title: "Location", icon: "location.fill", isEnabled: state.isLocationEnabled) { [weak self] in self?.viewModel.toggleLocation(for: deviceID) }
        addToggle(title: "Do Not Disturb", icon: "bell.slash.fill", isEnabled: state.isDoNotDisturbEnabled) { [weak self] in self?.viewModel.toggleDoNotDisturb(for: deviceID) }
        addToggle(title: "Auto Rotate", icon: "arrow.triangle.2.circlepath", isEnabled: state.isAutoRotateEnabled) { [weak self] in self?.viewModel.toggleAutoRotate(for: deviceID) }
        addToggle(title: "Auto Brightness", icon: "sun.max.fill", isEnabled: state.isAdaptiveBrightnessEnabled) { [weak self] in self?.viewModel.toggleAdaptiveBrightness(for: deviceID) }
        addToggle(title: "Dark Mode", icon: "moon.fill", isEnabled: state.isDarkModeEnabled) { [weak self] in self?.viewModel.toggleDarkMode(for: deviceID) }
    }

    func configureRestartMenu(_ menu: NSMenu, deviceID: String) {
        let modes: [(String, Selector, String)] = [
            ("Restart Android…", #selector(rebootDevice(_:)), "power"),
            ("Restart in Bootloader…", #selector(rebootBootloader(_:)), "laptopcomputer"),
            ("Restart in Recovery…", #selector(rebootRecovery(_:)), "wrench.and.screwdriver")
        ]
        for (title, action, symbol) in modes {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = deviceID
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            menu.addItem(item)
        }
    }
    
    func updateAllQuickActionsSubmenus() {
        guard let menu = statusItem.menu else { return }
        for item in menu.items {
            if let deviceID = item.representedObject as? String,
               let deviceSubmenu = item.submenu {
                
                // Update Quick Actions
                if let quickActionsItem = deviceSubmenu.items.first(where: { $0.title == "Quick Actions" }),
                   let quickActionsMenu = quickActionsItem.submenu {
                    configureQuickActionsMenu(quickActionsMenu, deviceID: deviceID)
                }
                
                // Update Config Menu
                if let configItem = deviceSubmenu.items.first(where: { $0.title == "Configuration" }),
                   let configMenu = configItem.submenu {
                    configureConfigMenu(configMenu, deviceID: deviceID)
                }
            }
        }
    }
    
    // MARK: - Quick Actions Handlers
    
    @objc func rebootDevice(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        confirmReboot(deviceID: deviceID, mode: .normal)
    }
    
    @objc func rebootBootloader(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        confirmReboot(deviceID: deviceID, mode: .bootloader)
    }
    
    @objc func rebootRecovery(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        confirmReboot(deviceID: deviceID, mode: .recovery)
    }
    
    private func confirmReboot(deviceID: String, mode: RebootMode) {
        let alert = NSAlert()
        let deviceName = viewModel.devices.first(where: { $0.id == deviceID })?.name ?? "Android device"
        alert.messageText = "Restart \(deviceName)?"
        let modeString = mode == .normal ? "Android" : mode.rawValue.capitalized
        alert.informativeText = "Target: \(deviceName)\nDevice ID: \(deviceID)\n\nThis will stop active apps, mirroring, and transfers on this device and restart it into \(modeString). Unsaved work may be lost."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Restart")
        alert.buttons[1].hasDestructiveAction = true
        alert.alertStyle = .warning
        
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            viewModel.reboot(deviceID: deviceID, mode: mode)
        }
    }
    
    @objc func toggleWifi(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleWifi(for: deviceID)
    }
    
    @objc func toggleBluetooth(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleBluetooth(for: deviceID)
    }
    
    @objc func toggleMobileData(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleMobileData(for: deviceID)
    }
    
    @objc func toggleAirplaneMode(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleAirplaneMode(for: deviceID)
    }
    
    @objc func toggleLocation(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleLocation(for: deviceID)
    }
    
    @objc func toggleDoNotDisturb(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleDoNotDisturb(for: deviceID)
    }
    
    @objc func toggleAutoRotate(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleAutoRotate(for: deviceID)
    }
    
    @objc func toggleAdaptiveBrightness(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleAdaptiveBrightness(for: deviceID)
    }
    
    @objc func toggleDarkMode(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleDarkMode(for: deviceID)
    }
}
