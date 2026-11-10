//
//  DeviceMenuItemView.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 11/29/25.
//

import AppKit

final class DeviceMenuItemView: NSView {
    private let hoverEffectView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .selection
        view.state = .active
        view.blendingMode = .withinWindow
        view.isEmphasized = true
        view.wantsLayer = true
        view.layer?.cornerRadius = 4.0
        view.layer?.masksToBounds = true
        view.alphaValue = 0
        return view
    }()
    
    private let deviceIconView = NSImageView()
    private let nameLabel = NSTextField()
    private let connectionIconView = NSImageView()
    private var trackingArea: NSTrackingArea?
    
    init(deviceName: String, isWireless: Bool) {
        let font = NSFont.menuFont(ofSize: 14)
        let textWidth = MenuRowMetrics.width - MenuRowMetrics.textLeading - 50
        // Long device names wrap to a second line; the row grows, the menu does not.
        let rowHeight = MenuRowMetrics.rowHeight(
            for: deviceName, font: font, lineLimit: 2, width: textWidth)
        super.init(frame: NSRect(x: 0, y: 0, width: MenuRowMetrics.width, height: rowHeight))
        let connectionDescription = isWireless ? "Wireless" : "USB"
        toolTip = "\(deviceName) — \(connectionDescription), authorized and ready"
        setAccessibilityLabel("\(deviceName), \(connectionDescription), ready")
        setAccessibilityHelp("Open this device’s submenu for mirroring, files, apps, and developer tools.")
        
        // Add hover effect view
        addSubview(hoverEffectView)
        
        // Device icon (left)
        // Standard menu item icon alignment is usually around 14-16pt from the edge
        deviceIconView.frame = NSRect(
            x: MenuRowMetrics.leadingInset, y: (rowHeight - 16) / 2, width: 16, height: 16)
        deviceIconView.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "Device")
        deviceIconView.contentTintColor = .controlTextColor
        addSubview(deviceIconView)
        
        // Device name (center)
        nameLabel.stringValue = deviceName
        nameLabel.font = font
        nameLabel.textColor = .controlTextColor
        nameLabel.lineBreakMode = .byWordWrapping
        nameLabel.maximumNumberOfLines = 2
        nameLabel.usesSingleLineMode = false
        nameLabel.allowsDefaultTighteningForTruncation = true
        nameLabel.cell?.wraps = true
        nameLabel.cell?.truncatesLastVisibleLine = true
        nameLabel.frame = NSRect(
            x: MenuRowMetrics.textLeading, y: 0, width: textWidth, height: rowHeight)
        nameLabel.drawsBackground = false
        nameLabel.isBordered = false
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        addSubview(nameLabel)
        
        // Connection type indicator (right)
        connectionIconView.frame = NSRect(
            x: MenuRowMetrics.width - 45, y: (rowHeight - 16) / 2, width: 16, height: 16)
        let connectionIcon = isWireless ? "wifi" : "cable.connector"
        connectionIconView.image = NSImage(systemSymbolName: connectionIcon, accessibilityDescription: isWireless ? "Wireless" : "USB")
        connectionIconView.contentTintColor = .tertiaryLabelColor
        addSubview(connectionIconView)
        
        // Arrow indicator (far right)
        let arrowIconView = NSImageView(
            frame: NSRect(x: MenuRowMetrics.width - 24, y: (rowHeight - 14) / 2, width: 12, height: 14))
        arrowIconView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Details")
        arrowIconView.contentTintColor = .tertiaryLabelColor
        addSubview(arrowIconView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        hoverEffectView.frame = bounds.insetBy(dx: 4, dy: 0)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        animateHover(visible: true)
    }
    
    override func mouseExited(with event: NSEvent) {
        animateHover(visible: false)
    }
    
    /// Clears the custom hover overlay without animation. Called when the menu opens
    /// so a selection painted before the menu closed never survives into the next open.
    func resetHover() {
        hoverEffectView.alphaValue = 0
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            resetHover()
        }
    }

    private func animateHover(visible: Bool) {
        if visible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.05
                hoverEffectView.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                hoverEffectView.animator().alphaValue = 0
            }
        }
    }
}
