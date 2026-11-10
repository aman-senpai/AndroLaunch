//
//  TrackpadPanel.swift
//  AndroLaunch
//
//  Window shell for the floating trackpad panel. Owned by platform-extras.
//
//  A non-activating `NSPanel` keeps the panel above normal windows while the user
//  works in another app, without stealing focus from what they are typing in.
//  The panel is movable by its background, joins every Space, and is hidden with
//  `orderOut` so reopening it is instant.
//

import AppKit
import SwiftUI

final class TrackpadPanelWindowController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let model: TrackpadPanelModel
    private let onClose: () -> Void
    private var hosting: NSHostingController<TrackpadPanelView>?

    init(model: TrackpadPanelModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose

        let contentSize = NSSize(width: 320, height: 268)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [
                .titled, .closable, .fullSizeContentView, .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false)
        panel.title = "Trackpad"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.animationBehavior = .utilityWindow
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        if let closeButton = panel.standardWindowButton(.closeButton) {
            closeButton.toolTip = "Close trackpad panel"
        }
        self.panel = panel

        super.init()

        panel.delegate = self
        let hosting = NSHostingController(rootView: TrackpadPanelView(model: model))
        hosting.view.frame = NSRect(origin: .zero, size: contentSize)
        hosting.view.autoresizingMask = [.width, .height]
        panel.contentView = hosting.view
        self.hosting = hosting
        positionNearBottomRight()
    }

    // MARK: - Presentation

    func show() {
        positionNearBottomRightIfOffscreen()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hide() {
        panel.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    // MARK: - Placement

    private func positionNearBottomRight() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.maxX - size.width - 24,
            y: visible.minY + 24)
        panel.setFrameOrigin(origin)
    }

    private func positionNearBottomRightIfOffscreen() {
        let frame = panel.frame
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        guard !onScreen else { return }
        positionNearBottomRight()
    }
}
