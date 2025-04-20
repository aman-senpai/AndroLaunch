//
//  StatusMenuController.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import AppKit
import Combine

final class StatusMenuController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let viewModel: MenuViewModel
    private var cancellables = Set<AnyCancellable>()
    private var currentDeviceID: String?
    
    init(viewModel: MenuViewModel) {
        self.viewModel = viewModel
        setupMenu()
        bindViewModel()
    }
    
    private func setupMenu() {
        statusItem.button?.title = "AndroLaunch"
        refreshDevices() // Call once during setup
        updateMenu()
    }
    
    private func bindViewModel() {
        viewModel.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenu() }
            .store(in: &cancellables)
        
        viewModel.$apps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenu() }
            .store(in: &cancellables)
        
        viewModel.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenu() }
            .store(in: &cancellables)
        
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenu() }
            .store(in: &cancellables)
    }
    
    private func updateMenu() {
        let menu = NSMenu()
        
        // Header
        let headerItem = NSMenuItem(title: "AndroLaunch", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())
        
        // Refresh Item
        let refreshItem = NSMenuItem(
            title: "Refresh Devices",
            action: #selector(refreshDevices),
            keyEquivalent: "r"
        )
        refreshItem.target = self
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
                let deviceItem = NSMenuItem(
                    title: "\(device.name) (\(device.id))",
                    action: nil,
                    keyEquivalent: ""
                )
                
                let submenu = NSMenu()
                
                // Mirror Action
                let mirrorItem = NSMenuItem(
                    title: "Mirror Device",
                    action: #selector(mirrorDevice),
                    keyEquivalent: ""
                )
                mirrorItem.target = self
                mirrorItem.representedObject = device.id
                submenu.addItem(mirrorItem)
                submenu.addItem(NSMenuItem.separator())
                
                // Apps Section
                if viewModel.isLoading && currentDeviceID == device.id {
                    let loadingItem = NSMenuItem(title: "Loading apps...", action: nil, keyEquivalent: "")
                    loadingItem.isEnabled = false
                    submenu.addItem(loadingItem)
                } else if device.id == currentDeviceID {
                    if viewModel.apps.isEmpty {
                        let noAppsItem = NSMenuItem(
                            title: viewModel.error ?? "No apps found",
                            action: nil,
                            keyEquivalent: ""
                        )
                        noAppsItem.isEnabled = false
                        submenu.addItem(noAppsItem)
                    } else {
                        viewModel.apps.forEach { app in
                            let appItem = NSMenuItem(
                                title: app.id,
                                action: #selector(launchApp),
                                keyEquivalent: ""
                            )
                            appItem.target = self
                            appItem.representedObject = (device.id, app.id)
                            submenu.addItem(appItem)
                        }
                    }
                    submenu.addItem(NSMenuItem.separator())
                    let refreshAppsItem = NSMenuItem(
                        title: "Refresh Apps",
                        action: #selector(refreshApps),
                        keyEquivalent: ""
                    )
                    refreshAppsItem.representedObject = device.id
                    refreshAppsItem.target = self
                    submenu.addItem(refreshAppsItem)
                } else {
                    let loadAppsItem = NSMenuItem(
                        title: "List Apps...",
                        action: #selector(loadApps),
                        keyEquivalent: ""
                    )
                    loadAppsItem.representedObject = device.id
                    loadAppsItem.target = self
                    submenu.addItem(loadAppsItem)
                }
                
                deviceItem.submenu = submenu
                menu.addItem(deviceItem)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Preferences
        let prefsItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)
        
        // Quit
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApp.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    // MARK: - Actions
    @objc private func refreshDevices() {
        viewModel.refresh()
        // Force immediate menu update
        DispatchQueue.main.async {
            self.updateMenu()
        }
    }
    
    @objc private func loadApps(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        currentDeviceID = deviceID
        viewModel.fetchApps(for: deviceID)
    }
    
    @objc private func refreshApps(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.fetchApps(for: deviceID)
    }
    
    @objc private func mirrorDevice(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.mirrorDevice(deviceID: deviceID)
    }
    
    @objc private func launchApp(_ sender: NSMenuItem) {
        guard let (deviceID, packageID) = sender.representedObject as? (String, String) else { return }
        viewModel.launchApp(packageID: packageID, deviceID: deviceID)
    }
    
    @objc private func showPreferences() {
        // As recommended, use the standard mechanism for opening the Settings scene.
        // This aligns with how SwiftUI's SettingsLink operates by sending standard actions.
        if #available(macOS 13, *) {
            // Use the modern selector for Settings (macOS 13+)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            // Use the older selector for Preferences (macOS 12 and earlier)
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        
        // Ensure the application is active and the settings window is brought to front
        NSApp.activate(ignoringOtherApps: true)
        

    }
}
