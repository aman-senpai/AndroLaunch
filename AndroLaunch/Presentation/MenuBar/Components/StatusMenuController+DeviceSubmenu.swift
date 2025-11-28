//
//  StatusMenuController+DeviceSubmenu.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 11/29/25.
//

import AppKit

extension StatusMenuController {
    
    func updateDeviceSubmenu(for deviceID: String, isLoadingOverride: Bool = false) {
        guard let menu = statusItem.menu else { return }
        
        // Find the item for this device
        // We stored deviceID in representedObject
        guard let deviceItem = menu.items.first(where: { ($0.representedObject as? String) == deviceID }) else { return }
        
        // Get or create submenu
        let submenu = deviceItem.submenu ?? NSMenu()
        if deviceItem.submenu == nil {
            deviceItem.submenu = submenu
        }
        
        // Clear and rebuild
        submenu.removeAllItems()
        
        // We need the device object. Find it in viewModel
        if let device = viewModel.devices.first(where: { $0.id == deviceID }) {
            configureDeviceSubmenu(submenu, for: device, isLoadingOverride: isLoadingOverride)
        }
    }
    
    func configureDeviceSubmenu(_ submenu: NSMenu, for device: AndroidDevice, isLoadingOverride: Bool = false) {
        // Clear existing items to prevent duplicates during refresh
        submenu.removeAllItems()
        
        // Device Info Section
        let truncatedID = truncateDeviceID(device.id)
        let deviceInfoItem = NSMenuItem(
            title: "ID: \(truncatedID)",
            action: nil,
            keyEquivalent: ""
        )
        deviceInfoItem.isEnabled = false
        submenu.addItem(deviceInfoItem)
        
        // Show model if available and different from name
        if let model = device.model, model != device.name {
            let modelInfoItem = NSMenuItem(
                title: "Model: \(model)",
                action: nil,
                keyEquivalent: ""
            )
            modelInfoItem.isEnabled = false
            submenu.addItem(modelInfoItem)
        }
        
        // Show Device Info (Version + Battery)
        let infoString = NSMutableAttributedString()
        
        if let version = device.androidVersion, let apiLevel = device.apiLevel {
            infoString.append(NSAttributedString(string: "\(version) (API \(apiLevel))"))
        }
        
        if let batteryLevel = device.batteryLevel {
            if infoString.length > 0 {
                infoString.append(NSAttributedString(string: "  |  "))
            }
            
            // Determine icon name
            let iconName: String
            if let isCharging = device.isCharging, isCharging {
                iconName = "battery.100.bolt"
            } else {
                switch batteryLevel {
                case 0...15: iconName = "battery.0"
                case 16...35: iconName = "battery.25"
                case 36...60: iconName = "battery.50"
                case 61...85: iconName = "battery.75"
                default: iconName = "battery.100"
                }
            }
            
            // Create attachment
            let attachment = NSTextAttachment()
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                attachment.image = image
                // Adjust bounds for vertical alignment if needed, but default is usually okay-ish.
                // Often needs a slight offset.
                attachment.bounds = CGRect(x: 0, y: -2, width: image.size.width, height: image.size.height)
            }
            infoString.append(NSAttributedString(attachment: attachment))
            
            infoString.append(NSAttributedString(string: " \(batteryLevel)%"))
        }
        
        if infoString.length > 0 {
            let infoItem = NSMenuItem()
            infoItem.attributedTitle = infoString
            infoItem.isEnabled = false
            infoItem.image = NSImage(systemSymbolName: "info.circle.fill", accessibilityDescription: "Device Info")
            infoItem.image?.size = NSSize(width: 16, height: 16)
            submenu.addItem(infoItem)
        }
        
        submenu.addItem(NSMenuItem.separator())
        
        // Controls Section (Audio, Camera, Mirror, Disconnect)
        let controlsItem = NSMenuItem()
        
        // Determine if device is wireless for disconnect button
        let isWireless = device.id.contains(":") ||
                        device.id.contains("_tcp") ||
                        device.id.contains("_udp")
        
        let controlsView = ControlsMenuItemView(
            deviceID: device.id,
            isWireless: isWireless,
            target: self,
            frontCamAction: #selector(launchFrontCamera(_:)),
            backCamAction: #selector(launchBackCamera(_:)),
            mirrorAction: #selector(mirrorDevice(_:)),
            installAction: #selector(installAPK(_:)),
            shellAction: #selector(launchShell(_:)),
            disconnectAction: #selector(disconnectDevice(_:))
        )
        controlsItem.view = controlsView
        submenu.addItem(controlsItem)
        
        submenu.addItem(NSMenuItem.separator())
        
        // Quick Actions
        let quickActionsItem = NSMenuItem(title: "Quick Actions", action: nil, keyEquivalent: "")
        quickActionsItem.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Quick Actions")
        quickActionsItem.image?.size = NSSize(width: 16, height: 16)
        
        let quickActionsMenu = NSMenu()
        quickActionsMenu.delegate = self
        quickActionsMenu.identifier = NSUserInterfaceItemIdentifier("QuickActions-\(device.id)")
        
        configureQuickActionsMenu(quickActionsMenu, deviceID: device.id)
        
        quickActionsItem.submenu = quickActionsMenu
        submenu.addItem(quickActionsItem)

        submenu.addItem(NSMenuItem.separator())
        
        // Configuration Section
        let configItem = NSMenuItem(title: "Configuration", action: nil, keyEquivalent: "")
        configItem.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Configuration")
        configItem.image?.size = NSSize(width: 16, height: 16)
        
        let configMenu = NSMenu()
        configureConfigMenu(configMenu, deviceID: device.id)
        configItem.submenu = configMenu
        submenu.addItem(configItem)
        
        submenu.addItem(NSMenuItem.separator())
        
        // Apps Section - check if apps exist for this specific device
        let deviceApps = viewModel.deviceApps[device.id] ?? []
        
        // Only show loading if we don't have apps yet OR if we are explicitly loading apps
        // We use isLoadingApps from ViewModel which tracks the specific app fetch operation
        let shouldShowLoading = (viewModel.isLoadingApps || isLoadingOverride) && device.id == currentDeviceID
        
        if shouldShowLoading {
            let loadingItem = NSMenuItem(title: "Loading apps...", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            submenu.addItem(loadingItem)
        } else if !deviceApps.isEmpty {
            // Search Field
            let searchItem = NSMenuItem()
            let searchView = SearchMenuItemView(deviceID: device.id, delegate: self)
            searchItem.view = searchView
            submenu.addItem(searchItem)
            
            submenu.addItem(NSMenuItem.separator())
            
            // App Items
            for app in deviceApps {
                let appItem = createAppMenuItem(app: app, deviceID: device.id)
                submenu.addItem(appItem)
            }
            
            submenu.addItem(NSMenuItem.separator())
        } else if device.id == currentDeviceID {
            let statusItem = NSMenuItem(
                title: viewModel.error ?? "No apps found",
                action: nil,
                keyEquivalent: ""
            )
            statusItem.isEnabled = false
            submenu.addItem(statusItem)
        }
        
        // Refresh Apps
        let refreshAppsItem = NSMenuItem()
        let refreshView = RefreshAppsMenuItemView(
            deviceID: device.id,
            target: self,
            action: #selector(refreshApps(_:))
        )
        refreshAppsItem.view = refreshView
        submenu.addItem(refreshAppsItem)
    }
    
    private func truncateDeviceID(_ deviceID: String, maxLength: Int = 30) -> String {
        guard deviceID.count > maxLength else { return deviceID }
        let prefixLength = maxLength / 2 - 2
        let suffixLength = maxLength / 2 - 2
        let prefix = deviceID.prefix(prefixLength)
        let suffix = deviceID.suffix(suffixLength)
        return "\(prefix)...\(suffix)"
    }
}
