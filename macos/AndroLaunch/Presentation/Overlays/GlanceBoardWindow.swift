//
//  GlanceBoardWindow.swift
//  AndroLaunch
//
//  Window shell for the Glance desktop board. Owned by platform-extras.
//
//  A regular-level floating `NSPanel` (transparent, rounded, no titlebar chrome)
//  so the board sits on the desktop like a widget without stealing focus from the
//  app the user is working in. WidgetKit is documented as future work.
//

import AppKit
import Combine
import SwiftUI

final class GlanceBoardPanelWindowController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let model: GlanceBoardModel
    private let onClose: () -> Void
    private var hosting: NSHostingController<GlanceBoardView>?
    private var cancellables = Set<AnyCancellable>()

    private static let contentSize = NSSize(width: 320, height: 400)

    init(model: GlanceBoardModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [
                .titled, .closable, .fullSizeContentView, .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false)
        panel.title = "Glance"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        self.panel = panel

        super.init()

        panel.delegate = self
        let hosting = NSHostingController(rootView: GlanceBoardView(model: model))
        hosting.view.frame = NSRect(origin: .zero, size: Self.contentSize)
        hosting.view.autoresizingMask = [.width, .height]
        hosting.view.wantsLayer = true
        hosting.view.layer?.cornerRadius = 16
        hosting.view.layer?.masksToBounds = true
        panel.contentView = hosting.view
        self.hosting = hosting

        // Follow the board's state so the rounded content fills the window.
        model.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.resizeToFit() }
            .store(in: &cancellables)

        positionNearTopRight()
    }

    // MARK: - Presentation

    func show() {
        panel.orderFrontRegardless()
        positionNearTopRightIfOffscreen()
        DispatchQueue.main.async { [weak self] in self?.resizeToFit() }
    }

    func hide() {
        panel.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    // MARK: - Layout

    private func resizeToFit() {
        // The board has a stable width; content height varies between the
        // connected layout and the empty state. Clamp so a long device name can
        // never make the panel taller than a comfortable desktop tile.
        guard let hosting else { return }
        hosting.view.frame.size.width = Self.contentSize.width
        let fitting = hosting.view.fittingSize
        let height = min(480, max(320, fitting.height))
        guard abs(panel.frame.height - height) > 1 else { return }
        panel.setContentSize(NSSize(width: Self.contentSize.width, height: height))
    }

    // MARK: - Placement

    private func positionNearTopRight() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.maxX - size.width - 24,
            y: visible.maxY - size.height - 24)
        panel.setFrameOrigin(origin)
    }

    private func positionNearTopRightIfOffscreen() {
        let frame = panel.frame
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        guard !onScreen else { return }
        positionNearTopRight()
    }
}
