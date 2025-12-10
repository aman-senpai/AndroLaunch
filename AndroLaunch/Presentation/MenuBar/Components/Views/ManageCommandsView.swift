//
//  ManageCommandsView.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 12/10/25.
//

import SwiftUI

struct ManageCommandsView: View {
    @ObservedObject var viewModel: MenuViewModel
    
    @State private var newCommandName: String = ""
    @State private var newCommandScript: String = ""
    @State private var isHostCommand: Bool = false
    @State private var isBackground: Bool = false
    
    @State private var commandToDelete: ShellCommand?
    @State private var showDeleteConfirmation: Bool = false
    
    init(viewModel: MenuViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Shell Commands")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                
                Button("Import") {
                    viewModel.importCommands()
                }
                .font(.callout)
                
                Button("Export") {
                    viewModel.exportCommands()
                }
                .font(.callout)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            // Command List
            List {
                ForEach(viewModel.getGlobalShellCommands()) { command in
                    HStack(spacing: 12) {
                        Image(systemName: command.isBackground ? "gear.badge.checkmark" : "terminal.fill")
                            .font(.system(size: 14))
                            .foregroundColor(command.isBackground ? .orange : .blue)
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(command.name)
                                .font(.body)
                                .foregroundColor(.primary)
                            Text(command.command)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            commandToDelete = command
                            showDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onHover { isHovering in
                            if isHovering { NSCursor.pointingHand.push() }
                            else { NSCursor.pop() }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(InsetListStyle())
            .border(Color.gray.opacity(0.1), width: 1)
            
            // Input Area
            VStack(spacing: 12) {
                Divider()
                
                HStack {
                    Text("New Command")
                        .font(.headline)
                    Spacer()
                }
                
                VStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Name:")
                            .frame(width: 70, alignment: .trailing)
                            .foregroundColor(.secondary)
                        TextField("Install APK", text: $newCommandName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    HStack(alignment: .firstTextBaseline) {
                        Text("Target:")
                            .frame(width: 70, alignment: .trailing)
                            .foregroundColor(.secondary)
                        Picker("", selection: $isHostCommand) {
                            Text("Device (adb shell)").tag(false)
                            Text("Mac (Host)").tag(true)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .labelsHidden()
                        Spacer()
                    }
                    
                    HStack(alignment: .top) {
                        Text("Command:")
                            .frame(width: 70, alignment: .trailing)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            TextField(isHostCommand ? "adb install /path/to/apk" : "pm list packages", text: $newCommandScript)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            if isHostCommand {
                                Text("Command runs on your Mac. 'adb' will automatically target the selected device.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                
                HStack {
                    Toggle("Run in Background", isOn: $isBackground)
                        .toggleStyle(CheckboxToggleStyle())
                        .font(.callout)
                    
                    Text("(Headless)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: addNewCommand) {
                        Text("Add Command")
                            .padding(.horizontal, 10)
                    }
                    .disabled(newCommandName.isEmpty || newCommandScript.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 500, height: 600)
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text("Delete Command"),
                message: Text("Are you sure you want to delete '\(commandToDelete?.name ?? "")'? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    if let id = commandToDelete?.id {
                        viewModel.deleteShellCommand(id: id)
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private func addNewCommand() {
        let command = ShellCommand(
            name: newCommandName,
            command: newCommandScript,
            isBackground: isBackground,
            isHostCommand: isHostCommand
        )
        viewModel.saveShellCommand(command)
        
        // Reset fields
        newCommandName = ""
        newCommandScript = ""
        isBackground = false
        isHostCommand = false
    }
}
