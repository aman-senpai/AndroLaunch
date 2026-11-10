//
//  MenuBarPanelLogicTests.swift
//  CoreLogicTests
//
//  Pure-logic coverage for the glass menu-bar panel: left/right click routing
//  and placement/clamping across screen sizes and menu-bar anchors.
//

import CoreGraphics
import Foundation

private let typicalScreen = CGRect(x: 0, y: 0, width: 1440, height: 875)
private let statusAnchor = CGRect(x: 700, y: 875, width: 32, height: 24)

func runMenuBarPanelLogicTests() {
    menuBarClickRouterTests()
    menuBarPanelGeometryTests()
}

private func menuBarClickRouterTests() {
    suite("MenuBarPanelClickRouter") {
        expect(
            MenuBarPanelClickRouter.action(button: .left, controlPressed: false)
                == .dashboardPanel,
            "left click opens the dashboard panel")
        expect(
            MenuBarPanelClickRouter.action(button: .left, controlPressed: true)
                == .legacyMenu,
            "control-left-click opens the legacy menu")
        expect(
            MenuBarPanelClickRouter.action(button: .right, controlPressed: false)
                == .legacyMenu,
            "right click opens the legacy menu")
        expect(
            MenuBarPanelClickRouter.action(button: .right, controlPressed: true)
                == .legacyMenu,
            "right click with control still opens the legacy menu")
        expect(MenuBarPanelMouseButton.left.rawValue == 0, "left button number")
        expect(MenuBarPanelMouseButton.right.rawValue == 1, "right button number")
    }
}

private func menuBarPanelGeometryTests() {
    suite("MenuBarPanelGeometry") {
        let frame = MenuBarPanelGeometry.frame(
            anchor: statusAnchor, screenFrame: typicalScreen)
        expect(frame.width == 380 && frame.height == 760, "panel keeps its 380x760 size")
        expect(frame.midX == statusAnchor.midX, "panel is centred under the status item")
        expect(frame.maxY <= statusAnchor.minY, "panel opens below the status item")
        expect(
            frame.minY >= typicalScreen.minY + MenuBarPanelGeometry.screenMargin,
            "panel stays inside the visible frame")
        expect(frame.maxY <= typicalScreen.maxY, "panel does not overflow the screen top")

        let leftEdge = MenuBarPanelGeometry.frame(
            anchor: CGRect(x: 0, y: 875, width: 32, height: 24),
            screenFrame: typicalScreen)
        expect(
            leftEdge.minX == MenuBarPanelGeometry.screenMargin,
            "left edge clamps to the screen margin")

        let rightEdge = MenuBarPanelGeometry.frame(
            anchor: CGRect(x: 1410, y: 875, width: 30, height: 24),
            screenFrame: typicalScreen)
        expect(
            rightEdge.maxX == typicalScreen.maxX - MenuBarPanelGeometry.screenMargin,
            "right edge clamps to the screen margin")

        let narrowScreen = CGRect(x: 0, y: 0, width: 320, height: 900)
        let narrowPanel = MenuBarPanelGeometry.frame(
            anchor: CGRect(x: 150, y: 900, width: 30, height: 24),
            screenFrame: narrowScreen)
        expect(narrowPanel.width == 304, "panel shrinks to a narrow screen")
        expect(
            narrowPanel.minX == MenuBarPanelGeometry.screenMargin,
            "shrunk panel is clamped on the narrow screen")

        let shortScreen = CGRect(x: 0, y: 0, width: 1440, height: 500)
        let shortPanel = MenuBarPanelGeometry.frame(
            anchor: CGRect(x: 700, y: 476, width: 32, height: 24),
            screenFrame: shortScreen)
        expect(shortPanel.height == 484, "panel shrinks to a short screen")
        expect(shortPanel.minY == 8, "panel is clamped to the visible frame on a short screen")

        let bottomAnchor = CGRect(x: 700, y: 20, width: 32, height: 24)
        let above = MenuBarPanelGeometry.frame(
            anchor: bottomAnchor, screenFrame: typicalScreen)
        expect(
            above.minY == bottomAnchor.maxY + MenuBarPanelGeometry.anchorGap,
            "panel opens above when there is no room below")

        let transformed = MenuBarPanelGeometry.anchor(
            buttonFrameInWindow: CGRect(x: 6, y: 0, width: 24, height: 24),
            windowFrame: CGRect(x: 700, y: 851, width: 36, height: 24))
        expect(transformed.minX == 706 && transformed.minY == 851, "status anchor converts to screen coordinates")
        expect(transformed.width == 24 && transformed.height == 24, "anchor keeps the button size")

        let zeroScreen = CGRect(x: 0, y: 0, width: 0, height: 0)
        let safe = MenuBarPanelGeometry.frame(anchor: .zero, screenFrame: zeroScreen)
        expect(safe.width >= 1 && safe.height >= 1, "degenerate screen never produces an empty frame")
    }
}
