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
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 20))
        
        // Add hover effect view
        addSubview(hoverEffectView)
        
        // Device icon (left)
        // Standard menu item icon alignment is usually around 14-16pt from the edge
        deviceIconView.frame = NSRect(x: 14, y: 2, width: 16, height: 16)
        deviceIconView.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "Device")
        deviceIconView.contentTintColor = .controlTextColor
        addSubview(deviceIconView)
        
        // Device name (center)
        nameLabel.stringValue = deviceName
        nameLabel.font = NSFont.menuFont(ofSize: 14)
        nameLabel.textColor = .controlTextColor
        nameLabel.frame = NSRect(x: 38, y: 2, width: 160, height: 16)
        nameLabel.drawsBackground = false
        nameLabel.isBordered = false
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        addSubview(nameLabel)
        
        // Connection type indicator (right)
        connectionIconView.frame = NSRect(x: 205, y: 2, width: 16, height: 16)
        let connectionIcon = isWireless ? "wifi" : "cable.connector"
        connectionIconView.image = NSImage(systemSymbolName: connectionIcon, accessibilityDescription: isWireless ? "Wireless" : "USB")
        connectionIconView.contentTintColor = .tertiaryLabelColor
        addSubview(connectionIconView)
        
        // Arrow indicator (far right)
        let arrowIconView = NSImageView(frame: NSRect(x: 226, y: 3, width: 12, height: 14))
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
