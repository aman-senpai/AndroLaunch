//
//  AppDelegate.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenuController: StatusMenuController?
    private var connectionCoordinator: ConnectionCoordinator?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Headless modes must run before any window or service is created.
        // 1. MCP server: the same binary acts as a local stdio server.
        if CommandLine.arguments.contains("--mcp-server") {
            MCPServerMain.run()
            exit(0)
        }
        // 2. Design verification: render real Hub views to PNG with ImageRenderer.
        if let index = CommandLine.arguments.firstIndex(of: "--render-hub-snapshots") {
            let output = CommandLine.arguments.indices.contains(index + 1)
                ? CommandLine.arguments[index + 1]
                : NSTemporaryDirectory() + "androlaunch-snapshots"
            HubSnapshotRenderer.render(to: output)
            exit(0)
        }

        let container = DependencyContainer.shared
        statusMenuController = StatusMenuController(viewModel: container.menuViewModel)

        // Continuity: watch for transports appearing/disappearing and fail over
        // between USB, Wi-Fi, Bonjour and user-added network addresses.
        let connectionCoordinator = ConnectionCoordinator.shared
        connectionCoordinator.start()
        self.connectionCoordinator = connectionCoordinator

        // Finder → Services → "Send to Android".
        FinderServiceProvider.shared.install()

        // Live phone surfaces start with the app and stay calm when the
        // companion is absent: both poll only devices the Mac already trusts.
        CallCenter.shared.start()
        MediaCenter.shared.start()
        CameraController.shared.refreshExtensionStatus()
        DeviceConnectionNotifier.shared.start()
        // A Glance board the user left enabled comes back with the app; it never
        // opens itself unless it was explicitly enabled.
        GlanceBoardController.shared.restoreIfEnabled()

        // Debug/manual launch helpers: open a surface immediately.
        if CommandLine.arguments.contains("--open-hub")
            || CommandLine.arguments.contains("--open-dashboard")
        {
            DispatchQueue.main.async {
                PanelRouter.openDashboard()
            }
        }
        if CommandLine.arguments.contains("--open-storage")
            || CommandLine.arguments.contains("--open-mirror-controls")
        {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let deviceID = container.menuViewModel.devices.first(where: \.isConnected)?.id
                if CommandLine.arguments.contains("--open-storage"), let deviceID {
                    StorageAnalyticsWindowController.shared.show(deviceID: deviceID)
                }
                if CommandLine.arguments.contains("--open-mirror-controls"), let deviceID {
                    MirrorControlsController.shared.show(deviceID: deviceID)
                }
            }
        }

        // StatusMenuController built its menu before the coordinator had learned
        // the remembered devices, so rebuild once on the next run-loop turn (after
        // the initial device feed lands) to put the continuity rows in place.
        DispatchQueue.main.async { [weak self] in
            self?.statusMenuController?.rebuildMenu()
        }

        let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        if !hasCompleted {
            DispatchQueue.main.async { [weak self] in
                self?.showOnboardingWindow()
            }
        }
    }

    private func showOnboardingWindow() {
        let container = DependencyContainer.shared
        let onboardingView = OnboardingView(viewModel: container.onboardingViewModel)
        let hostingController = NSHostingController(rootView: onboardingView)

        // Enable translucency: clear background on hosting view
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        // Frosted glass via visual effect view behind SwiftUI content
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 620, height: 600))
        visualEffect.material = .underWindowBackground
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true

        // Embed hosting view inside the visual effect view
        hostingController.view.frame = visualEffect.bounds
        hostingController.view.autoresizingMask = [.width, .height]
        visualEffect.addSubview(hostingController.view)

        // Window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = visualEffect
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        self.onboardingWindow = window

        container.onboardingViewModel.dismissHandler = { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            // First run ends on the one dashboard surface, not a second window.
            PanelRouter.openDashboard()
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.onboardingWindow = nil
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Tear down the presence timer and wake observer explicitly.
        connectionCoordinator?.stop()
        DependencyContainer.shared.adb.stopAllClipboardSync()
        DependencyContainer.shared.scrcpyService.stopAll()
    }

    /// Clicking the Dock icon brings the one dashboard panel forward instead of
    /// opening a second window.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            PanelRouter.openDashboard()
        }
        return true
    }

    // MARK: - Deep links

    /// `androlaunch://launch?serial=…&pkg=…` from desktop shortcuts and other apps.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if SpotlightService.handle(url) { break }
        }
    }

    /// Spotlight/CoreSpotlight result continuation.
    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        var info: [String: Any] = [:]
        userActivity.userInfo?.forEach { key, value in
            if let key = key as? String { info[key] = value }
        }
        return SpotlightService.handle(
            activityType: userActivity.activityType,
            userInfo: info)
    }
}
