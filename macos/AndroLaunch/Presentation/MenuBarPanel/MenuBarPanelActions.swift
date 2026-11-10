//
//  MenuBarPanelActions.swift
//  AndroLaunch
//
//  The small action surface the glass menu-bar dashboard exposes besides the
//  five tabs. StatusMenuController builds the live closures; SwiftUI previews
//  and the snapshot renderer use `.preview` (no-ops).
//

import Foundation

struct MenuBarPanelActions {
    /// Opens the floating mirror controls panel for the primary device.
    var openMirrorControls: () -> Void = {}
    /// Opens the storage analytics window for the primary device.
    var openStorageAnalytics: () -> Void = {}
    /// Materializes and reveals the local Finder mirror for the primary device.
    var openFinderMirror: () -> Void = {}
    /// Sends the current Mac clipboard text to the primary device. Returns a
    /// short inline feedback line, or nil when the result needs no message.
    var copyClipboardToAndroid: () -> String? = { nil }
    /// Opens the full Hub window.
    /// Shows the classic NSMenu under the status item.
    /// Closes the panel (the legacy-menu path uses this before popping up).
    var closePanel: () -> Void = {}

    static let preview = MenuBarPanelActions()
}
