//
//  PreferencesView.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var viewModel: PreferencesViewModel
    @ObservedObject private var notificationMirror = NotificationMirror.shared
    @State private var toolStatuses: [ToolStatus] = []
    @State private var isCheckingTools = false

    @AppStorage("show_developer_settings") private var showDeveloperSettings = false
    struct ToolStatus: Identifiable {
        let id = UUID()
        let name: String
        let path: String
        let found: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label(
                    viewModel.adbStatus == "Connected" ? "Device connection tools are ready" : "Device connection tools need attention",
                    systemImage: viewModel.adbStatus == "Connected" ? "checkmark.circle" : "exclamationmark.triangle"
                )
                .font(.headline)
                .accessibilityValue(viewModel.adbStatus)

                Text("Tool readiness is not a device connection. Connect and authorize a device before using its actions in the menu bar.")
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox("Connect a device") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. On Android, enable Developer options and USB debugging.")
                        Text("2. Connect a data-capable USB cable and unlock the device.")
                        Text("3. Approve “Allow USB debugging?” on Android, then choose Refresh Devices in the menu bar.")
                        Text("Once the device appears, choose Mirror Screen or Browse Files. Wireless pairing is available separately for Android 11 and later.")
                            .foregroundColor(.secondary)
                    }
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                Button("Recheck Connection Tools") {
                    viewModel.checkAdbStatus()
                    checkTools()
                }
                .help("Checks ADB availability. Refresh Devices in the menu bar to discover authorized devices.")
                .disabled(isCheckingTools)

                GroupBox("Clipboard privacy") {
                    Text("Text sharing is off by default and enabled per device. Android to Mac uses scrcpy. Mac to Android uses AndroLaunch Comp, which installs from the Clipboard menu over ADB. Every enabled device may receive sensitive text copied on this Mac.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }

                GroupBox("Notifications") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Mirror Android notifications", isOn: Binding(
                            get: { notificationMirror.masterEnabled },
                            set: { notificationMirror.setMasterEnabled($0) }
                        ))
                        .accessibilityValue(notificationMirror.masterEnabled ? "On" : "Off")
                        .help("Nothing is mirrored until you also enable it for a device in the Notifications menu.")

                        Toggle("Hide sensitive apps", isOn: Binding(
                            get: { notificationMirror.hideSensitiveApps },
                            set: { notificationMirror.setHideSensitiveApps($0) }
                        ))
                        .help("Keeps banking, finance, password managers, authenticators and email off this Mac. On by default.")

                        Text("Notification text is read over ADB only while mirroring is enabled for a connected device. Banking, finance, password-manager, authenticator and email apps are hidden by default; media and ongoing notifications are ignored. Nothing is sent off this Mac.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                DisclosureGroup("Developer Settings", isExpanded: $showDeveloperSettings) {
                    developerSettings
                        .padding(.top, 12)
                }
                .help("Optional Android SDK paths and diagnostics for emulator management. Not required for everyday device mirroring.")
            }
            .padding(24)
        }
        .frame(minWidth: 500, idealWidth: 560, minHeight: 460, idealHeight: 600)
        .onAppear {
            viewModel.checkAdbStatus()
            checkTools()
        }
    }

    private var developerSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Android SDK Command-Line Tools")
                .font(.headline)
            Text("These optional tools are used by Emulator Manager. ADB and scrcpy are discovered separately.")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                TextField("Path to cmdline-tools/latest/bin", text: Binding(
                    get: { viewModel.commandLineToolsPath },
                    set: {
                        viewModel.commandLineToolsPath = $0
                        checkTools()
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Android SDK command-line tools directory")
                .help("Choose the bin directory containing sdkmanager and avdmanager.")
                Button("Browse…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.title = "Choose Android SDK Command-Line Tools Directory"
                    if panel.runModal() == .OK, let url = panel.url {
                        viewModel.commandLineToolsPath = url.path
                        checkTools()
                    }
                }
                .help("Choose the Android SDK command-line tools directory.")
            }

            ForEach(toolStatuses) { tool in
                VStack(alignment: .leading, spacing: 3) {
                    Label("\(tool.name): \(tool.found ? "Available" : "Not found")",
                          systemImage: tool.found ? "checkmark.circle" : "exclamationmark.triangle")
                    Text(tool.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Button("Auto-Detect SDK") {
                    if let detected = AppConstants.detectCmdlineToolsPath() {
                        viewModel.commandLineToolsPath = detected
                    }
                    checkTools()
                }
                Button("Check Tools") { checkTools() }
                    .disabled(isCheckingTools)
                if isCheckingTools {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Checking developer tools")
                }
            }

            Text("Install Android SDK Command-Line Tools from Android Studio or with Homebrew: brew install --cask android-commandlinetools. The usual directory is ~/Library/Android/sdk/cmdline-tools/latest/bin. Emulator Manager contains advanced SDK and virtual-device settings.")
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func checkTools() {
        isCheckingTools = true
        let toolsPath = viewModel.commandLineToolsPath

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default

            let statuses: [ToolStatus] = [
                ToolStatus(
                    name: "sdkmanager",
                    path: (toolsPath as NSString).appendingPathComponent("sdkmanager"),
                    found: fm.isExecutableFile(
                        atPath: (toolsPath as NSString).appendingPathComponent("sdkmanager"))
                ),
                ToolStatus(
                    name: "avdmanager",
                    path: (toolsPath as NSString).appendingPathComponent("avdmanager"),
                    found: fm.isExecutableFile(
                        atPath: (toolsPath as NSString).appendingPathComponent("avdmanager"))
                ),
                ToolStatus(
                    name: "adb",
                    path: viewModel.adbPath ?? "Auto-detected from PATH",
                    found: viewModel.adbPath != nil
                        || fm.isExecutableFile(atPath: "/usr/local/bin/adb")
                        || fm.isExecutableFile(atPath: "/opt/homebrew/bin/adb")
                ),
            ]

            DispatchQueue.main.async {
                toolStatuses = statuses
                isCheckingTools = false
            }
        }
    }
}
