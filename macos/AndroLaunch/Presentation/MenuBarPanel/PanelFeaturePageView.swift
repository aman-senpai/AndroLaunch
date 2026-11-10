//
//  PanelFeaturePageView.swift
//  AndroLaunch
//
//  Windowless feature pages inside the menu-bar panel. Wi-Fi pairing, saved
//  commands and AVDs expand in place instead of opening NSWindows.
//

import AppKit
import SwiftUI

enum PanelFeaturePage: String, Identifiable {
    case wifi
    case commands
    case avd
    case mirrorControls

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wifi: return "Wi-Fi Connection"
        case .commands: return "Commands"
        case .avd: return "Virtual Devices"
        case .mirrorControls: return "Mirror Controls"
        }
    }
}

extension Notification.Name {
    static let openPanelFeaturePage = Notification.Name(
        "com.senpai.AndroLaunch.OpenPanelFeaturePage")
}

enum PanelFeaturePageRouter {
    static func open(_ page: PanelFeaturePage) {
        PanelRouter.openDashboard()
        // Wait for the panel's SwiftUI tree, then ask it to show the subpage.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            NotificationCenter.default.post(
                name: .openPanelFeaturePage, object: nil,
                userInfo: ["page": page.rawValue])
        }
    }
}

struct PanelFeaturePageView: View {
    let page: PanelFeaturePage
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(HubColor.stroke).frame(height: 1)
            ScrollView(.vertical, showsIndicators: false) {
                content
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 22)
            }
        }
        .background(Color.clear)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(HubColor.textPrimary)
                    .frame(width: 28, height: 28)
                    .background {
                        Circle().fill(.clear).hubGlassSurface(cornerRadius: 14)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Text(page.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(HubColor.textPrimary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(HubColor.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(HubColor.cardElevated))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .wifi:
            WiFiConnectionView(store: HubStore.shared)
        case .commands:
            PanelCommandsInlineView()
        case .avd:
            PanelAVDInlineView()
        case .mirrorControls:
            MirrorControlsPageInlineView()
        }
    }
}

// MARK: - Commands

private struct PanelCommandsInlineView: View {
    @State private var commands: [ShellCommand] = []
    @State private var name = ""
    @State private var script = ""
    @State private var feedback: String?
    @State private var showAdd = false
    @ObservedObject private var surface = PanelFeatureSurface.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Saved on this Mac")
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textSecondary)
                Spacer()
                Button(showAdd ? "Close" : "New") {
                    withAnimation(.easeOut(duration: 0.16)) { showAdd.toggle() }
                }
                .buttonStyle(.plain)
                .font(.hubButton)
                .foregroundStyle(HubColor.textPrimary)
            }
            if showAdd {
                HubCard {
                    VStack(spacing: 8) {
                        TextField("Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                        TextField("adb shell command", text: $script)
                            .textFieldStyle(.roundedBorder)
                        HubActionButton(title: "Save command", icon: "plus", style: .primary) {
                            let trimmedName = name.trimmingCharacters(in: .whitespaces)
                            let trimmedScript = script.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmedName.isEmpty, !trimmedScript.isEmpty else { return }
                            ShellCommandManager.shared.saveCommand(
                                ShellCommand(
                                    name: trimmedName, command: trimmedScript,
                                    isBackground: false))
                            name = ""
                            script = ""
                            showAdd = false
                            reload()
                        }
                    }
                }
            }
            if commands.isEmpty {
                HubCard {
                    HubEmptyState(
                        icon: "apple.terminal",
                        title: "No saved commands",
                        subtitle: "Create a command once and run it on this phone from here.")
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                        if index > 0 { HubDivider() }
                        HStack(spacing: 9) {
                            Image(systemName: "apple.terminal")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(HubColor.textSecondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(command.name)
                                    .font(.hubRowTitle)
                                    .foregroundStyle(HubColor.textPrimary)
                                Text(command.command)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(HubColor.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Button("Run") {
                                let result = surface.runCommand(
                                    command, deviceID: HubStore.shared.selectedDeviceID)
                                feedback = result.message
                            }
                            .buttonStyle(.plain)
                            .font(.hubButton)
                            .foregroundStyle(HubColor.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .hubGlassSurface(cornerRadius: 7)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(HubColor.card))
            }
            if let feedback {
                DashboardFeedback(text: feedback)
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() { commands = ShellCommandManager.shared.getAllCommands() }
}

// MARK: - AVDs

private struct PanelAVDInlineView: View {
    @ObservedObject private var viewModel =
        DependencyContainer.shared.emulatorManagerViewModel
    @State private var names: [String] = EmulatorInventory.load().avdNames

    private var combinedRows: [(name: String, avd: AVD?)] {
        names.map { name in
            (name, viewModel.existingAVDs.first(where: { $0.name == name }))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if combinedRows.isEmpty {
                HubCard {
                    HubEmptyState(
                        icon: "display",
                        title: "No virtual devices",
                        subtitle:
                            viewModel.setupIssue
                            ?? "Create an AVD in Android Studio, then refresh here.")
                }
            } else {
                ForEach(combinedRows, id: \.name) { row in
                    HubCard(padding: 11) {
                        HStack(spacing: 9) {
                            Image(systemName: "display")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(HubColor.textSecondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.name)
                                    .font(.hubRowTitle)
                                    .foregroundStyle(HubColor.textPrimary)
                                Text(
                                    row.avd?.isRunning == true ? "Running"
                                        : row.avd?.isStarting == true ? "Starting…"
                                        : row.avd?.isStopping == true ? "Stopping…" : "Stopped"
                                )
                                .font(.hubCaption)
                                .foregroundStyle(
                                    row.avd?.isRunning == true
                                        ? HubColor.success : HubColor.textSecondary)
                            }
                            Spacer(minLength: 4)
                            if row.avd?.isStarting == true || row.avd?.isStopping == true {
                                ProgressView().controlSize(.small)
                            } else {
                                Button(row.avd?.isRunning == true ? "Stop" : "Start") {
                                    if row.avd?.isRunning == true {
                                        viewModel.stopEmulator(avdName: row.name)
                                    } else {
                                        viewModel.startEmulator(avdName: row.name)
                                    }
                                }
                                .buttonStyle(.plain)
                                .font(.hubButton)
                                .foregroundStyle(HubColor.textPrimary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .hubGlassSurface(cornerRadius: 7)
                            }
                        }
                    }
                }
            }
            HubActionButton(title: "Refresh", icon: "arrow.clockwise", style: .quiet) {
                names = EmulatorInventory.load().avdNames
            }
        }
        .onAppear { names = EmulatorInventory.load().avdNames }
    }
}


private struct MirrorControlsPageInlineView: View {
    @ObservedObject private var controller = MirrorControlsController.shared

    var body: some View {
        MirrorControlsView()
            .padding(.horizontal, 2)
            .onAppear {
                if let id = HubStore.shared.selectedDeviceID {
                    controller.select(deviceID: id)
                }
            }
    }
}
