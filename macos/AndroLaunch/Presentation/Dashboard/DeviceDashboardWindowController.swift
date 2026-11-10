//
//  DeviceDashboardWindowController.swift
//  AndroLaunch
//
//  Compact per-device dashboard window (380×760). The window shell is
//  intentionally thin: presentation lives in `DeviceDashboardView` and its five
//  tab views, so the same views can be rendered by `ImageRenderer` for design
//  review.
//

import AppKit
import SwiftUI

enum DeviceDashboardTab: String, CaseIterable, Identifiable {
    case apps
    case notifications
    case storage
    case device
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: return "Apps"
        case .notifications: return "Notifications"
        case .storage: return "Storage"
        case .device: return "Device"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .apps: return "square.grid.2x2.fill"
        case .notifications: return "bell.fill"
        case .storage: return "internaldrive.fill"
        case .device: return "iphone.gen3"
        case .settings: return "gearshape.fill"
        }
    }
}

final class DeviceDashboardWindowController: NSWindowController {
    static let shared = DeviceDashboardWindowController()

    private init() {
        let hosting = NSHostingController(
            rootView: DeviceDashboardView(deviceID: nil, initialTab: .apps))
        hosting.view.wantsLayer = true

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "Device"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 380, height: 620)
        window.backgroundColor = NSColor(
            name: nil,
            dynamicProvider: { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return isDark
                    ? NSColor(srgbRed: 0.06, green: 0.06, blue: 0.07, alpha: 1)
                    : NSColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1)
            })
        window.contentViewController = hosting
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Opens the dashboard for a device and tab. Passing `nil` follows the Hub's
    /// selected device.
    func show(deviceID: String? = nil, tab: DeviceDashboardTab = .apps) {
        window?.contentViewController = NSHostingController(
            rootView: DeviceDashboardView(deviceID: deviceID, initialTab: tab))
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
