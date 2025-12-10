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
    
    @objc func mirrorDevice(_ sender: Any) {
        var deviceID: String?
        
        if let deviceButton = sender as? DeviceActionButton {
            deviceID = deviceButton.deviceID
        } else if let menuItem = sender as? NSMenuItem, let id = menuItem.representedObject as? String {
            deviceID = id
        }
        
        if let deviceID = deviceID {
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
    
    // MARK: - Shell Command Actions
    
    @objc func manageShellCommands(_ sender: NSMenuItem) {
        if manageCommandsWindow == nil {
            let manageView = ManageCommandsView(viewModel: viewModel)
            let hostingController = NSHostingController(rootView: manageView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Shell Commands"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.center()
            window.isReleasedWhenClosed = false
            self.manageCommandsWindow = window
        }
        
        manageCommandsWindow?.center() // Center again to be sure
        manageCommandsWindow?.makeKeyAndOrderFront(nil)
        manageCommandsWindow?.orderFrontRegardless()
        
        // Force app activation - using standard API
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func executeSavedShellCommand(_ sender: NSMenuItem) {
        // representedObject should be the wrapper
        guard let wrapper = sender.representedObject as? ShellCommandWrapper else { return }
        let command = wrapper.command
        let deviceID = wrapper.deviceID
        
        if command.isHostCommand {
            // Host Command Logic (e.g. adb install ...)
            // We need to inject the device ID into the command
            
            // Default ADB path
            var adbPath = "adb"
            if let path = viewModel.adbPath {
                adbPath = path
            }
            
            // Replace "adb " with "adb -s DEVICE_ID "
            // We use simple string replacement, assuming user types "adb"
            // Better would be regex, but for now simple replacement works for standard cases
            
            let targetedADB = "\(adbPath) -s \(deviceID)"
            let processedCommand = command.command.replacingOccurrences(of: "adb ", with: "\(targetedADB) ")
            
            // If the command starts with "adb", replace that too if not caught by space
            let finalCommand: String
            if processedCommand.hasPrefix("adb") && !processedCommand.hasPrefix("adb ") {
                 // "adb" without space? unlikely for valid command but safe to handle
                 finalCommand = processedCommand.replacingOccurrences(of: "adb", with: targetedADB)
            } else {
                 finalCommand = processedCommand
            }
            
            if command.isBackground {
                 viewModel.runHostShellCommand(finalCommand)
            } else {
                 launchHostTerminalCommand(command: finalCommand, title: command.name)
            }
            
        } else {
            // Standard Device Shell (adb shell ...)
            if command.isBackground {
                viewModel.runBackgroundShellCommand(command.command, for: deviceID)
            } else {
                launchSpecificShellCommand(deviceID: deviceID, command: command.command, title: command.name)
            }
        }
    }
    
    private func launchSpecificShellCommand(deviceID: String, command: String, title: String) {
        // ... existing implementation ...
        print("DEBUG: Launching specific shell command for device: \(deviceID)")
        
        // ... (rest of existing method)
        // Ensure this content matches exactly what is in the file or just append the new function if possible with sufficient context
        // Since I'm using replace_file_content, I'll target the end of the previous function to append.
        
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            let fileName = "\(title).command"
            let fileURL = tempDir.appendingPathComponent(fileName)
            
            var adbDir = "$HOME/Library/Android/sdk/platform-tools"
            if let adbPath = self.viewModel.adbPath {
                let url = URL(fileURLWithPath: adbPath)
                adbDir = url.deletingLastPathComponent().path
            }
            
            let scriptContent = """
            #!/bin/bash
            clear
            echo -n -e "\\033]0;ADB Shell - \(deviceID) - \(title)\\007"
            
            echo "Device: \(deviceID)"
            echo "Command: \(command)"
            echo "----------------------------------------"
            export PATH=$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(adbDir)
            
            if ! command -v adb &> /dev/null; then
                echo "Error: adb not found."
                read -n 1 -s -r -p "Press any key to close..."
                exit 1
            fi
            
            adb -s \(deviceID) shell "\(command)"
            
            echo "----------------------------------------"
            echo "Command finished."
            read -n 1 -s -r -p "Press any key to close..."
            """
            
            try scriptContent.write(to: fileURL, atomically: true, encoding: .utf8)
            let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
            try fileManager.setAttributes(attributes, ofItemAtPath: fileURL.path)
            
            NSWorkspace.shared.open(fileURL)
        } catch {
            print("ERROR: Failed to launch command: \(error)")
        }
    }

    private func launchHostTerminalCommand(command: String, title: String) {
        print("DEBUG: Launching host terminal command: \(command)")
        
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            let fileName = "\(title).command"
            let fileURL = tempDir.appendingPathComponent(fileName)
            
            var adbDir = "$HOME/Library/Android/sdk/platform-tools"
            if let adbPath = self.viewModel.adbPath {
                let url = URL(fileURLWithPath: adbPath)
                adbDir = url.deletingLastPathComponent().path
            }
            
            let scriptContent = """
            #!/bin/bash
            clear
            echo -n -e "\\033]0;Host Command - \(title)\\007"
            
            echo "Executing: \(command)"
            echo "----------------------------------------"
            export PATH=$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(adbDir)
            
            # Execute directly
            \(command)
            
            echo "----------------------------------------"
            echo "Command finished."
            read -n 1 -s -r -p "Press any key to close..."
            """
            
            try scriptContent.write(to: fileURL, atomically: true, encoding: .utf8)
            let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
            try fileManager.setAttributes(attributes, ofItemAtPath: fileURL.path)
            
            NSWorkspace.shared.open(fileURL)
        } catch {
            print("ERROR: Failed to launch host command: \(error)")
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
