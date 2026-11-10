//
//  MenuSection.swift
//  AndroLaunch
//
//  A self-contained slice of the status menu. Features contribute items through
//  this protocol instead of editing `StatusMenuController.rebuildMenu`, so the
//  menu stays one ordered, predictable list while every feature owns its code.
//

import AppKit

/// Whether the status menu is currently on screen.
///
/// AppKit tracks the highlighted row by index. Inserting or removing items while the
/// menu is open therefore leaves the highlight attached to whatever item slid into
/// that index — the "stuck highlight" bug. Anything structural is deferred until the
/// menu closes; sections may still update retained items in place.
enum MenuTrackingState {
    static var isOpen = false
}

protocol MenuSectionProviding: AnyObject {
    /// Stable identifier, used for debugging and de-duplication.
    var sectionID: String { get }

    /// Lower values appear earlier in the top-level menu.
    var topLevelOrder: Int { get }

    /// Items added once, after the device list and Previous Devices.
    func topLevelItems() -> [NSMenuItem]

    /// Items appended to one device's submenu, after Configuration.
    func deviceItems(for device: AndroidDevice) -> [NSMenuItem]

    /// Called whenever the main menu opens. Sections mutate their retained items
    /// in place here (state labels, enabled state) instead of forcing a rebuild.
    func menuWillOpen()
}

extension MenuSectionProviding {
    var topLevelOrder: Int { 100 }
    func deviceItems(for device: AndroidDevice) -> [NSMenuItem] { [] }
    func menuWillOpen() {}
}
