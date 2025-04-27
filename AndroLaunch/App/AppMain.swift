//
//  AppMain.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import SwiftUI

@main
struct AndroLaunch: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate

    var body: some Scene {
        // Main window group - required even for menu bar apps
        WindowGroup(id: "main") {
            EmptyView()
                .frame(width: 0, height: 0)
                .hidden()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 0, height: 0)

        // Settings scene
        Settings {
            PreferencesView()
                .environmentObject(DependencyContainer.shared.menuViewModel)
                .frame(minWidth: 400, minHeight: 300)
                .navigationTitle("AndroLaunch Settings")
        }
    }
}
