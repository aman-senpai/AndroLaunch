//
//  PanelFeatureWindows.swift
//  AndroLaunch
//
//  Monochrome host windows for panel features that need more room than the
//  menu-bar panel: saved shell commands, the Android virtual-device manager and
//  Wi-Fi connection (QR / pairing code / IP / companion). Windows are reused so
//  reopening from the panel is instant, and they use the plain system window
//  chrome rather than the Hub's tinted surfaces.
//

import AppKit
import SwiftUI

enum PanelFeatureWindows {
    private static var windows: [String: NSWindow] = [:]

    // MARK: - Commands

    static func showCommandsManager() {
        let key = "commands"
        if let existing = windows[key] {
            bringForward(existing)
            return
        }
        let view = ManageCommandsView(viewModel: DependencyContainer.shared.menuViewModel)
        let hosting = NSHostingController(rootView: view)
        let window = monochromeWindow(
            title: "Commands",
            size: NSSize(width: 640, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            contentViewController: hosting)
        windows[key] = window
        bringForward(window)
    }

    // MARK: - Virtual devices

    static func showEmulatorManager() {
        let key = "emulator"
        if let existing = windows[key] {
            bringForward(existing)
            return
        }
        let view = EmulatorManagerView(
            viewModel: DependencyContainer.shared.emulatorManagerViewModel)
        let hosting = NSHostingController(rootView: view)
        let window = monochromeWindow(
            title: "Virtual Devices",
            size: NSSize(width: 960, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            contentViewController: hosting)
        window.minSize = NSSize(width: 780, height: 580)
        windows[key] = window
        bringForward(window)
    }

    // MARK: - Wi-Fi

    static func showWiFiConnection(initialTab: WiFiConnectionTab = .qr) {
        let key = "wifi"
        if let existing = windows[key] {
            bringForward(existing)
            return
        }
        let view = WiFiConnectionView(
            store: HubStore.shared, initialTab: initialTab)
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingController(rootView: view)
        let window = monochromeWindow(
            title: "Wi-Fi Connection",
            size: NSSize(width: 460, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            contentViewController: hosting)
        window.minSize = NSSize(width: 420, height: 560)
        windows[key] = window
        bringForward(window)
    }

    // MARK: - Helpers

    private static func monochromeWindow(
        title: String,
        size: NSSize,
        styleMask: NSWindow.StyleMask,
        contentViewController: NSViewController
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false)
        window.title = title
        window.contentViewController = contentViewController
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        // Plain system chrome and background: no tinted / purple treatment.
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.center()
        return window
    }

    private static func bringForward(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
