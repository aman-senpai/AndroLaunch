//
//  StatusMenuController.swift
//  AndroLaunch
//

import AppKit
import Combine

final class StatusMenuController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let viewModel: MenuViewModel
    private var cancellables = Set<AnyCancellable>()
    private var currentDeviceID: String?
    
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
            button.imagePosition = .imageLeft
            button.title = "Launcher"
            button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            statusItem.length = 100
        }
        refreshDevices()
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
        menu.delegate = self
        
        // Header with app icon
        let headerItem = NSMenuItem(title: "AndroLaunch", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        let headerConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        headerItem.image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "AndroLaunch")?.withSymbolConfiguration(headerConfig)
        menu.addItem(headerItem)
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
                deviceItem.representedObject = device.id
                deviceItem.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "Device")
                deviceItem.image?.size = NSSize(width: 16, height: 16)
                
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
    
    private func configureDeviceSubmenu(_ submenu: NSMenu, for device: AndroidDevice) {
        // Mirror Action
        let mirrorItem = NSMenuItem(
            title: "Mirror Device",
            action: #selector(mirrorDevice),
            keyEquivalent: ""
        )
        mirrorItem.target = self
        mirrorItem.representedObject = device.id
        mirrorItem.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Mirror")
        mirrorItem.image?.size = NSSize(width: 16, height: 16)
        submenu.addItem(mirrorItem)
        submenu.addItem(NSMenuItem.separator())
        
        // Apps Section
        if device.id == currentDeviceID {
            if viewModel.isLoading {
                let loadingItem = NSMenuItem(title: "Loading apps...", action: nil, keyEquivalent: "")
                loadingItem.isEnabled = false
                submenu.addItem(loadingItem)
            } else if !viewModel.apps.isEmpty {
                let appsMenuItem = NSMenuItem()
                appsMenuItem.view = createAppListView(for: viewModel.apps, deviceID: device.id)
                submenu.addItem(appsMenuItem)
                submenu.addItem(NSMenuItem.separator())
            } else if !viewModel.isLoading {
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
        column.width = 200
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
        viewModel.fetchApps(for: deviceID)
    }
    
    @objc private func mirrorDevice(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.mirrorDevice(deviceID: deviceID)
    }
    
    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/aman-senpai/AndroLaunch") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension StatusMenuController: NSMenuDelegate {
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        if let deviceID = item?.representedObject as? String, deviceID != currentDeviceID {
            currentDeviceID = deviceID
            viewModel.fetchApps(for: deviceID)
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
        
        return containerView
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
