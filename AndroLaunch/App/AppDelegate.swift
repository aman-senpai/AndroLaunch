//
//  AppDelegate.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenuController: StatusMenuController?
    private var settingsWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let container = DependencyContainer.shared
        statusMenuController = StatusMenuController(viewModel: container.menuViewModel)
    }
    
    func openPreferences() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        let label = NSTextField(labelWithString: "Settings Window")
        label.frame = NSRect(x: 20, y: 20, width: 260, height: 160)
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 24)
        
        window.contentView = label
        window.title = "Settings"
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
