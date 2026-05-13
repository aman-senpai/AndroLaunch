//
//  PreferencesView.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var viewModel: PreferencesViewModel
    @State private var toolStatuses: [ToolStatus] = []
    @State private var isCheckingTools = false

    struct ToolStatus: Identifiable {
        let id = UUID()
        let name: String
        let path: String
        let found: Bool
    }

    var body: some View {
        VStack(spacing: 20) {
            // ADB Status
            HStack {
                Image(
                    systemName: viewModel.adbStatus == "Connected"
                        ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundColor(viewModel.adbStatus == "Connected" ? .green : .red)
                Text("ADB Status: \(viewModel.adbStatus)")
                    .font(.headline)
            }

            Divider()

            // Command Line Tools Path
            VStack(alignment: .leading, spacing: 8) {
                Text("Android Command Line Tools Path")
                    .font(.subheadline)
                    .fontWeight(.bold)

                HStack {
                    TextField(
                        "Path to cmdline-tools/latest/bin",
                        text: Binding(
                            get: { viewModel.commandLineToolsPath },
                            set: { newValue in
                                viewModel.commandLineToolsPath = newValue
                                checkTools()
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Button("Browse…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.title = "Select Android SDK Command Line Tools Directory"
                        if panel.runModal() == .OK, let url = panel.url {
                            viewModel.commandLineToolsPath = url.path
                            checkTools()
                        }
                    }
                }

                Text("This directory should contain sdkmanager and avdmanager binaries.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Tool Status
            if !toolStatuses.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tool Status")
                        .font(.subheadline)
                        .fontWeight(.bold)

                    ForEach(toolStatuses) { tool in
                        HStack(spacing: 8) {
                            Image(
                                systemName: tool.found
                                    ? "checkmark.circle.fill" : "xmark.circle.fill"
                            )
                            .foregroundColor(tool.found ? .green : .red)
                            .frame(width: 16)
                            Text(tool.name)
                                .font(.callout)
                                .frame(width: 100, alignment: .leading)
                            Text(tool.path)
                                .font(.caption)
                                .foregroundColor(tool.found ? .secondary : .red)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )
            }

            Divider()

            // Actions
            HStack(spacing: 12) {
                Button("Auto-Detect SDK") {
                    if let detected = AppConstants.detectCmdlineToolsPath() {
                        viewModel.commandLineToolsPath = detected
                    }
                    checkTools()
                }

                Button("Check Tools") {
                    checkTools()
                }
                .disabled(isCheckingTools)

                Button("Check ADB Status") {
                    viewModel.checkAdbStatus()
                }

                if isCheckingTools {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                }
            }

            // Help text
            VStack(alignment: .leading, spacing: 4) {
                Text("Troubleshooting")
                    .font(.subheadline)
                    .fontWeight(.bold)
                Text(
                    """
                    • Install Android SDK Command-Line Tools from Android Studio or \
                    via Homebrew: `brew install --cask android-commandlinetools`
                    • After installation, run: `sdkmanager --install "cmdline-tools;latest"`
                    • The default path is usually: ~/Library/Android/sdk/cmdline-tools/latest/bin
                    • Open the Emulator Manager for advanced SDK and AVD settings.
                    """
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 420)
        .onAppear {
            checkTools()
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
