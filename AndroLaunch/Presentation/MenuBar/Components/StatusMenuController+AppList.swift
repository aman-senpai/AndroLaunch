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
}
