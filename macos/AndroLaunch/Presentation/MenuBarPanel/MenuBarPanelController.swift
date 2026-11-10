//
//  MenuBarPanelController.swift
//  AndroLaunch
//
//  Floating glass panel for the menu-bar dashboard. A borderless,
//  non-activating NSPanel whose content is `MenuBarDashboardView`. The panel is
//  anchored under the status item, clamped to the active screen, and closes on
//  Escape, outside click (key resignation), screen changes or a second click on
//  the status item.
//

import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted when the glass panel closes so the status item can drop its
    /// highlighted state even when the close did not go through the button.
    static let menuBarPanelDidClose = Notification.Name(
        "com.senpai.AndroLaunch.MenuBarPanelDidClose")
}

final class MenuBarPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class MenuBarPanelBackdrop: NSVisualEffectView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateMaterial()
        updateBorder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMaterial()
    }

    /// Dark glass needs a denser HUD material to stay legible over busy
    /// desktops; light glass keeps the softer popover material.
    func updateMaterial() {
        let isDark =
            effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        material = isDark ? .hudWindow : .popover
    }

    func updateBorder() {
        wantsLayer = true
        layer?.cornerRadius = 24
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
    }
}

final class MenuBarPanelController: NSObject, NSWindowDelegate {
    static let shared = MenuBarPanelController()

    private var panel: MenuBarPanelWindow?
    private var hosting: NSHostingView<MenuBarDashboardView>?
    private var backdrop: MenuBarPanelBackdrop?
    private var escapeMonitor: Any?
    private var outsideClickMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    /// `windowDidResignKey` fires during activation/key transfer. Only close on
    /// a real outside interaction, never while the panel is being presented.
    private var allowsAutoClose = false
    private var shownAt = Date.distantPast
    private(set) var lastCloseAt = Date.distantPast

    var isVisible: Bool { panel?.isVisible == true }

    /// A status-item click can make the panel resign key just before the action
    /// runs, which would otherwise close and immediately reopen it. The toggle
    /// treats a close in the last 0.4s as "this click already closed it".
    var closedRecently: Bool {
        Date().timeIntervalSince(lastCloseAt) < 0.4
    }

    private override init() {
        super.init()
    }

    // MARK: - Presentation

    func toggle(
        anchor: CGRect, actions: MenuBarPanelActions, initialTab: DeviceDashboardTab = .apps
    ) {
        if isVisible {
            close()
        } else {
            show(anchor: anchor, actions: actions, initialTab: initialTab)
        }
    }

    func show(
        anchor: CGRect, actions: MenuBarPanelActions,
        initialTab: DeviceDashboardTab = .apps
    ) {
        let panel = ensurePanel()
        hosting?.rootView = MenuBarDashboardView(initialTab: initialTab, actions: actions)

        // The status item lives on the primary menu bar. `NSScreen.main` follows
        // the key window and can point at a secondary portrait display, which put
        // the panel off-screen at launch; use the primary screen explicitly.
        let screen = NSScreen.screens.first
            ?? NSScreen.main
        let visibleFrame =
            screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = MenuBarPanelGeometry.frame(anchor: anchor, screenFrame: visibleFrame)

        panel.setFrame(frame, display: true)
        // A status-item click does not normally activate an accessory app. The
        // panel must be key to receive Escape and to mirror a real popover, and
        // `.accessory` keeps a Dock icon from appearing when we activate.
        allowsAutoClose = false
        shownAt = Date()
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
        panel.invalidateShadow()
        installEscapeMonitor()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.panel?.isVisible == true else { return }
            self.allowsAutoClose = true
        }

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.close()
        }
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        allowsAutoClose = false
        lastCloseAt = Date()
        panel.orderOut(nil)
        removeEventMonitors()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        NotificationCenter.default.post(name: .menuBarPanelDidClose, object: self)
    }

    /// Rebuild the SwiftUI tree (used when the primary device changes while the
    /// panel is visible; the dashboard also observes HubStore itself, this is a
    /// belt-and-braces refresh for the actions closures).
    func setActions(_ actions: MenuBarPanelActions) {
        hosting?.rootView = MenuBarDashboardView(initialTab: .apps, actions: actions)
    }

    /// Debug-only capture of the live panel window (own-window capture does not
    /// need Screen Recording permission). Falls back to the content view cache.
    func captureLiveWindow(to url: URL) -> Bool {
        guard let panel, panel.isVisible, let view = panel.contentView else { return false }
        guard let cachedRep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return false
        }
        view.cacheDisplay(in: view.bounds, to: cachedRep)
        guard let image = cachedRep.cgImage else { return false }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            return false
        }
        return (try? data.write(to: url)) != nil
    }

    // MARK: - Window construction

    private func ensurePanel() -> MenuBarPanelWindow {
        if let panel { return panel }

        let panel = MenuBarPanelWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: MenuBarPanelGeometry.panelWidth,
                height: MenuBarPanelGeometry.panelHeight),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.title = "AndroLaunch Dashboard"

        let backdrop = MenuBarPanelBackdrop()
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.updateMaterial()
        backdrop.updateBorder()

        let hosting = NSHostingView(
            rootView: MenuBarDashboardView(initialTab: .apps, actions: .preview))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: backdrop.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
        ])

        panel.contentView = backdrop

        self.panel = panel
        self.backdrop = backdrop
        self.hosting = hosting
        return panel
    }

    // MARK: - Escape / outside click

    private func installEscapeMonitor() {
        removeEventMonitors()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self, self.isVisible, event.keyCode == 53,
                self.panel?.attachedSheet == nil
            else { return event }
            self.close()
            return nil
        }
        // Clicks in another application never reach a local monitor. A global
        // mouse monitor (no accessibility permission needed for mouse events)
        // makes the panel behave like a real popover: click anywhere else closes.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self, self.allowsAutoClose,
                Date().timeIntervalSince(self.shownAt) > 0.2,
                self.panel?.attachedSheet == nil
            else { return }
            self.close()
        }
    }

    private func removeEventMonitors() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // A status-bar panel can lose key to one of its own child windows
        // (scrcpy mirror/camera, an attached Settings sheet, the command
        // palette). Closing on resign made the dashboard disappear right after
        // opening. Real outside clicks are handled by the global mouse monitor.
    }

    func windowWillClose(_ notification: Notification) {
        removeEventMonitors()
    }
}
