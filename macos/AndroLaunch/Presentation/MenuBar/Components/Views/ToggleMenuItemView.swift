//
//  ToggleMenuItemView.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 11/29/25.
//

import AppKit

class ToggleMenuItemView: NSView {
    private let titleLabel = NSTextField()
    private let toggleSwitch = NSSwitch()
    private let iconView = NSImageView()
    
    var onToggle: ((Bool) -> Void)?
    
    init(title: String, icon: String, isOn: Bool, onToggle: @escaping (Bool) -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 26))
        self.onToggle = onToggle
        
        // Icon
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        iconView.contentTintColor = .labelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        
        // Title
        titleLabel.stringValue = title
        titleLabel.font = NSFont.menuFont(ofSize: 14)
        titleLabel.textColor = .labelColor
        titleLabel.drawsBackground = false
        titleLabel.isBordered = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        // Switch
        toggleSwitch.state = isOn ? .on : .off
        toggleSwitch.controlSize = .mini
        toggleSwitch.target = self
        toggleSwitch.action = #selector(switchToggled(_:))
        toggleSwitch.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toggleSwitch)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            toggleSwitch.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            toggleSwitch.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    @objc private func switchToggled(_ sender: NSSwitch) {
        onToggle?(sender.state == .on)
    }
}
