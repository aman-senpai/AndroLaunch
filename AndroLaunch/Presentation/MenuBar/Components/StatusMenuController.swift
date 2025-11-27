//
//  StatusMenuController.swift
//  AndroLaunch
//

import AppKit
import Combine
import SwiftUI

final class StatusMenuController: NSObject {
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
    }
    
    private func updateMenu() {
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
    
    private func truncateDeviceID(_ deviceID: String, maxLength: Int = 30) -> String {
        guard deviceID.count > maxLength else { return deviceID }
        let prefixLength = maxLength / 2 - 2
        let suffixLength = maxLength / 2 - 2
        let prefix = deviceID.prefix(prefixLength)
        let suffix = deviceID.suffix(suffixLength)
        return "\(prefix)...\(suffix)"
    }
    
    private func configureDeviceSubmenu(_ submenu: NSMenu, for device: AndroidDevice) {
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
        
        submenu.addItem(NSMenuItem.separator())
        
        // Controls Section (Audio, Camera, Mirror, Disconnect)
        let controlsItem = NSMenuItem()
        let isAudioEnabled = viewModel.isAudioEnabled(for: device.id)
        
        // Determine if device is wireless for disconnect button
        let isWireless = device.id.contains(":") || 
                        device.id.contains("_tcp") || 
                        device.id.contains("_udp")
        
        let controlsView = ControlsMenuItemView(
            isAudioEnabled: isAudioEnabled,
            deviceID: device.id,
            isWireless: isWireless,
            target: self,
            audioAction: #selector(toggleAudio(_:)),
            frontCamAction: #selector(launchFrontCamera(_:)),
            backCamAction: #selector(launchBackCamera(_:)),
            mirrorAction: #selector(mirrorDevice(_:)),
            installAction: #selector(installAPK(_:)),
            disconnectAction: #selector(disconnectDevice(_:))
        )
        controlsItem.view = controlsView
        submenu.addItem(controlsItem)
        
        // Resolution Section (Radio Buttons)
        let resItem = NSMenuItem()
        let currentResolution = viewModel.getResolution(for: device.id)
        let resView = ResolutionMenuItemView(
            currentResolution: currentResolution,
            deviceID: device.id,
            target: self,
            action: #selector(changeResolution(_:))
        )
        resItem.view = resView
        submenu.addItem(resItem)
        
        submenu.addItem(NSMenuItem.separator())
        
        submenu.addItem(NSMenuItem.separator())

        
        // Apps Section - check if apps exist for this specific device
        let deviceApps = viewModel.deviceApps[device.id] ?? []
        
        if viewModel.isLoading && device.id == currentDeviceID {
            let loadingItem = NSMenuItem(title: "Loading apps...", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            submenu.addItem(loadingItem)
        } else if !deviceApps.isEmpty {
            let appsMenuItem = NSMenuItem()
            appsMenuItem.view = createAppListView(for: deviceApps, deviceID: device.id)
            submenu.addItem(appsMenuItem)
            submenu.addItem(NSMenuItem.separator())
        } else if device.id == currentDeviceID && !viewModel.isLoading {
            let statusItem = NSMenuItem(
                title: viewModel.error ?? "No apps found",
                action: nil,
                keyEquivalent: ""
            )
            statusItem.isEnabled = false
            submenu.addItem(statusItem)
        }
        
        // Refresh Apps
        let refreshAppsItem = NSMenuItem(
            title: "Refresh Apps",
            action: #selector(refreshApps),
            keyEquivalent: ""
        )
        refreshAppsItem.representedObject = device.id
        refreshAppsItem.target = self
        refreshAppsItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        refreshAppsItem.image?.size = NSSize(width: 16, height: 16)
        submenu.addItem(refreshAppsItem)
    }
    
    // MARK: - Scrollable App List with Search
    private var handlerKey: UInt8 = 0
    
    private func createAppListView(for apps: [AndroidApp], deviceID: String) -> NSView {
        let containerView = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 250))
        
        // Add custom search field with improved styling
        let searchField = DeviceSearchField(frame: NSRect(x: 8, y: 222, width: 284, height: 22))
        searchField.placeholderString = "Search apps..."
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        searchField.deviceID = deviceID
        searchField.focusRingType = .none
        searchField.bezelStyle = .roundedBezel
        searchField.font = NSFont.systemFont(ofSize: 13)
        searchField.isContinuous = false // Disable real-time search
        containerView.addSubview(searchField)
        
        // Make search field first responder when menu opens
        DispatchQueue.main.async {
            searchField.becomeFirstResponder()
        }
        
        // Configure scroll view and table view with improved styling
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        
        let tableView = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("AppColumn"))
        column.width = 280
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 28
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        
        let handler = AppsTableViewHandler(originalApps: apps, deviceID: deviceID, controller: self)
        tableView.dataSource = handler
        tableView.delegate = handler
        
        objc_setAssociatedObject(
            tableView,
            &handlerKey,
            handler,
            .OBJC_ASSOCIATION_RETAIN
        )
        
        scrollView.documentView = tableView
        containerView.addSubview(scrollView)
        
        return containerView
    }
    
    @objc private func searchFieldChanged(_ sender: DeviceSearchField) {
        guard sender.deviceID != nil else { return }
        let searchText = sender.stringValue.lowercased()
        
        // Find the associated table view and handler
        guard let containerView = sender.superview,
              let scrollView = containerView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView,
              let tableView = scrollView.documentView as? NSTableView,
              let handler = objc_getAssociatedObject(tableView, &handlerKey) as? AppsTableViewHandler else { return }
        
        handler.searchText = searchText
        tableView.reloadData()
        // Scroll to top when search changes
        tableView.scrollRowToVisible(0)
    }
    
    fileprivate func launchApp(deviceID: String, appID: String) {
        viewModel.launchApp(packageID: appID, deviceID: deviceID)
        NSApp.stopModal()
    }
    
    // MARK: - Actions
    @objc private func refreshDevices() {
        viewModel.refresh()
        currentDeviceID = nil
    }
    
    @objc private func refreshApps(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        currentDeviceID = deviceID
        viewModel.forceRefreshApps(for: deviceID)
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
            openPanel.showsResizeIndicator = true
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
    
    @objc private func toggleAudio(_ sender: NSButton) {
        if let deviceButton = sender as? DeviceActionButton, let deviceID = deviceButton.deviceID {
            // 1. Optimistic UI Update
            let currentAudioState = viewModel.isAudioEnabled(for: deviceID)
            let newAudioState = !currentAudioState
            
            // Find the ControlsMenuItemView and update it directly
            if let controlsView = sender.superview?.superview as? ControlsMenuItemView {
                 controlsView.setAudioEnabled(newAudioState)
            }
            
            // 2. Perform Action
            viewModel.toggleAudio(for: deviceID)
            
            // 3. Prevent Menu Closure (optional, but good for toggles)
            // If we want the menu to stay open, we do nothing.
            // If we want it to close, we call cancelTracking().
            // Standard behavior for toggles in menus is often to stay open or close depending on UX.
            // Given the user complaint about "sluggish", keeping it open and showing instant change is better.
        }
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
    
    @objc private func changeResolution(_ sender: NSButton) {
        // Use custom button class to get resolution and deviceID
        if let resButton = sender as? DeviceResolutionRadioButton, let deviceID = resButton.deviceID {
            let resolution = resButton.resolutionValue
            viewModel.setResolution(for: deviceID, resolution: resolution)
            // We might want to update the UI state (radio selection) if the menu stays open,
            // but usually it closes. If it stays open, the ViewModel update should trigger a refresh
            // if we are observing it correctly, but NSMenu items don't auto-update views easily without reload.
            // Since clicking usually closes the menu, this is fine.
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
}

extension StatusMenuController: NSMenuDelegate {
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        if let deviceID = item?.representedObject as? String {
            // Always fetch - the repository will use cache if available
            // This ensures the menu updates even when using cached data
            if deviceID != currentDeviceID {
                currentDeviceID = deviceID
                viewModel.fetchApps(for: deviceID)
                // Force menu update after a short delay to show cached apps
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.updateMenu()
                }
            }
        }
    }
}

// MARK: - Table View Components with Search Support
private final class AppsTableViewHandler: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let originalApps: [AndroidApp]
    var filteredApps: [AndroidApp] = []
    let deviceID: String
    weak var controller: StatusMenuController?
    var searchText: String = "" {
        didSet {
            filterApps()
        }
    }
    
    init(originalApps: [AndroidApp], deviceID: String, controller: StatusMenuController) {
        self.originalApps = originalApps
        self.deviceID = deviceID
        self.controller = controller
        super.init()
        filterApps()
    }
    
    private func filterApps() {
        if searchText.isEmpty {
            filteredApps = originalApps
        } else {
            filteredApps = originalApps.filter { app in
                // Fuzzy search implementation
                let searchTerms = searchText.lowercased().split(separator: " ")
                let appName = app.name.lowercased()
                let appId = app.id.lowercased()
                
                return searchTerms.allSatisfy { term in
                    appName.contains(term) || appId.contains(term)
                }
            }
        }
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return filteredApps.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let app = filteredApps[row]
        
        let containerView = NSView()
        
        // App icon with dynamic selection based on app type
        let iconView = NSImageView(frame: NSRect(x: 8, y: 4, width: 20, height: 20))
        let iconName = getAppIconName(for: app)
        iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "App Icon")
        iconView.image?.size = NSSize(width: 20, height: 20)
        containerView.addSubview(iconView)
        
        // App name
        let textField = NSTextField(labelWithString: app.name)
        textField.font = NSFont.menuFont(ofSize: 14)
        textField.textColor = NSColor.controlTextColor
        textField.drawsBackground = false
        textField.frame = NSRect(x: 36, y: 4, width: 200, height: 20)
        containerView.addSubview(textField)
        
        // Trash/Uninstall Button
        let trashButton = NSButton()
        trashButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Uninstall")
        trashButton.image?.size = NSSize(width: 12, height: 12)
        trashButton.bezelStyle = .inline
        trashButton.isBordered = false
        trashButton.toolTip = "Uninstall App"
        trashButton.frame = NSRect(x: 250, y: 4, width: 20, height: 20)
        trashButton.target = self // The handler handles the action dispatch
        trashButton.action = #selector(uninstallClicked(_:))
        
        // Store app and controller info in the button (using a subclass would be cleaner, but tag/associated object works too)
        // Let's use a subclass wrapper or just find the row index.
        // Since we are in viewFor, we know the app.
        // We can use a custom button class.
        let customBtn = AppActionButton()
        customBtn.app = app
        customBtn.deviceID = deviceID
        customBtn.image = trashButton.image
        customBtn.bezelStyle = trashButton.bezelStyle
        customBtn.isBordered = trashButton.isBordered
        customBtn.toolTip = trashButton.toolTip
        customBtn.frame = trashButton.frame
        customBtn.target = self
        customBtn.action = #selector(uninstallClicked(_:))
        
        containerView.addSubview(customBtn)
        
        return containerView
    }
    
    @objc private func uninstallClicked(_ sender: AppActionButton) {
        guard let app = sender.app, let deviceID = sender.deviceID else { return }
        controller?.uninstallApp(deviceID: deviceID, app: app)
    }
    
    private func getAppIconName(for app: AndroidApp) -> String {
        return AppIconMapper.getIconName(for: app)
    }
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return MenuTableRowView()
    }
    
    func tableView(_ tableView: NSTableView, keyDown event: NSEvent) {
        switch event.keyCode {
        case 125: // Down arrow
            if tableView.selectedRow < tableView.numberOfRows - 1 {
                let newRow = tableView.selectedRow + 1
                tableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
                tableView.scrollRowToVisible(newRow)
            }
        case 126: // Up arrow
            if tableView.selectedRow > 0 {
                let newRow = tableView.selectedRow - 1
                tableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
                tableView.scrollRowToVisible(newRow)
            }
        case 36: // Return
            if tableView.selectedRow >= 0 {
                let app = filteredApps[tableView.selectedRow]
                controller?.launchApp(deviceID: deviceID, appID: app.id)
            }
        default:
            break
        }
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return true
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        controller?.launchApp(deviceID: deviceID, appID: filteredApps[row].id)
    }
}

private final class MenuTableRowView: NSTableRowView {
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
    
    private var trackingArea: NSTrackingArea?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(hoverEffectView)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
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
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            hoverEffectView.animator().alphaValue = visible ? 1 : 0
        }
    }
    
    override func drawSelection(in dirtyRect: NSRect) {
    }
}

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
        deviceIconView.frame = NSRect(x: 8, y: 2, width: 16, height: 16)
        deviceIconView.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "Device")
        deviceIconView.contentTintColor = .controlTextColor
        addSubview(deviceIconView)
        
        // Device name (center)
        nameLabel.stringValue = deviceName
        nameLabel.font = NSFont.menuFont(ofSize: 14)
        nameLabel.textColor = .controlTextColor
        nameLabel.frame = NSRect(x: 30, y: 2, width: 180, height: 16)
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
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            hoverEffectView.animator().alphaValue = visible ? 1 : 0
        }
    }
}

// MARK: - Custom Controls View
private class DeviceActionButton: NSButton {
    var deviceID: String?
}

private class DeviceResolutionRadioButton: NSButton {
    var deviceID: String?
    var resolutionValue: Int = 900
}

private class AppActionButton: NSButton {
    var app: AndroidApp?
    var deviceID: String?
}

private final class ControlsMenuItemView: NSView {
    
    private var audioButton: NSButton?
    
    init(isAudioEnabled: Bool, deviceID: String, isWireless: Bool, target: AnyObject, audioAction: Selector, frontCamAction: Selector, backCamAction: Selector, mirrorAction: Selector, installAction: Selector, disconnectAction: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 30))
        
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 16
        stackView.distribution = .fill
        stackView.alignment = .centerY
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        
        // Center the stack view
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        // Mirror Button
        let mirrorBtn = createButton(
            imageName: "display",
            tooltip: "Mirror Device",
            target: target,
            action: mirrorAction,
            deviceID: deviceID
        )
        stackView.addArrangedSubview(mirrorBtn)
        
        // Install APK Button
        let installBtn = createButton(
            imageName: "shippingbox",
            tooltip: "Install APK",
            target: target,
            action: installAction,
            deviceID: deviceID
        )
        stackView.addArrangedSubview(installBtn)
        
        // Audio Button
        let audioBtn = createButton(
            imageName: isAudioEnabled ? "speaker.slash" : "speaker.wave.2",
            tooltip: isAudioEnabled ? "Disable Audio" : "Enable Audio",
            target: target,
            action: audioAction,
            deviceID: deviceID
        )
        self.audioButton = audioBtn
        stackView.addArrangedSubview(audioBtn)
        
        // Camera Group (Front + Back)
        let camStack = NSStackView()
        camStack.orientation = .horizontal
        camStack.spacing = 8
        
        let frontCamBtn = createButton(
            imageName: "person.fill.viewfinder",
            tooltip: "Front Camera",
            target: target,
            action: frontCamAction,
            deviceID: deviceID
        )
        camStack.addArrangedSubview(frontCamBtn)
        
        let backCamBtn = createButton(
            imageName: "camera",
            tooltip: "Back Camera",
            target: target,
            action: backCamAction,
            deviceID: deviceID
        )
        camStack.addArrangedSubview(backCamBtn)
        
        stackView.addArrangedSubview(camStack)
        
        // Disconnect Button (if wireless)
        if isWireless {
            let disconnectBtn = createButton(
                imageName: "wifi.slash",
                tooltip: "Disconnect Device",
                target: target,
                action: disconnectAction,
                deviceID: deviceID
            )
            stackView.addArrangedSubview(disconnectBtn)
        }
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func setAudioEnabled(_ isEnabled: Bool) {
        guard let btn = audioButton else { return }
        let imageName = isEnabled ? "speaker.slash" : "speaker.wave.2"
        let tooltip = isEnabled ? "Disable Audio" : "Enable Audio"
        
        btn.image = NSImage(systemSymbolName: imageName, accessibilityDescription: tooltip)
        btn.image?.size = NSSize(width: 14, height: 14)
        btn.toolTip = tooltip
    }
    
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

private final class ResolutionMenuItemView: NSView {
    
    init(currentResolution: Int, deviceID: String, target: AnyObject, action: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 8
        stackView.distribution = .fillEqually
        stackView.alignment = .centerY
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        let resolutions = [540, 720, 900, 1080]
        
        for res in resolutions {
            let btn = DeviceResolutionRadioButton(radioButtonWithTitle: "\(res)p", target: target, action: action)
            btn.deviceID = deviceID
            btn.resolutionValue = res
            btn.state = (res == currentResolution) ? .on : .off
            btn.controlSize = .small
            btn.font = NSFont.systemFont(ofSize: 10)
            stackView.addArrangedSubview(btn)
        }
    }
    
    required init?(coder: NSCoder) { fatalError() }
}
