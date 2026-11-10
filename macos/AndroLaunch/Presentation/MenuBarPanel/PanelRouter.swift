//
//  PanelRouter.swift
//  AndroLaunch
//
//  A small cross-surface router for opening the one menu-bar dashboard panel.
//  The Hub window has been removed; onboarding, the Dock icon, Trackpad and
//  Glance all route here instead of opening a second window.
//

import Foundation

extension Notification.Name {
    static let openMenuBarPanelRequested = Notification.Name(
        "com.senpai.AndroLaunch.OpenMenuBarPanel")
    static let openPanelStorageAnalytics = Notification.Name(
        "com.senpai.AndroLaunch.OpenPanelStorageAnalytics")
}

enum PanelRouter {
    static func openDashboard() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .openMenuBarPanelRequested, object: nil)
        }
    }

    /// Storage analysis is an inline section under the Storage tab, never a
    /// separate window. This opens the panel and asks the dashboard to select
    /// Storage and expand the analysis.
    static func openStorageAnalytics() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .openMenuBarPanelRequested, object: nil)
        }
        // The panel's SwiftUI tree needs to be mounted before it can receive the
        // storage-tab request.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            NotificationCenter.default.post(
                name: .openPanelStorageAnalytics, object: nil)
        }
    }
}
