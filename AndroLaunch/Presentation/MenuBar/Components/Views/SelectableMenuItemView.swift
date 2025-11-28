//
//  SelectableMenuItemView.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 11/29/25.
//

import AppKit

final class SelectableMenuItemView: NSView {
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
    
    private let checkIconView = NSImageView()
    private let titleLabel = NSTextField()
    private var trackingArea: NSTrackingArea?
    
    var onSelect: (() -> Void)?
    
    init(title: String, isSelected: Bool, onSelect: @escaping () -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        self.onSelect = onSelect
        
        // Add hover effect view
        addSubview(hoverEffectView)
        
        // Check Icon (Left)
        checkIconView.frame = NSRect(x: 10, y: 3, width: 16, height: 16)
        checkIconView.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Selected")
        checkIconView.contentTintColor = .labelColor
        checkIconView.isHidden = !isSelected
        addSubview(checkIconView)
        
        // Title (Right of icon)
        titleLabel.stringValue = title
        titleLabel.font = NSFont.menuFont(ofSize: 14)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 34, y: 3, width: 160, height: 16)
        titleLabel.drawsBackground = false
        titleLabel.isBordered = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        addSubview(titleLabel)
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
    
    override func mouseUp(with event: NSEvent) {
        // Trigger selection
        onSelect?()
        
        // Do NOT call super.mouseUp or anything that propagates to the menu item to close it
    }
    
    private func animateHover(visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.05
            hoverEffectView.animator().alphaValue = visible ? 1 : 0
        }
    }
    
    func updateState(isSelected: Bool) {
        checkIconView.isHidden = !isSelected
    }
}
