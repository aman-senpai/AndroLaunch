//
//  StatusMenuController+Actions.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 11/29/25.
//

import AppKit
import SwiftUI

extension StatusMenuController {
    
    @objc func refreshDevices() {
        viewModel.refresh()
        currentDeviceID = nil
    }
    
    @objc func refreshApps(_ sender: NSButton) {
        // Use custom button class or check sender
        if let refreshButton = sender as? DeviceActionButton, let deviceID = refreshButton.deviceID {
             currentDeviceID = deviceID
             viewModel.forceRefreshApps(for: deviceID)
             // Do NOT cancel tracking to keep menu open
        }
    }
    
    @objc func mirrorDevice(_ sender: NSButton) {
        if let deviceButton = sender as? DeviceActionButton, let deviceID = deviceButton.deviceID {
             viewModel.mirrorDevice(deviceID: deviceID)
             if let menu = statusItem.menu { menu.cancelTracking() }
        }
    }
    
    @objc func disconnectDevice(_ sender: NSButton) {
        if let deviceButton = sender as? DeviceActionButton, let deviceID = deviceButton.deviceID {
            viewModel.disconnectDevice(deviceID: deviceID)
            if let menu = statusItem.menu { menu.cancelTracking() }
        }
    }
    
    @objc func installAPK(_ sender: NSButton) {
        if let deviceButton = sender as? DeviceActionButton, let deviceID = deviceButton.deviceID {
            let openPanel = NSOpenPanel()
            openPanel.title = "Select APK to Install"
            openPanel.showsHiddenFiles = false
            openPanel.canChooseDirectories = false
            openPanel.canCreateDirectories = false
            openPanel.allowsMultipleSelection = false
            openPanel.allowedContentTypes = [.init(filenameExtension: "apk")!]
            
            // Bring open panel to front
            NSApp.activate(ignoringOtherApps: true)
            
            openPanel.begin { [weak self] (result) in
                if result == .OK {
                    if let url = openPanel.url {
                        self?.viewModel.installAPK(deviceID: deviceID, apkPath: url.path)
                        // Close menu after selection
                        if let menu = self?.statusItem.menu { menu.cancelTracking() }
                    }
                }
            }
        }
    }
    
    @objc func launchShell(_ sender: NSButton) {
        if let deviceButton = sender as? DeviceActionButton, let deviceID = deviceButton.deviceID {
            
            print("DEBUG: Launching shell for device: \(deviceID)")
            
            // Create a temporary .command file to launch the shell
            let fileManager = FileManager.default
            let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            
            do {
                try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
                let fileName = "ADB Shell.command"
                let fileURL = tempDir.appendingPathComponent(fileName)
                
                // Determine ADB directory
                var adbDir = "$HOME/Library/Android/sdk/platform-tools" // Default fallback
                if let adbPath = self.viewModel.adbPath {
                    let url = URL(fileURLWithPath: adbPath)
                    adbDir = url.deletingLastPathComponent().path
                }
                
                let scriptContent = """
                #!/bin/bash
                clear
                # Set window title
                echo -n -e "\\033]0;ADB Shell - \(deviceID)\\007"
                
                echo "Starting ADB Shell for device: \(deviceID)"
                export PATH=$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(adbDir)
                
                # Check if adb is available
                if ! command -v adb &> /dev/null; then
                    echo "Error: adb not found in PATH."
                    echo "PATH is: $PATH"
                    read -n 1 -s -r -p "Press any key to close..."
                    exit 1
                fi
                
                adb -s \(deviceID) shell
                
                # Keep window open if shell exits unexpectedly
                if [ $? -ne 0 ]; then
                    echo "ADB shell exited with error."
                    read -n 1 -s -r -p "Press any key to close..."
                fi
                """
                
                try scriptContent.write(to: fileURL, atomically: true, encoding: .utf8)
                
                // Make executable
                let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
                try fileManager.setAttributes(attributes, ofItemAtPath: fileURL.path)
                
                // Open with Terminal
                NSWorkspace.shared.open(fileURL)
                print("DEBUG: Opened command file at \(fileURL.path)")
            } catch {
                print("ERROR: Failed to create or open command file: \(error)")
            }
            
            if let menu = statusItem.menu { menu.cancelTracking() }
        }
    }
    
    @objc func mirrorCamera(_ sender: NSButton) {
        if let deviceButton = sender as? DeviceActionButton, let deviceID = deviceButton.deviceID {
            viewModel.mirrorCamera(deviceID: deviceID)
            if let menu = statusItem.menu { menu.cancelTracking() }
        }
    }
    
    @objc func openGitHub() {
        if let url = URL(string: "https://github.com/aman-senpai/AndroLaunch") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func pairDeviceWirelessly() {
        if pairingWindow == nil {
            let pairingView = PairingView()
            let hostingController = NSHostingController(rootView: pairingView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Pair Device"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.center()
            window.isReleasedWhenClosed = false
            
            self.pairingWindow = window
        }
        
        pairingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func toggleAudio(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleAudio(for: deviceID)
        // Update menu item state
        sender.state = viewModel.isAudioEnabled(for: deviceID) ? .on : .off
    }
    
    @objc func toggleClipboard(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        viewModel.toggleClipboard(for: deviceID)
        // Update menu item state
        sender.state = viewModel.isClipboardEnabled(for: deviceID) ? .on : .off
    }
}
