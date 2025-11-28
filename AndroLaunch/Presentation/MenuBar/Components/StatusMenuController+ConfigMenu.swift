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
        
        let mirroringHeader = NSMenuItem(title: "Mirroring", action: nil, keyEquivalent: "")
        mirroringHeader.isEnabled = false
        menu.addItem(mirroringHeader)
        
        // Mirroring Size Submenu
        let sizeItem = NSMenuItem(title: "Mirroring Size", action: nil, keyEquivalent: "")
        sizeItem.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right.circle", accessibilityDescription: "Mirroring Size")
        
        let sizeMenu = NSMenu()
        configureMaxSizeMenu(sizeMenu, deviceID: deviceID)
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)
        
        // Frame Rate Submenu
        let fpsItem = NSMenuItem(title: "Frame Rate", action: nil, keyEquivalent: "")
        fpsItem.image = NSImage(systemSymbolName: "speedometer", accessibilityDescription: "Frame Rate")
        let fpsMenu = NSMenu()
        configureFrameRateMenu(fpsMenu, deviceID: deviceID)
        fpsItem.submenu = fpsMenu
        menu.addItem(fpsItem)
        
        // Bit Rate Submenu
        let bitRateItem = NSMenuItem(title: "Bit Rate", action: nil, keyEquivalent: "")
        bitRateItem.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Bit Rate")
        let bitRateMenu = NSMenu()
        configureBitRateMenu(bitRateMenu, deviceID: deviceID)
        bitRateItem.submenu = bitRateMenu
        menu.addItem(bitRateItem)
        
        // Rotation Toggle
        let isCaptureOrientationEnabled = viewModel.isCaptureOrientationEnabled(for: deviceID)
        let captureOrientationItem = NSMenuItem()
        let captureOrientationView = ToggleMenuItemView(
            title: "Rotation",
            icon: isCaptureOrientationEnabled ? "lock.rotation" : "lock.rotation.open",
            isOn: isCaptureOrientationEnabled
        ) { [weak self] isOn in
            self?.viewModel.toggleCaptureOrientation(for: deviceID)
        }
        captureOrientationItem.view = captureOrientationView
        menu.addItem(captureOrientationItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Camera Section
        let cameraHeader = NSMenuItem(title: "Camera", action: nil, keyEquivalent: "")
        cameraHeader.isEnabled = false
        menu.addItem(cameraHeader)
        
        // Camera Facing
        let camFacingItem = NSMenuItem(title: "Camera Facing", action: nil, keyEquivalent: "")
        camFacingItem.image = NSImage(systemSymbolName: "camera.aperture", accessibilityDescription: "Camera Facing")
        let camFacingMenu = NSMenu()
        configureCameraFacingMenu(camFacingMenu, deviceID: deviceID)
        camFacingItem.submenu = camFacingMenu
        menu.addItem(camFacingItem)
        
        // Camera FPS
        let camFPSItem = NSMenuItem(title: "Camera FPS", action: nil, keyEquivalent: "")
        camFPSItem.image = NSImage(systemSymbolName: "speedometer", accessibilityDescription: "Camera FPS")
        let camFPSMenu = NSMenu()
        configureCameraFPSMenu(camFPSMenu, deviceID: deviceID)
        camFPSItem.submenu = camFPSMenu
        menu.addItem(camFPSItem)
        
        // Camera Size
        let camSizeItem = NSMenuItem(title: "Camera Size", action: nil, keyEquivalent: "")
        camSizeItem.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right.circle", accessibilityDescription: "Camera Size")
        let camSizeMenu = NSMenu()
        configureCameraSizeMenu(camSizeMenu, deviceID: deviceID)
        camSizeItem.submenu = camSizeMenu
        menu.addItem(camSizeItem)
        
        // Camera Aspect Ratio
        let camARItem = NSMenuItem(title: "Camera Aspect Ratio", action: nil, keyEquivalent: "")
        camARItem.image = NSImage(systemSymbolName: "aspectratio", accessibilityDescription: "Camera Aspect Ratio")
        let camARMenu = NSMenu()
        configureCameraARMenu(camARMenu, deviceID: deviceID)
        camARItem.submenu = camARMenu
        menu.addItem(camARItem)
        
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
            let item = NSMenuItem()
            let view = SelectableMenuItemView(
                title: "\(res)p",
                isSelected: res == currentResolution
            ) { [weak self] in
                self?.viewModel.setResolution(for: deviceID, resolution: res)
                self?.updateResolutionMenuState(menu, selectedResolution: res)
            }
            item.view = view
            item.representedObject = res // Store resolution for easy access if needed
            menu.addItem(item)
        }
    }
    
    private func updateResolutionMenuState(_ menu: NSMenu, selectedResolution: Int) {
        for item in menu.items {
            if let view = item.view as? SelectableMenuItemView, let res = item.representedObject as? Int {
                view.updateState(isSelected: res == selectedResolution)
            }
        }
    }
    
    // MARK: - Camera Configs
    func configureCameraFacingMenu(_ menu: NSMenu, deviceID: String) {
        let currentFacing = viewModel.getCameraFacing(for: deviceID)
        let options = ["Auto", "Front", "Back", "External"]
        
        for option in options {
            let item = NSMenuItem()
            let view = SelectableMenuItemView(
                title: option,
                isSelected: option == currentFacing
            ) { [weak self] in
                self?.viewModel.setCameraFacing(for: deviceID, facing: option)
                self?.updateCameraFacingMenuState(menu, selectedFacing: option)
            }
            item.view = view
            item.representedObject = option
            menu.addItem(item)
        }
    }
    
    private func updateCameraFacingMenuState(_ menu: NSMenu, selectedFacing: String) {
        for item in menu.items {
            if let view = item.view as? SelectableMenuItemView, let facing = item.representedObject as? String {
                view.updateState(isSelected: facing == selectedFacing)
            }
        }
    }
    
    func configureCameraFPSMenu(_ menu: NSMenu, deviceID: String) {
        let currentFPS = viewModel.getCameraFPS(for: deviceID)
        let options = [0, 30, 60, 120, 240]
        
        for fps in options {
            let title = fps == 0 ? "Default" : "\(fps) fps"
            let item = NSMenuItem()
            let view = SelectableMenuItemView(
                title: title,
                isSelected: fps == currentFPS
            ) { [weak self] in
                self?.viewModel.setCameraFPS(for: deviceID, fps: fps)
                self?.updateCameraFPSMenuState(menu, selectedFPS: fps)
            }
            item.view = view
            item.representedObject = fps
            menu.addItem(item)
        }
    }
    
    private func updateCameraFPSMenuState(_ menu: NSMenu, selectedFPS: Int) {
        for item in menu.items {
            if let view = item.view as? SelectableMenuItemView, let fps = item.representedObject as? Int {
                view.updateState(isSelected: fps == selectedFPS)
            }
        }
    }
    
    func configureCameraSizeMenu(_ menu: NSMenu, deviceID: String) {
        let currentSize = viewModel.getCameraSize(for: deviceID)
        let sizes = [0, 3840, 2560, 1920, 1280, 1024, 800, 640]
        
        for size in sizes {
            var title = ""
            switch size {
            case 0: title = "Original"
            case 3840: title = "3840 (4K)"
            case 2560: title = "2560 (2K)"
            case 1920: title = "1920 (1080p)"
            case 1280: title = "1280 (720p)"
            case 1024: title = "1024"
            case 800: title = "800 (480p)"
            case 640: title = "640 (VGA)"
            default: title = "\(size)"
            }
            
            let item = NSMenuItem()
            let view = SelectableMenuItemView(
                title: title,
                isSelected: size == currentSize
            ) { [weak self] in
                self?.viewModel.setCameraSize(for: deviceID, size: size)
                self?.updateCameraSizeMenuState(menu, selectedSize: size)
            }
            item.view = view
            item.representedObject = size
            menu.addItem(item)
        }
    }
    
    private func updateCameraSizeMenuState(_ menu: NSMenu, selectedSize: Int) {
        for item in menu.items {
            if let view = item.view as? SelectableMenuItemView, let size = item.representedObject as? Int {
                view.updateState(isSelected: size == selectedSize)
            }
        }
    }
    
    func configureCameraARMenu(_ menu: NSMenu, deviceID: String) {
        let currentAR = viewModel.getCameraAR(for: deviceID)
        let options = ["Auto", "4:3", "16:9", "1:1", "sensor"]
        
        for option in options {
            let item = NSMenuItem()
            let view = SelectableMenuItemView(
                title: option == "Auto" ? "Auto" : option,
                isSelected: option == currentAR
            ) { [weak self] in
                self?.viewModel.setCameraAR(for: deviceID, ar: option)
                self?.updateCameraARMenuState(menu, selectedAR: option)
            }
            item.view = view
            item.representedObject = option
            menu.addItem(item)
        }
    }
    
    private func updateCameraARMenuState(_ menu: NSMenu, selectedAR: String) {
        for item in menu.items {
            if let view = item.view as? SelectableMenuItemView, let ar = item.representedObject as? String {
                view.updateState(isSelected: ar == selectedAR)
            }
        }
    }
    
    func configureMaxSizeMenu(_ menu: NSMenu, deviceID: String) {
        let currentSize = viewModel.getMaxSize(for: deviceID)
        // 0 represents "Original"
        let sizes = [0, 800, 1024, 1280, 1440, 1600, 1920]
        
        for size in sizes {
            let title = size == 0 ? "Original" : "\(size)"
            let item = NSMenuItem()
            let view = SelectableMenuItemView(
                title: title,
                isSelected: size == currentSize
            ) { [weak self] in
                self?.viewModel.setMaxSize(for: deviceID, size: size)
                self?.updateMaxSizeMenuState(menu, selectedSize: size)
            }
            item.view = view
            item.representedObject = size
            menu.addItem(item)
        }
    }
    
    private func updateMaxSizeMenuState(_ menu: NSMenu, selectedSize: Int) {
        for item in menu.items {
            if let view = item.view as? SelectableMenuItemView, let size = item.representedObject as? Int {
                view.updateState(isSelected: size == selectedSize)
            }
        }
    }
    
    // MARK: - Frame Rate
    func configureFrameRateMenu(_ menu: NSMenu, deviceID: String) {
        let currentFPS = viewModel.getMaxFPS(for: deviceID)
        let fpsOptions = [0, 30, 60, 90, 120]
        
        for fps in fpsOptions {
            let title = fps == 0 ? "Unlimited" : "\(fps) fps"
            let item = NSMenuItem()
            let view = SelectableMenuItemView(
                title: title,
                isSelected: fps == currentFPS
            ) { [weak self] in
                self?.viewModel.setMaxFPS(for: deviceID, fps: fps)
                self?.updateFrameRateMenuState(menu, selectedFPS: fps)
            }
            item.view = view
            item.representedObject = fps
            menu.addItem(item)
        }
    }
    
    private func updateFrameRateMenuState(_ menu: NSMenu, selectedFPS: Int) {
        for item in menu.items {
            if let view = item.view as? SelectableMenuItemView, let fps = item.representedObject as? Int {
                view.updateState(isSelected: fps == selectedFPS)
            }
        }
    }
    
    // MARK: - Bit Rate
    func configureBitRateMenu(_ menu: NSMenu, deviceID: String) {
        let currentBitRate = viewModel.getBitRate(for: deviceID)
        let bitRates = [2, 4, 8, 16, 20]
        
        for rate in bitRates {
            let title = "\(rate) Mbps"
            let item = NSMenuItem()
            let view = SelectableMenuItemView(
                title: title,
                isSelected: rate == currentBitRate
            ) { [weak self] in
                self?.viewModel.setBitRate(for: deviceID, bitRate: rate)
                self?.updateBitRateMenuState(menu, selectedBitRate: rate)
            }
            item.view = view
            item.representedObject = rate
            menu.addItem(item)
        }
    }
    
    private func updateBitRateMenuState(_ menu: NSMenu, selectedBitRate: Int) {
        for item in menu.items {
            if let view = item.view as? SelectableMenuItemView, let rate = item.representedObject as? Int {
                view.updateState(isSelected: rate == selectedBitRate)
            }
        }
    }
}
