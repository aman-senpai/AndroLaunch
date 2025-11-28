//
//  ControlsMenuItemView.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 11/29/25.
//

import AppKit

class DeviceActionButton: NSButton {
    var deviceID: String?
}

final class ControlsMenuItemView: NSView {
    
    init(deviceID: String, isWireless: Bool, target: AnyObject, frontCamAction: Selector, backCamAction: Selector, mirrorAction: Selector, installAction: Selector, shellAction: Selector, disconnectAction: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 44)) // Reduced height
        
        // Helper to configure button size
        func config(_ btn: NSButton) -> NSButton {
            btn.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(equalToConstant: 28),
                btn.heightAnchor.constraint(equalToConstant: 28)
            ])
            return btn
        }
        
        // Buttons
        let mirrorBtn = config(createButton(imageName: "display", tooltip: "Mirror Device", target: target, action: mirrorAction, deviceID: deviceID))
        let installBtn = config(createButton(imageName: "shippingbox", tooltip: "Install APK", target: target, action: installAction, deviceID: deviceID))
        let shellBtn = config(createButton(imageName: "terminal", tooltip: "Open ADB Shell", target: target, action: shellAction, deviceID: deviceID))
        
        let frontCamBtn = config(createButton(imageName: "person.fill.viewfinder", tooltip: "Front Camera", target: target, action: frontCamAction, deviceID: deviceID))
        let backCamBtn = config(createButton(imageName: "camera", tooltip: "Back Camera", target: target, action: backCamAction, deviceID: deviceID))
        
        var disconnectBtn: NSButton?
        if isWireless {
            disconnectBtn = config(createButton(imageName: "wifi.slash", tooltip: "Disconnect Device", target: target, action: disconnectAction, deviceID: deviceID))
        }
        
        // Grid Layout
        let gridView = NSGridView(views: [
            [mirrorBtn, installBtn, shellBtn, frontCamBtn, backCamBtn, disconnectBtn ?? NSGridCell.emptyContentView]
        ])
        
        gridView.translatesAutoresizingMaskIntoConstraints = false
        gridView.columnSpacing = 12
        gridView.rowSpacing = 0
        gridView.xPlacement = .center
        gridView.yPlacement = .center
        
        addSubview(gridView)
        
        NSLayoutConstraint.activate([
            gridView.centerXAnchor.constraint(equalTo: centerXAnchor),
            gridView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func createButton(imageName: String, tooltip: String, target: AnyObject, action: Selector, deviceID: String) -> NSButton {
        let btn = DeviceActionButton()
        btn.deviceID = deviceID
        btn.bezelStyle = .inline
        btn.image = NSImage(systemSymbolName: imageName, accessibilityDescription: tooltip)
        btn.image?.size = NSSize(width: 14, height: 14)
        btn.toolTip = tooltip
        btn.target = target
        btn.action = action
        btn.isBordered = false
        return btn
    }
}
