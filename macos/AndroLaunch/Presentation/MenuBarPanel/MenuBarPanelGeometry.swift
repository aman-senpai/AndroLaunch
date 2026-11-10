//
//  MenuBarPanelGeometry.swift
//  AndroLaunch
//
//  Foundation/CoreGraphics-only placement rules for the menu-bar dashboard
//  panel. Keeping this pure means the clamp rules (multi-monitor, menu-bar
//  screens, narrow displays) can be tested without a window server.
//

import CoreGraphics

/// Which affordance a click on the status item opens.
enum MenuBarStatusItemAction: Equatable {
    case dashboardPanel
    case legacyMenu
}

enum MenuBarPanelMouseButton: Int {
    case left = 0
    case right = 1
}

enum MenuBarPanelClickRouter {
    /// Right-click (button 1) and Control-left-click both open the legacy menu;
    /// a normal left click opens the dashboard panel.
    static func action(button: MenuBarPanelMouseButton, controlPressed: Bool) -> MenuBarStatusItemAction {
        if button == .right || controlPressed { return .legacyMenu }
        return .dashboardPanel
    }
}

struct MenuBarPanelGeometry {
    static let panelWidth: CGFloat = 380
    static let panelHeight: CGFloat = 760
    /// Viewport left for the dashboard's scrolling content in the fixed panel:
    /// panel height minus the header, tab bar, divider and footer. Used only by
    /// the ImageRenderer preview path, which cannot lay out a ScrollView.
    static let panelContentHeight: CGFloat = 548
    static let screenMargin: CGFloat = 8
    static let anchorGap: CGFloat = 6

    /// Frame for the panel in screen coordinates.
    ///
    /// - Centres the panel under the status item and clamps it into the active
    ///   screen's visible frame.
    /// - Opens above the status item only when there is no room below (e.g. a
    ///   very short display), otherwise always below.
    /// - Shrinks to the visible frame when the screen is smaller than 380x760.
    static func frame(
        panelSize: CGSize = CGSize(width: panelWidth, height: panelHeight),
        anchor: CGRect,
        screenFrame: CGRect,
        margin: CGFloat = screenMargin,
        gap: CGFloat = anchorGap
    ) -> CGRect {
        let availableWidth = max(1, screenFrame.width - margin * 2)
        let availableHeight = max(1, screenFrame.height - margin * 2)
        let width = min(panelSize.width, availableWidth)
        let height = min(panelSize.height, availableHeight)

        let minX = screenFrame.minX + margin
        let maxX = screenFrame.maxX - margin - width
        let x = clamp(anchor.midX - width / 2, lower: minX, upper: max(minX, maxX))

        let minY = screenFrame.minY + margin
        let maxY = screenFrame.maxY - margin - height
        var y = anchor.minY - gap - height
        if y < minY {
            let above = anchor.maxY + gap
            if above + height <= screenFrame.maxY - margin {
                y = above
            } else {
                y = minY
            }
        }
        y = clamp(y, lower: minY, upper: max(minY, maxY))

        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Anchor rectangle for a status-item button, in screen coordinates.
    static func anchor(
        buttonFrameInWindow: CGRect, windowFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: windowFrame.minX + buttonFrameInWindow.minX,
            y: windowFrame.minY + buttonFrameInWindow.minY,
            width: buttonFrameInWindow.width,
            height: buttonFrameInWindow.height)
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
