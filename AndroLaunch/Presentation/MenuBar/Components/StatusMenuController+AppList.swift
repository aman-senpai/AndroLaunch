//
//  StatusMenuController+AppList.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 11/29/25.
//

import AppKit

extension StatusMenuController {
    
    // Helper struct for actions
    struct AppActionData {
        let app: AndroidApp
        let deviceID: String
    }
    
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
        
        var startIndex = -1
        for (index, item) in submenu.items.enumerated() {
            if item.view is SearchMenuItemView {
                startIndex = index + 1
                break
            }
        }
        
        guard startIndex != -1 else { return }
        
        let endIndex = submenu.items.count - 1
        
        if startIndex < endIndex {
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
    
    func createAppMenuItem(app: AndroidApp, deviceID: String) -> NSMenuItem {
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
        
        // Get Version
        let getVersionItem = NSMenuItem(title: "Get Version", action: #selector(getAppVersionAction(_:)), keyEquivalent: "")
        getVersionItem.target = self
        getVersionItem.representedObject = AppActionData(app: app, deviceID: deviceID)
        getVersionItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Get Version")
        submenu.addItem(getVersionItem)
        
        submenu.addItem(NSMenuItem.separator())
        
        // Uninstall
        let uninstallItem = NSMenuItem(title: "Uninstall", action: #selector(uninstallAction(_:)), keyEquivalent: "")
        uninstallItem.target = self
        uninstallItem.representedObject = AppActionData(app: app, deviceID: deviceID)
        uninstallItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Uninstall")
        submenu.addItem(uninstallItem)
        
        item.submenu = submenu
        return item
    }
    
    @objc func launchAppAction(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? AppActionData else { return }
        launchApp(deviceID: data.deviceID, appID: data.app.id, appName: data.app.name)
    }
    
    @objc func clearDataAction(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? AppActionData else { return }
        clearAppData(deviceID: data.deviceID, app: data.app)
    }
    
    @objc func uninstallAction(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? AppActionData else { return }
        uninstallApp(deviceID: data.deviceID, app: data.app)
    }
    
    @objc func getAppVersionAction(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? AppActionData else { return }
        getAppVersion(deviceID: data.deviceID, app: data.app)
    }
    
    private func launchApp(deviceID: String, appID: String, appName: String) {
        viewModel.launchApp(packageID: appID, deviceID: deviceID, appName: appName)
        NSApp.stopModal()
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
    
    func getAppVersion(deviceID: String, app: AndroidApp) {
        print("DEBUG: Getting version for \(app.name) on \(deviceID)")
        
        // We will run a command that outputs the version info nicely
        // Command: adb shell dumpsys package <package> | grep -i version
        
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            let fileName = "GetVersion-\(app.name).command"
            let fileURL = tempDir.appendingPathComponent(fileName)
            
            var adbDir = "$HOME/Library/Android/sdk/platform-tools"
            // Accessing adbPath from viewModel if feasible, or hardcode/fallback
            if let adbPath = self.viewModel.adbPath {
                let url = URL(fileURLWithPath: adbPath)
                adbDir = url.deletingLastPathComponent().path
            }
            
            let scriptContent = """
            #!/bin/bash
            clear
            echo -n -e "\\033]0;Version Info - \(app.name)\\007"
            
            echo "App: \(app.name)"
            echo "Package: \(app.id)"
            echo "Device: \(deviceID)"
            echo "----------------------------------------"
            export PATH=$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(adbDir)
            
            if ! command -v adb &> /dev/null; then
                echo "Error: adb not found."
                echo "PATH: $PATH"
                read -n 1 -s -r -p "Press any key to close..."
                exit 1
            fi
            
            echo "fetching version info..."
            adb -s \(deviceID) shell dumpsys package \(app.id) | grep -i "version"
            
            echo ""
            echo "----------------------------------------"
            read -n 1 -s -r -p "Press any key to close..."
            """
            
            try scriptContent.write(to: fileURL, atomically: true, encoding: .utf8)
            let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
            try fileManager.setAttributes(attributes, ofItemAtPath: fileURL.path)
            
            NSWorkspace.shared.open(fileURL)
        } catch {
            print("ERROR: Failed to launch get version: \(error)")
        }
    }
}
