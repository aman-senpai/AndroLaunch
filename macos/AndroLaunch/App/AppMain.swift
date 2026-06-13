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
        WindowGroup(id: "main") {
            EmptyView()
                .frame(width: 0, height: 0)
                .hidden()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 0, height: 0)

        Settings {
            PreferencesView()
                .environmentObject(DependencyContainer.shared.preferencesViewModel)
                .frame(minWidth: 400, minHeight: 300)
                .navigationTitle("AndroLaunch Settings")
        }
    }
}
