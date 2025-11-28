//
//  StatusMenuController.swift
//  AndroLaunch
//

import AppKit
import Combine
import SwiftUI

final class StatusMenuController: NSObject, NSSearchFieldDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let viewModel: MenuViewModel
    private var cancellables = Set<AnyCancellable>()
    private var currentDeviceID: String?
    private var pairingWindow: NSWindow?
    
    // MARK: - Search Field Subclass
    private class DeviceSearchField: NSSearchField {
        var deviceID: String?
    }

    init(viewModel: MenuViewModel) {
        self.viewModel = viewModel
        super.init()
        setupMenu()
        bindViewModel()
    }
    
    private func setupMenu() {
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            button.image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "AndroLaunch")?.withSymbolConfiguration(config)
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
                // We don't want to rebuild the whole menu for a simple toggle if we can avoid it.
                // But since objectWillChange is generic, we might need to check what changed or just rely on the fact that
                // we are manually updating the UI in the action methods.
                // However, if the change comes from elsewhere, we might want to refresh.
                // For now, let's rely on manual UI updates for responsiveness and full refresh for data changes.
            }
            .store(in: &cancellables)
            
        viewModel.$quickActionsStates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAllQuickActionsSubmenus()
            }
            .store(in: &cancellables)
    }
    
    private func updateDeviceSubmenu(for deviceID: String, isLoadingOverride: Bool = false) {
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
        
        // Important: If the menu is currently open, we might need to force a layout update
        // But usually modifying the submenu items is enough for AppKit to reflect changes
    }
    
    private func updateMenu() {
        // If menu doesn't exist, create it
        guard let menu = statusItem.menu else {
            rebuildMenu()
            return
        }
        
        // Check if we need to rebuild (e.g. device count changed)
        // For simplicity, if the number of device items doesn't match, we rebuild.
        // We can be smarter, but this covers the main case of "refreshing details".
        
        // Count device items (excluding static items)
        // Static items: Refresh (2), Separator (1), Pair (2), About (2), Quit (1) -> Total ~8 items + devices
        // This is fragile. Better to check representedObjects.
        
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
            
            // Update Title / View if needed
            // The view is DeviceMenuItemView. We might need to update it.
            // Update Title / View if needed
            // The view is DeviceMenuItemView. We might need to update it.
            // if let itemView = item.view as? DeviceMenuItemView {
                // Update connection status or name if changed
                // For now, we assume name doesn't change often, but we can update it.
                // itemView.update(...) // If we had an update method.
                // Recreating the view is cheap enough if we don't lose state.
            // }
            
            // Update Submenu (Battery, Version, etc.)
            if let submenu = item.submenu {
                configureDeviceSubmenu(submenu, for: device)
            }
        }
        
        // Update Error Item if needed
        if viewModel.devices.isEmpty {
            // If empty, we should have rebuilt above because IDs wouldn't match (0 vs N)
            // But if we went from 0 to 0, we might need to update error text.
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
    
    private func truncateDeviceID(_ deviceID: String, maxLength: Int = 30) -> String {
        guard deviceID.count > maxLength else { return deviceID }
        let prefixLength = maxLength / 2 - 2
        let suffixLength = maxLength / 2 - 2
        let prefix = deviceID.prefix(prefixLength)
        let suffix = deviceID.suffix(suffixLength)
        return "\(prefix)...\(suffix)"
    }
    
    private func configureDeviceSubmenu(_ submenu: NSMenu, for device: AndroidDevice, isLoadingOverride: Bool = false) {
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
        let isAudioEnabled = viewModel.isAudioEnabled(for: device.id)
        
        // Determine if device is wireless for disconnect button
        let isWireless = device.id.contains(":") || 
                        device.id.contains("_tcp") || 
                        device.id.contains("_udp")
        
        let isClipboardEnabled = viewModel.isClipboardEnabled(for: device.id)
        
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
    
    // MARK: - App List Menu Items
    
    private func createAppListView(for apps: [AndroidApp], deviceID: String) -> NSView {
        // This method is no longer used for the main list, but we might need a container for the search field
        // if we want it to look a specific way.
        // However, we are moving to direct menu items.
        return NSView()
    }
    
    // Custom View for Search Field in Menu
    private class SearchMenuItemView: NSView {
        let searchField: DeviceSearchField
        
        init(deviceID: String, delegate: NSSearchFieldDelegate) {
            searchField = DeviceSearchField(frame: .zero)
            super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 30))
            
            searchField.deviceID = deviceID
            searchField.delegate = delegate
            searchField.placeholderString = "Search apps..."
            searchField.focusRingType = .none
            searchField.bezelStyle = .roundedBezel
            searchField.font = NSFont.systemFont(ofSize: 13)
            searchField.translatesAutoresizingMaskIntoConstraints = false
            
            addSubview(searchField)
            
            NSLayoutConstraint.activate([
                searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
                searchField.heightAnchor.constraint(equalToConstant: 22)
            ])
        }
        
        required init?(coder: NSCoder) { fatalError() }
    }
    
    // MARK: - NSSearchFieldDelegate
    func controlTextDidChange(_ obj: Notification) {
        guard let searchField = obj.object as? DeviceSearchField,
              let deviceID = searchField.deviceID else { return }
        
        let searchText = searchField.stringValue.lowercased()
        updateAppMenuItems(for: deviceID, filter: searchText)
    }
    
    private func updateAppMenuItems(for deviceID: String, filter: String) {
        guard let menu = statusItem.menu,
              let deviceItem = menu.items.first(where: { ($0.representedObject as? String) == deviceID }),
              let submenu = deviceItem.submenu else { return }
        
        // 1. Find the start of the app list
        // We can identify it by looking for the separator after the resolution item, or the search item.
        // Let's rely on tags or known structure.
        // Structure: ... -> Resolution -> Separator -> Search -> Apps -> Separator -> Refresh
        
        // Let's tag the Search Item to find it easily.
        // Or just iterate.
        
        var startIndex = -1
        for (index, item) in submenu.items.enumerated() {
            if item.view is SearchMenuItemView {
                startIndex = index + 1
                break
            }
        }
        
        guard startIndex != -1 else { return }
        
        // 2. Remove existing app items until we hit the separator before "Refresh Apps"
        // "Refresh Apps" is the last item.
        // So we remove from startIndex until (count - 1)
        
        let endIndex = submenu.items.count - 1 // The last item is Refresh Apps
        
        if startIndex < endIndex {
            // Remove items in range
            // Note: removing items shifts indices, so we remove from startIndex repeatedly
            let countToRemove = endIndex - startIndex
            for _ in 0..<countToRemove {
                submenu.removeItem(at: startIndex)
            }
        }
        
        // 3. Add filtered apps
        let apps = viewModel.deviceApps[deviceID] ?? []
        let filteredApps: [AndroidApp]
        if filter.isEmpty {
            filteredApps = apps
        } else {
            let searchTerms = filter.lowercased().split(separator: " ")
            filteredApps = apps.filter { app in
                let appName = app.name.lowercased()
                let appId = app.id.lowercased()
                return searchTerms.allSatisfy { term in
                    appName.contains(term) || appId.contains(term)
                }
            }
        }
        
        // Insert items at startIndex
        for (offset, app) in filteredApps.enumerated() {
            let appItem = createAppMenuItem(app: app, deviceID: deviceID)
            submenu.insertItem(appItem, at: startIndex + offset)
        }
    }
    
    private func createAppMenuItem(app: AndroidApp, deviceID: String) -> NSMenuItem {
        let item = NSMenuItem(title: app.name, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: AppIconMapper.getIconName(for: app), accessibilityDescription: nil)
        item.image?.size = NSSize(width: 16, height: 16)
        
        let submenu = NSMenu()
        
        // Launch
        let launchItem = NSMenuItem(title: "Launch", action: #selector(launchAppAction(_:)), keyEquivalent: "")
        launchItem.target = self
        launchItem.representedObject = AppActionData(app: app, deviceID: deviceID)
        launchItem.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Launch")
        submenu.addItem(launchItem)
        
        submenu.addItem(NSMenuItem.separator())
        
        // Clear Data
        let clearDataItem = NSMenuItem(title: "Clear Data", action: #selector(clearDataAction(_:)), keyEquivalent: "")
        clearDataItem.target = self
        clearDataItem.representedObject = AppActionData(app: app, deviceID: deviceID)
        clearDataItem.image = NSImage(systemSymbolName: "trash.slash", accessibilityDescription: "Clear Data")
        submenu.addItem(clearDataItem)
        
        // Uninstall
        let uninstallItem = NSMenuItem(title: "Uninstall", action: #selector(uninstallAction(_:)), keyEquivalent: "")
        uninstallItem.target = self
        uninstallItem.representedObject = AppActionData(app: app, deviceID: deviceID)
        uninstallItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Uninstall")
        submenu.addItem(uninstallItem)
        
        item.submenu = submenu
        return item
    }
    
    // Helper struct for actions
    private struct AppActionData {
        let app: AndroidApp
        let deviceID: String
    }
    
    @objc private func launchAppAction(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? AppActionData else { return }
        launchApp(deviceID: data.deviceID, appID: data.app.id, appName: data.app.name)
    }
    
    @objc private func clearDataAction(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? AppActionData else { return }
        clearAppData(deviceID: data.deviceID, app: data.app)
    }
    
    @objc private func uninstallAction(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? AppActionData else { return }
        uninstallApp(deviceID: data.deviceID, app: data.app)
    }
    
    private func launchApp(deviceID: String, appID: String, appName: String) {
        viewModel.launchApp(packageID: appID, deviceID: deviceID, appName: appName)
        NSApp.stopModal()
    }
    
    // MARK: - Actions
    @objc private func refreshDevices() {
        viewModel.refresh()
        currentDeviceID = nil
    }
    
    @objc private func refreshApps(_ sender: NSButton) {
        // Use custom button class or check sender
        if let refreshButton = sender as? DeviceActionButton, let deviceID = refreshButton.deviceID {
             currentDeviceID = deviceID
             viewModel.forceRefreshApps(for: deviceID)
             // Do NOT cancel tracking to keep menu open
        }
    }
    
    @objc private func mirrorDevice(_ sender: NSButton) {
        if let deviceButton = sender as? DeviceActionButton, let deviceID = deviceButton.deviceID {
             viewModel.mirrorDevice(deviceID: deviceID)
             if let menu = statusItem.menu { menu.cancelTracking() }
        }
    }
    
    @objc private func disconnectDevice(_ sender: NSButton) {
        if let deviceButton = sender as? DeviceActionButton, let deviceID = deviceButton.deviceID {
            viewModel.disconnectDevice(deviceID: deviceID)
            if let menu = statusItem.menu { menu.cancelTracking() }
        }
    }
    
    @objc private func installAPK(_ sender: NSButton) {
        if let deviceButton = sender as? DeviceActionButton, let deviceID = deviceButton.deviceID {
            let openPanel = NSOpenPanel()
            openPanel.title = "Select APK to Install"
            openPanel.showsHiddenFiles = false
            openPanel.canChooseDirectories = false
            openPanel.canCreateDirectories = false
            openPanel.allowsMultipleSelection = false
            openPanel.allowedContentTypes = [.init(filenameExtension: "apk")!]
            
            // Bring open panel to front
            NSApp.activate(ignoringOtherApps: true)
            
            openPanel.begin { [weak self] (result) in
                if result == .OK {
                    if let url = openPanel.url {
                        self?.viewModel.installAPK(deviceID: deviceID, apkPath: url.path)
                        // Close menu after selection
                        if let menu = self?.statusItem.menu { menu.cancelTracking() }
                    }
                }
            }
        }
    }
    
    @objc private func launchShell(_ sender: NSButton) {
        if let deviceButton = sender as? DeviceActionButton, let deviceID = deviceButton.deviceID {
            // Use AppleScript to open Terminal and run adb shell
            // We need to find the adb path first.
            // Since ADBService is internal, we might not have direct access to the path string easily 
            // without exposing it or asking ViewModel.
            // However, we can assume 'adb' is in the path if we are running, or we can try to use the one from service.
            
            // Better approach: Ask ViewModel to get the ADB path or just assume it's in a standard location / user's path.
            // But to be robust, let's try to construct a command that sources zshrc or similar, 
            // OR better, use the absolute path if we can get it.
            
            // Let's get the ADB path from the ViewModel if possible, or just use "adb" and hope it's in the path 
            // that Terminal uses (which it usually is if installed via brew).
            
            // For now, let's try just "adb". If that fails, we might need to be more specific.
            // Actually, ADBService has `adbPath`. Let's expose it in ViewModel or just access it if we can.
            // ViewModel doesn't expose it currently.
            
            // Let's use a simple AppleScript that tries to run it.
            
            // We need to ensure adb is in the path.
            // A common issue is that the environment variables aren't loaded in the `do script` context the same way.
            // We can try to export the path or source the profile.
            
            print("DEBUG: Launching shell for device: \(deviceID)")
            
            // Create a temporary .command file to launch the shell
            let fileManager = FileManager.default
            let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            
            do {
                try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
                let fileName = "ADB Shell.command"
                let fileURL = tempDir.appendingPathComponent(fileName)
                
                // Determine ADB directory
                var adbDir = "$HOME/Library/Android/sdk/platform-tools" // Default fallback
                if let adbPath = self.viewModel.adbPath {
                    let url = URL(fileURLWithPath: adbPath)
                    adbDir = url.deletingLastPathComponent().path
                }
                
                let scriptContent = """
                #!/bin/bash
                clear
                # Set window title
                echo -n -e "\\033]0;ADB Shell - \(deviceID)\\007"
                
                echo "Starting ADB Shell for device: \(deviceID)"
                export PATH=$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(adbDir)
                
                # Check if adb is available
                if ! command -v adb &> /dev/null; then
                    echo "Error: adb not found in PATH."
                    echo "PATH is: $PATH"
                    read -n 1 -s -r -p "Press any key to close..."
                    exit 1
                fi
                
                adb -s \(deviceID) shell
                
                # Keep window open if shell exits unexpectedly
                if [ $? -ne 0 ]; then
                    echo "ADB shell exited with error."
                    read -n 1 -s -r -p "Press any key to close..."
                fi
                """
                
                try scriptContent.write(to: fileURL, atomically: true, encoding: .utf8)
                
                // Make executable
                let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
                try fileManager.setAttributes(attributes, ofItemAtPath: fileURL.path)
                
                // Open with Terminal
                NSWorkspace.shared.open(fileURL)
                print("DEBUG: Opened command file at \(fileURL.path)")
            } catch {
                print("ERROR: Failed to create or open command file: \(error)")
            }
            
            if let menu = statusItem.menu { menu.cancelTracking() }
        }
    }
    
    @objc private func toggleAudio(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleAudio(for: deviceID)
        // Update menu item state
        sender.state = viewModel.isAudioEnabled(for: deviceID) ? .on : .off
    }
    
    @objc private func toggleClipboard(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleClipboard(for: deviceID)
        // Update menu item state
        sender.state = viewModel.isClipboardEnabled(for: deviceID) ? .on : .off
    }
    
    @objc private func launchFrontCamera(_ sender: NSButton) {
        if let deviceButton = sender as? DeviceActionButton, let deviceID = deviceButton.deviceID {
            viewModel.launchCamera(deviceID: deviceID, facing: .front)
            if let menu = statusItem.menu { menu.cancelTracking() }
        }
    }
    
    @objc private func launchBackCamera(_ sender: NSButton) {
        if let deviceButton = sender as? DeviceActionButton, let deviceID = deviceButton.deviceID {
            viewModel.launchCamera(deviceID: deviceID, facing: .back)
            if let menu = statusItem.menu { menu.cancelTracking() }
        }
    }
    
    @objc private func changeResolution(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        let resolution = sender.tag
        viewModel.setResolution(for: deviceID, resolution: resolution)
        
        // Update checkmarks
        if let menu = sender.menu {
            for item in menu.items {
                item.state = (item.tag == resolution) ? .on : .off
            }
        }
    }

    
    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/aman-senpai/AndroLaunch") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func pairDeviceWirelessly() {
        if pairingWindow == nil {
            let pairingView = PairingView()
            let hostingController = NSHostingController(rootView: pairingView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Pair Device"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.center()
            window.isReleasedWhenClosed = false
            
            self.pairingWindow = window
        }
        
        pairingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    

    
    func uninstallApp(deviceID: String, app: AndroidApp) {
        let alert = NSAlert()
        alert.messageText = "Uninstall \(app.name)?"
        alert.informativeText = "Are you sure you want to uninstall this app? This action cannot be undone."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        // Bring alert to front
        NSApp.activate(ignoringOtherApps: true)
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            viewModel.uninstallApp(deviceID: deviceID, packageID: app.id)
        }
    }

    func clearAppData(deviceID: String, app: AndroidApp) {
        let alert = NSAlert()
        alert.messageText = "Clear Data for \(app.name)?"
        alert.informativeText = "Are you sure you want to clear all data for this app? This includes accounts, settings, and files. This action cannot be undone."
        alert.addButton(withTitle: "Clear Data")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        // Bring alert to front
        NSApp.activate(ignoringOtherApps: true)
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            viewModel.repository.clearAppData(deviceID: deviceID, packageID: app.id)
        }
    }
    
    // MARK: - Quick Actions Helper
    
    private func configureQuickActionsMenu(_ menu: NSMenu, deviceID: String) {
        menu.removeAllItems()
        
        // Reboot Options
        let rebootItem = NSMenuItem(title: "Reboot", action: #selector(rebootDevice(_:)), keyEquivalent: "")
        rebootItem.target = self
        rebootItem.representedObject = deviceID
        rebootItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(rebootItem)
        
        let bootloaderItem = NSMenuItem(title: "Reboot to Bootloader", action: #selector(rebootBootloader(_:)), keyEquivalent: "")
        bootloaderItem.target = self
        bootloaderItem.representedObject = deviceID
        bootloaderItem.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: nil)
        menu.addItem(bootloaderItem)
        
        let recoveryItem = NSMenuItem(title: "Reboot to Recovery", action: #selector(rebootRecovery(_:)), keyEquivalent: "")
        recoveryItem.target = self
        recoveryItem.representedObject = deviceID
        recoveryItem.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: nil)
        menu.addItem(recoveryItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Toggles
        let state = viewModel.quickActionsStates[deviceID]
        
        func addToggle(title: String, icon: String, isEnabled: Bool, action: @escaping () -> Void) {
            let item = NSMenuItem()
            let view = ToggleMenuItemView(title: title, icon: icon, isOn: isEnabled) { _ in
                action()
            }
            item.view = view
            menu.addItem(item)
        }
        
        addToggle(title: "Wi-Fi", icon: "wifi", isEnabled: state?.isWifiEnabled ?? false) { [weak self] in self?.viewModel.toggleWifi(for: deviceID) }
        addToggle(title: "Bluetooth", icon: "wave.3.right", isEnabled: state?.isBluetoothEnabled ?? false) { [weak self] in self?.viewModel.toggleBluetooth(for: deviceID) }
        addToggle(title: "Mobile Data", icon: "antenna.radiowaves.left.and.right", isEnabled: state?.isMobileDataEnabled ?? false) { [weak self] in self?.viewModel.toggleMobileData(for: deviceID) }
        addToggle(title: "Airplane Mode", icon: "airplane", isEnabled: state?.isAirplaneModeEnabled ?? false) { [weak self] in self?.viewModel.toggleAirplaneMode(for: deviceID) }
        addToggle(title: "Location", icon: "location.fill", isEnabled: state?.isLocationEnabled ?? false) { [weak self] in self?.viewModel.toggleLocation(for: deviceID) }
        addToggle(title: "Do Not Disturb", icon: "bell.slash.fill", isEnabled: state?.isDoNotDisturbEnabled ?? false) { [weak self] in self?.viewModel.toggleDoNotDisturb(for: deviceID) }
        addToggle(title: "Auto Rotate", icon: "arrow.triangle.2.circlepath", isEnabled: state?.isAutoRotateEnabled ?? false) { [weak self] in self?.viewModel.toggleAutoRotate(for: deviceID) }
        addToggle(title: "Auto Brightness", icon: "sun.max.fill", isEnabled: state?.isAdaptiveBrightnessEnabled ?? false) { [weak self] in self?.viewModel.toggleAdaptiveBrightness(for: deviceID) }
        addToggle(title: "Dark Mode", icon: "moon.fill", isEnabled: state?.isDarkModeEnabled ?? false) { [weak self] in self?.viewModel.toggleDarkMode(for: deviceID) }
    }
    
    private func configureResolutionMenu(_ menu: NSMenu, deviceID: String) {
        let currentResolution = viewModel.getResolution(for: deviceID)
        let resolutions = [360, 540, 720, 900, 1080, 1440, 1600]
        
        for res in resolutions {
            let item = NSMenuItem(title: "\(res)p", action: #selector(changeResolution(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = deviceID
            item.tag = res
            item.state = (res == currentResolution) ? .on : .off
            item.onStateImage = NSImage(systemSymbolName: "smallcircle.fill.circle", accessibilityDescription: "Selected")
            item.offStateImage = NSImage(systemSymbolName: "circle", accessibilityDescription: "Unselected")
            menu.addItem(item)
        }
    }
    private func configureConfigMenu(_ menu: NSMenu, deviceID: String) {
        menu.removeAllItems()
        
        // Resolution Submenu
        let resItem = NSMenuItem(title: "App Resolution", action: nil, keyEquivalent: "")
        resItem.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Resolution")
        
        let resMenu = NSMenu()
        configureResolutionMenu(resMenu, deviceID: deviceID)
        resItem.submenu = resMenu
        menu.addItem(resItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem.separator())
        
        // Audio Forwarding
        let isAudioEnabled = viewModel.isAudioEnabled(for: deviceID)
        let audioItem = NSMenuItem()
        let audioView = ToggleMenuItemView(
            title: "Audio Forwarding",
            icon: isAudioEnabled ? "speaker.wave.2" : "speaker.slash",
            isOn: isAudioEnabled
        ) { [weak self] isOn in
            self?.viewModel.toggleAudio(for: deviceID)
        }
        audioItem.view = audioView
        menu.addItem(audioItem)
        
        // Clipboard Sync
        let isClipboardEnabled = viewModel.isClipboardEnabled(for: deviceID)
        let clipboardItem = NSMenuItem()
        let clipboardView = ToggleMenuItemView(
            title: "Clipboard Sync",
            icon: "doc.on.clipboard",
            isOn: isClipboardEnabled
        ) { [weak self] isOn in
            self?.viewModel.toggleClipboard(for: deviceID)
        }
        clipboardItem.view = clipboardView
        menu.addItem(clipboardItem)
    }

    private func updateAllQuickActionsSubmenus() {
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
    
    @objc private func rebootDevice(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        confirmReboot(deviceID: deviceID, mode: .normal)
    }
    
    @objc private func rebootBootloader(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        confirmReboot(deviceID: deviceID, mode: .bootloader)
    }
    
    @objc private func rebootRecovery(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        confirmReboot(deviceID: deviceID, mode: .recovery)
    }
    
    private func confirmReboot(deviceID: String, mode: RebootMode) {
        let alert = NSAlert()
        alert.messageText = "Reboot Device?"
        let modeString = mode == .normal ? "System" : mode.rawValue.capitalized
        alert.informativeText = "Are you sure you want to reboot the device into \(modeString) mode?"
        alert.addButton(withTitle: "Reboot")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            viewModel.reboot(deviceID: deviceID, mode: mode)
        }
    }
    
    @objc private func toggleWifi(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleWifi(for: deviceID)
    }
    
    @objc private func toggleBluetooth(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleBluetooth(for: deviceID)
    }
    
    @objc private func toggleMobileData(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleMobileData(for: deviceID)
    }
    
    @objc private func toggleAirplaneMode(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleAirplaneMode(for: deviceID)
    }
    
    @objc private func toggleLocation(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleLocation(for: deviceID)
    }
    
    @objc private func toggleDoNotDisturb(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleDoNotDisturb(for: deviceID)
    }
    
    @objc private func toggleAutoRotate(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleAutoRotate(for: deviceID)
    }
    
    @objc private func toggleAdaptiveBrightness(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleAdaptiveBrightness(for: deviceID)
    }
    
    @objc private func toggleDarkMode(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleDarkMode(for: deviceID)
    }
}

extension StatusMenuController: NSMenuDelegate {
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        if let deviceID = item?.representedObject as? String {
            // Always fetch - the repository will use cache if available
            // This ensures the menu updates even when using cached data
            if deviceID != currentDeviceID {
                currentDeviceID = deviceID
                viewModel.fetchApps(for: deviceID)
                // Update just this device's submenu to show loading state or cached apps immediately
                self.updateDeviceSubmenu(for: deviceID, isLoadingOverride: true)
            }
        }
    }
}

// MARK: - Table View Components with Search Support


// MARK: - Device Menu Item View with Hover Effect
private final class DeviceMenuItemView: NSView {
    private let hoverEffectView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .selection
        view.state = .active
        view.blendingMode = .withinWindow
        view.isEmphasized = true
        view.wantsLayer = true
        view.layer?.cornerRadius = 4.0
        view.layer?.masksToBounds = true
        view.alphaValue = 0
        return view
    }()
    
    private let deviceIconView = NSImageView()
    private let nameLabel = NSTextField()
    private let connectionIconView = NSImageView()
    private var trackingArea: NSTrackingArea?
    
    init(deviceName: String, isWireless: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 20))
        
        // Add hover effect view
        addSubview(hoverEffectView)
        
        // Device icon (left)
        // Standard menu item icon alignment is usually around 14-16pt from the edge
        deviceIconView.frame = NSRect(x: 14, y: 2, width: 16, height: 16)
        deviceIconView.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "Device")
        deviceIconView.contentTintColor = .controlTextColor
        addSubview(deviceIconView)
        
        // Device name (center)
        nameLabel.stringValue = deviceName
        nameLabel.font = NSFont.menuFont(ofSize: 14)
        nameLabel.textColor = .controlTextColor
        nameLabel.frame = NSRect(x: 38, y: 2, width: 172, height: 16)
        nameLabel.drawsBackground = false
        nameLabel.isBordered = false
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        addSubview(nameLabel)
        
        // Connection type indicator (right)
        connectionIconView.frame = NSRect(x: 215, y: 2, width: 16, height: 16)
        let connectionIcon = isWireless ? "wifi" : "cable.connector"
        connectionIconView.image = NSImage(systemSymbolName: connectionIcon, accessibilityDescription: isWireless ? "Wireless" : "USB")
        addSubview(connectionIconView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        hoverEffectView.frame = bounds.insetBy(dx: 4, dy: 0)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        animateHover(visible: true)
    }
    
    override func mouseExited(with event: NSEvent) {
        animateHover(visible: false)
    }
    
    private func animateHover(visible: Bool) {
        if visible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.05
                hoverEffectView.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                hoverEffectView.animator().alphaValue = 0
            }
        }
    }
}

// MARK: - Custom Controls View
private class DeviceActionButton: NSButton {
    var deviceID: String?
}



private class AppActionButton: NSButton {
    var app: AndroidApp?
    var deviceID: String?
}

private final class ControlsMenuItemView: NSView {
    

    
    init(deviceID: String, isWireless: Bool, target: AnyObject, frontCamAction: Selector, backCamAction: Selector, mirrorAction: Selector, installAction: Selector, shellAction: Selector, disconnectAction: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 44)) // Reduced height
        
        // Helper to configure button size
        func config(_ btn: NSButton) -> NSButton {
            btn.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(equalToConstant: 28),
                btn.heightAnchor.constraint(equalToConstant: 28)
            ])
            return btn
        }
        
        // Buttons
        let mirrorBtn = config(createButton(imageName: "display", tooltip: "Mirror Device", target: target, action: mirrorAction, deviceID: deviceID))
        let installBtn = config(createButton(imageName: "shippingbox", tooltip: "Install APK", target: target, action: installAction, deviceID: deviceID))
        let shellBtn = config(createButton(imageName: "terminal", tooltip: "Open ADB Shell", target: target, action: shellAction, deviceID: deviceID))
        
        let frontCamBtn = config(createButton(imageName: "person.fill.viewfinder", tooltip: "Front Camera", target: target, action: frontCamAction, deviceID: deviceID))
        let backCamBtn = config(createButton(imageName: "camera", tooltip: "Back Camera", target: target, action: backCamAction, deviceID: deviceID))
        
        var disconnectBtn: NSButton?
        if isWireless {
            disconnectBtn = config(createButton(imageName: "wifi.slash", tooltip: "Disconnect Device", target: target, action: disconnectAction, deviceID: deviceID))
        }
        
        // Grid Layout
        let gridView = NSGridView(views: [
            [mirrorBtn, installBtn, shellBtn, frontCamBtn, backCamBtn, disconnectBtn ?? NSGridCell.emptyContentView]
        ])
        
        gridView.translatesAutoresizingMaskIntoConstraints = false
        gridView.columnSpacing = 12
        gridView.rowSpacing = 0
        gridView.xPlacement = .center
        gridView.yPlacement = .center
        
        addSubview(gridView)
        
        NSLayoutConstraint.activate([
            gridView.centerXAnchor.constraint(equalTo: centerXAnchor),
            gridView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError() }
    

    
    private func createButton(imageName: String, tooltip: String, target: AnyObject, action: Selector, deviceID: String) -> NSButton {
        let btn = DeviceActionButton()
        btn.deviceID = deviceID
        btn.bezelStyle = .inline
        btn.image = NSImage(systemSymbolName: imageName, accessibilityDescription: tooltip)
        btn.image?.size = NSSize(width: 14, height: 14)
        btn.toolTip = tooltip
        btn.target = target
        btn.action = action
        btn.isBordered = false
        return btn
    }
}

// MARK: - Toggle Menu Item View
private class ToggleMenuItemView: NSView {
    private let titleLabel = NSTextField()
    private let toggleSwitch = NSSwitch()
    private let iconView = NSImageView()
    
    var onToggle: ((Bool) -> Void)?
    
    init(title: String, icon: String, isOn: Bool, onToggle: @escaping (Bool) -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 26))
        self.onToggle = onToggle
        
        // Icon
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        iconView.contentTintColor = .labelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        
        // Title
        titleLabel.stringValue = title
        titleLabel.font = NSFont.menuFont(ofSize: 14)
        titleLabel.textColor = .labelColor
        titleLabel.drawsBackground = false
        titleLabel.isBordered = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        // Switch
        toggleSwitch.state = isOn ? .on : .off
        toggleSwitch.controlSize = .mini
        toggleSwitch.target = self
        toggleSwitch.action = #selector(switchToggled(_:))
        toggleSwitch.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toggleSwitch)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            toggleSwitch.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            toggleSwitch.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    @objc private func switchToggled(_ sender: NSSwitch) {
        onToggle?(sender.state == .on)
    }
}



// MARK: - Refresh Apps Custom View
private class RefreshAppsMenuItemView: NSView {
    private let button: DeviceActionButton
    
    init(deviceID: String, target: AnyObject?, action: Selector) {
        self.button = DeviceActionButton(
            image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")!,
            target: target,
            action: action
        )
        self.button.deviceID = deviceID
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        setupView()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func setupView() {
        // Configure Button to look like a menu item row
        button.title = "Refresh Apps"
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.font = NSFont.systemFont(ofSize: 13)
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .labelColor
        
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        
        NSLayoutConstraint.activate([
            // Fill the view with padding similar to standard menu items
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14), // Standard menu padding
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
}
