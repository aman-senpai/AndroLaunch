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
    
    init(deviceID: String, isWireless: Bool, target: AnyObject, mirrorCameraAction: Selector, installAction: Selector, shellAction: Selector, logcatAction: Selector, disconnectAction: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 44))
        
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
        let mirrorCamBtn = config(createButton(imageName: "camera", tooltip: "Mirror Camera", target: target, action: mirrorCameraAction, deviceID: deviceID))
        let installBtn = config(createButton(imageName: "shippingbox", tooltip: "Install APK", target: target, action: installAction, deviceID: deviceID))
        let shellBtn = config(createButton(imageName: "terminal", tooltip: "Open ADB Shell", target: target, action: shellAction, deviceID: deviceID))
        let logcatBtn = config(createButton(imageName: "pawprint.fill", tooltip: "Open Logcat", target: target, action: logcatAction, deviceID: deviceID))
        
        var disconnectBtn: NSButton?
        if isWireless {
            disconnectBtn = config(createButton(imageName: "wifi.slash", tooltip: "Disconnect Device", target: target, action: disconnectAction, deviceID: deviceID))
        }
        
        // Grid Layout
        let gridView = NSGridView(views: [
            [mirrorCamBtn, installBtn, shellBtn, logcatBtn, disconnectBtn ?? NSGridCell.emptyContentView]
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
