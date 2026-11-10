//
//  CallBannerController.swift
//  AndroLaunch
//
//  Floating "call banner" that appears while the phone rings (and stays up during
//  the call). It is a non-activating panel on purpose: answering a call must not
//  steal focus from whatever the user is doing, and the Mac is never registered as
//  a system call handler — this is a notification surface, not a call client.
//
//  Honest limits shown in the UI: audio stays on the phone, and Answer/Decline are
//  best-effort (the phone needs ANSWER_PHONE_CALLS and a live ringing call).
//
//  Ownership: phone-companion. Trackpad/Glance overlays are separate panels.
//

import AppKit
import SwiftUI

/// Observable model so the panel's SwiftUI content can update in place.
final class CallBannerModel: ObservableObject {
    @Published var snapshot: CallCenter.Snapshot?
}

final class CallBannerController {

    static let shared = CallBannerController()

    private let model = CallBannerModel()
    private var panel: NSPanel?
    /// A call the user hid manually stays hidden until its state changes.
    private var suppressedKey: String?

    private init() {}

    /// Called by CallCenter on every state change (main thread).
    func update(_ snapshot: CallCenter.Snapshot?) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.update(snapshot) }
            return
        }
        guard let snapshot, !snapshot.isIdle else {
            hide()
            return
        }
        let key = Self.key(for: snapshot)
        if let suppressedKey, suppressedKey == key {
            hide()
            return
        }
        // A new call clears a previous manual dismissal.
        if suppressedKey != key { suppressedKey = nil }
        model.snapshot = snapshot
        show()
    }

    /// User dismissed the banner: hide it without touching the call itself.
    func dismissBanner() {
        if let snapshot = model.snapshot {
            suppressedKey = Self.key(for: snapshot)
        }
        hide()
    }

    private static func key(for snapshot: CallCenter.Snapshot) -> String {
        "\(snapshot.deviceID)|\(Int(snapshot.since.timeIntervalSince1970))|\(snapshot.state)"
    }

    // MARK: - Panel lifecycle

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setContentSize(Self.panelSize)
        position(panel)
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
        model.snapshot = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = false
        panel.contentView = NSHostingView(rootView: CallBannerView(model: model))
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = Self.panelSize
        let origin = NSPoint(
            x: visible.maxX - size.width - 16,
            y: visible.maxY - size.height - 10)
        panel.setFrameOrigin(origin)
    }

    private static let panelSize = NSSize(width: 372, height: 116)
}
