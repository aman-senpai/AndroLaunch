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
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let container = DependencyContainer.shared
        statusMenuController = StatusMenuController(viewModel: container.menuViewModel)

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
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 420, height: 480))
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
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
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
}
