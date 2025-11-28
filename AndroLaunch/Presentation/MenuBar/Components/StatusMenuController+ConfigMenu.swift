//
//  StatusMenuController+ConfigMenu.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 11/29/25.
//

import AppKit

extension StatusMenuController {
    
    func configureConfigMenu(_ menu: NSMenu, deviceID: String) {
        menu.removeAllItems()
        
        // Resolution Submenu
        let resItem = NSMenuItem(title: "App Resolution", action: nil, keyEquivalent: "")
        resItem.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Resolution")
        
        let resMenu = NSMenu()
        configureResolutionMenu(resMenu, deviceID: deviceID)
        resItem.submenu = resMenu
        menu.addItem(resItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem.separator())
        
        // Audio Forwarding
        let isAudioEnabled = viewModel.isAudioEnabled(for: deviceID)
        let audioItem = NSMenuItem()
        let audioView = ToggleMenuItemView(
            title: "Audio Forwarding",
            icon: isAudioEnabled ? "speaker.wave.2" : "speaker.slash",
            isOn: isAudioEnabled
        ) { [weak self] isOn in
            self?.viewModel.toggleAudio(for: deviceID)
        }
        audioItem.view = audioView
        menu.addItem(audioItem)
        
        // Clipboard Sync
        let isClipboardEnabled = viewModel.isClipboardEnabled(for: deviceID)
        let clipboardItem = NSMenuItem()
        let clipboardView = ToggleMenuItemView(
            title: "Clipboard Sync",
            icon: "doc.on.clipboard",
            isOn: isClipboardEnabled
        ) { [weak self] isOn in
            self?.viewModel.toggleClipboard(for: deviceID)
        }
        clipboardItem.view = clipboardView
        menu.addItem(clipboardItem)
    }
    
    func configureResolutionMenu(_ menu: NSMenu, deviceID: String) {
        let currentResolution = viewModel.getResolution(for: deviceID)
        let resolutions = [360, 540, 720, 900, 1080, 1440, 1600]
        
        for res in resolutions {
            let item = NSMenuItem(title: "\(res)p", action: #selector(changeResolution(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = deviceID
            item.tag = res
            item.state = (res == currentResolution) ? .on : .off
            item.onStateImage = NSImage(systemSymbolName: "smallcircle.fill.circle", accessibilityDescription: "Selected")
            item.offStateImage = NSImage(systemSymbolName: "circle", accessibilityDescription: "Unselected")
            menu.addItem(item)
        }
    }
    
    @objc func changeResolution(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        let resolution = sender.tag
        viewModel.setResolution(for: deviceID, resolution: resolution)
        
        // Update checkmarks
        if let menu = sender.menu {
            for item in menu.items {
                item.state = (item.tag == resolution) ? .on : .off
            }
        }
    }
}
