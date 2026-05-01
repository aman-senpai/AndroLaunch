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
    @State private var hoveredCommandID: UUID?
    @State private var commandToDelete: ShellCommand?
    @State private var showDeleteConfirmation: Bool = false
    @State private var isAddingCommand: Bool = false
    @State private var searchText: String = ""

    init(viewModel: MenuViewModel) {
        self.viewModel = viewModel
    }

    private var commands: [ShellCommand] {
        let all = viewModel.getGlobalShellCommands()
        guard !searchText.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.command.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()

            if commands.isEmpty && !searchText.isEmpty {
                searchEmptyState
            } else if commands.isEmpty {
                emptyStateView
            } else {
                commandList
            }

            Divider()
            addCommandSection
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 500, idealHeight: 620)
        .background(Color(NSColor.windowBackgroundColor))
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text("Delete Command"),
                message: Text(
                    "Are you sure you want to delete '\(commandToDelete?.name ?? "")'? This action cannot be undone."
                ),
                primaryButton: .destructive(Text("Delete")) {
                    if let id = commandToDelete?.id {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.deleteShellCommand(id: id)
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .animation(.easeInOut(duration: 0.2), value: isAddingCommand)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 0) {
            // Icon + Title
            HStack(spacing: 10) {
                Image(systemName: "apple.terminal.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.08))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text("Shell Commands")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("\(commands.count) command\(commands.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Import / Export
            HStack(spacing: 12) {
                Button(action: { viewModel.importCommands() }) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Import commands from JSON")

                Button(action: { viewModel.exportCommands() }) {
                    Image(systemName: "arrow.up.doc")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Export commands as JSON")
            }
            .padding(.trailing, 8)

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Search commands...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .frame(width: 140)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Command List

    private var commandList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(commands) { command in
                    commandCard(command)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(16)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }

    // MARK: - Command Card

    private func commandCard(_ command: ShellCommand) -> some View {
        HStack(spacing: 14) {
            // Leading icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 38, height: 38)

                Image(systemName: cardIcon(command))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }

            // Name + Command preview
            VStack(alignment: .leading, spacing: 3) {
                Text(command.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text(command.command)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Type badges
            HStack(spacing: 6) {
                if command.isHostCommand {
                    typeBadge(icon: "desktopcomputer", label: "Host")
                } else {
                    typeBadge(icon: "iphone.gen3", label: "Device")
                }

                if command.isBackground {
                    typeBadge(icon: "gearshape.2.fill", label: "BG")
                }
            }

            // Copy button (appears on hover)
            if hoveredCommandID == command.id {
                Button(action: { copyToClipboard(command.command) }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Copy command")
                .transition(.scale.combined(with: .opacity))
            }

            // Delete button
            Button(action: {
                commandToDelete = command
                showDeleteConfirmation = true
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Delete command")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    hoveredCommandID == command.id
                        ? Color(NSColor.controlBackgroundColor).opacity(0.8)
                        : Color(NSColor.controlBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    hoveredCommandID == command.id
                        ? Color.secondary.opacity(0.15)
                        : Color.secondary.opacity(0.06),
                    lineWidth: 1
                )
        )
        .shadow(
            color: hoveredCommandID == command.id
                ? Color.black.opacity(0.05)
                : Color.clear,
            radius: 4, y: 2
        )
        .scaleEffect(hoveredCommandID == command.id ? 1.01 : 1.0)
        .animation(.easeInOut(duration: 0.18), value: hoveredCommandID)
        .onHover { hovering in
            if hovering {
                hoveredCommandID = command.id
            } else if hoveredCommandID == command.id {
                hoveredCommandID = nil
            }
        }
    }

    // MARK: - Shared Badge

    private func typeBadge(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.secondary.opacity(0.06))
                    .frame(width: 80, height: 80)

                Image(systemName: "terminal")
                    .font(.system(size: 34, weight: .light))
                    .foregroundColor(.secondary.opacity(0.5))
            }

            VStack(spacing: 6) {
                Text("No Custom Commands")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(
                    "Add your own shell commands to run\non your device or Mac with a single click."
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            }

            Button(action: { withAnimation { isAddingCommand = true } }) {
                Label("Add Your First Command", systemImage: "plus.circle.fill")
                    .font(.callout)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }

    // MARK: - Search Empty State

    private var searchEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No commands match \"\(searchText)\"")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }

    // MARK: - Add Command Section

    private var addCommandSection: some View {
        VStack(spacing: 0) {
            // Toggle button
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isAddingCommand.toggle() } }
            ) {
                HStack(spacing: 8) {
                    Image(systemName: isAddingCommand ? "minus.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)

                    Text(isAddingCommand ? "Cancel" : "New Command")
                        .font(.callout)
                        .fontWeight(.medium)

                    Spacer()

                    if !isAddingCommand {
                        Text("⌘N")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)

            // Expandable form
            if isAddingCommand {
                Divider()

                VStack(spacing: 16) {
                    // Name + Target row
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        // Name field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Name")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            TextField("e.g. Install APK", text: $newCommandName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                        }

                        Spacer()

                        // Target picker
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Target")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            Picker("", selection: $isHostCommand) {
                                Text("Device (adb shell)").tag(false)
                                Text("Mac (Host)").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }

                    // Command field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Command")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        TextField(
                            isHostCommand ? "adb install /path/to/apk" : "pm list packages",
                            text: $newCommandScript
                        )
                        .textFieldStyle(.roundedBorder)

                        if isHostCommand {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text(
                                    "Runs on your Mac. 'adb' will automatically target the selected device."
                                )
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            .padding(.top, 2)
                        }
                    }

                    // Bottom row: Background toggle + Add button
                    HStack {
                        Toggle(isOn: $isBackground) {
                            HStack(spacing: 5) {
                                Text("Run in Background")
                                    .font(.callout)
                                Text("(Headless)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)

                        Spacer()

                        Button(action: addNewCommand) {
                            Label("Add Command", systemImage: "plus")
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(newCommandName.isEmpty || newCommandScript.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Helpers

    private func cardIcon(_ command: ShellCommand) -> String {
        if command.isHostCommand && command.isBackground {
            return "gearshape.2"
        } else if command.isHostCommand {
            return "desktopcomputer"
        } else if command.isBackground {
            return "arrow.triangle.2.circlepath"
        } else {
            return "apple.terminal"
        }
    }

    private func addNewCommand() {
        let command = ShellCommand(
            name: newCommandName,
            command: newCommandScript,
            isBackground: isBackground,
            isHostCommand: isHostCommand
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.saveShellCommand(command)
            isAddingCommand = false
        }

        // Reset fields
        newCommandName = ""
        newCommandScript = ""
        isBackground = false
        isHostCommand = false
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
