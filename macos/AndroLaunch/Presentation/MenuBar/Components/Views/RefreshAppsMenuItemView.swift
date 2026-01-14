//
//  RefreshAppsMenuItemView.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 11/29/25.
//

import AppKit

class RefreshAppsMenuItemView: NSView {
    private let button: DeviceActionButton
    
    init(deviceID: String, target: AnyObject?, action: Selector) {
        self.button = DeviceActionButton(
            image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")!,
            target: target,
            action: action
        )
        self.button.deviceID = deviceID
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        setupView()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func setupView() {
        // Configure Button to look like a menu item row
        button.title = "Refresh Apps"
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.font = NSFont.systemFont(ofSize: 13)
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .labelColor
        
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        
        NSLayoutConstraint.activate([
            // Fill the view with padding similar to standard menu items
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14), // Standard menu padding
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
}
