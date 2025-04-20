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
        // Create window if needed
        if settingsWindow == nil {
            let settingsView = PreferencesView()
                .environmentObject(DependencyContainer.shared.menuViewModel)
            
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.contentViewController = NSHostingController(rootView: settingsView)
            settingsWindow?.title = "Preferences"
        }
        
        // Bring to front
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
