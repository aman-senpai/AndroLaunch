//
//  PreferencesView.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var viewModel: PreferencesViewModel

    var body: some View {
        VStack(spacing: 20) {
            Text("ADB Status: \(viewModel.adbStatus)")
                .font(.headline)

            if let error = viewModel.errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Android Command Line Tools Path")
                    .font(.subheadline)
                    .fontWeight(.bold)
                
                HStack {
                    TextField("Path to cmdline-tools/bin", text: Binding(
                        get: { viewModel.commandLineToolsPath },
                        set: { viewModel.commandLineToolsPath = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        
                        if panel.runModal() == .OK {
                            if let url = panel.url {
                                viewModel.commandLineToolsPath = url.path
                            }
                        }
                    }
                }
                Text("Required for 'sdkmanager' and 'avdmanager'.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Button("Check ADB Status") {
                viewModel.checkAdbStatus()
            }
        }
        .padding()
        .frame(width: 450, height: 350)
    }
}
