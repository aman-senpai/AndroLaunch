//
//  SettingsSections.swift
//  AndroLaunch
//
//  The Settings screen's sections. Each section is a header + one card
//  of compact rows, matching the reference hierarchy: Fusion mode, Hardware
//  support, AI, Devices, Notifications, Storage and About.
//
//  Every action delegates to the owning feature's contract. Nothing here
//  pretends a platform-blocked capability works: unavailable rows are disabled
//  and state the reason in words.
//

import AppKit
import SwiftUI

// MARK: - Fusion mode

struct SettingsFusionSection: View {
    @ObservedObject var store: HubStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var spotlight: SpotlightService
    let showSpotlight: () -> Void

    private enum Support {
        case supported(AndroidDevice)
        case noDevice
        case unsupported(AndroidDevice)

        var isSupported: Bool {
            if case .supported = self { return true }
            return false
        }
    }

    private var spotlightIsOn: Bool { store.isPreview ? true : spotlight.isEnabled }

    private var support: Support {
        guard let device = store.selectedDevice else { return .noDevice }
        guard let api = device.apiLevel.flatMap({ Int($0) }) else { return .unsupported(device) }
        return api >= 34 ? .supported(device) : .unsupported(device)
    }

    private var meldFootnote: String? {
        switch support {
        case .supported:
            return nil
        case .noDevice:
            return
                "Requires Android 14 or later. Connect an Android 14+ device to turn this on."
        case .unsupported(let device):
            let version = device.androidVersion.map { "Android \($0)" } ?? "an older Android version"
            return
                "Requires Android 14 or later. \(device.name) runs \(version), so apps open on "
                + "the phone screen instead."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HubMetric.cardGap) {
            HubSectionHeader("Fusion mode")
            HubCard {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        icon: "rectangle.on.rectangle",
                        title: "Frame Mode",
                        subtitle: "Use your Android apps directly in windows.",
                        footnote: meldFootnote,
                        isOn: $preferences.meldModeEnabled,
                        disabled: !support.isSupported)

                    HubDivider()

                    HubChevronRow(
                        icon: "magnifyingglass",
                        title: "Spotlight Search",
                        subtitle: "Open Android apps from Spotlight, Alfred and Raycast.",
                        value: spotlightIsOn ? "On" : "Off",
                        valueTint: HubColor.textPrimary,
                        action: showSpotlight)

                    HubDivider()

                    SettingsToggleRow(
                        icon: "link",
                        title: "Open Links on Mac",
                        subtitle: "Open links tapped in Frame Mode with your Mac browser.",
                        footnote:
                            "Not available in this build: Frame Mode link interception needs a separate Scrcpy link bridge.",
                        isOn: $preferences.openLinksOnMac,
                        disabled: true)

                    HubDivider()

                    SettingsToggleRow(
                        icon: "arrow.left.arrow.right",
                        title: "Handoff",
                        subtitle: "Continue the Android app you were just using on this Mac.",
                        isOn: $preferences.handoffEnabled)
                }
            }
        }
    }
}

// MARK: - Hardware support

struct SettingsHardwareSection: View {
    @ObservedObject var store: HubStore
    @ObservedObject var camera: CameraController
    @ObservedObject var trackpad: TrackpadController
    @ObservedObject var glance: GlanceBoardController

    private var selectedDevice: AndroidDevice? { store.selectedDevice }

    private var cameraStatus: CameraExtensionStatus {
        if store.isPreview {
            return .unavailable(
                "Local camera extension not bundled in this preview. The in-app preview still works.")
        }
        return camera.state.extensionStatus
    }

    private var cameraStatusPillTint: Color {
        switch cameraStatus {
        case .querying: return HubColor.textSecondary
        case .installable: return HubColor.textSecondary
        case .installed: return HubColor.textPrimary
        case .unavailable: return HubColor.textTertiary
        }
    }

    private var cameraCanPreview: Bool {
        store.isPreview || camera.state.canPreview || camera.state.isPreviewing
    }

    private var glanceBinding: Binding<Bool> {
        Binding(
            get: { store.isPreview ? true : glance.isVisible },
            set: { visible in
                guard !store.isPreview else { return }
                if visible { glance.show() } else { glance.hide() }
            })
    }

    let openCameraSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HubMetric.cardGap) {
            HubSectionHeader("Hardware support")
            HubCard {
                VStack(spacing: 0) {
                    cameraCard
                    HubDivider()
                    HubChevronRow(
                        icon: "hand.draw",
                        title: "Trackpad gestures",
                        subtitle: "Swipe, scroll and navigate your phone from the Mac trackpad.",
                        value: trackpad.isPresented ? "Open" : "Show",
                        disabled: selectedDevice == nil,
                        action: { trackpad.show(deviceID: selectedDevice?.id) })
                    if selectedDevice == nil {
                        HubNote(
                            text: "Connect an Android device to send trackpad gestures.",
                            icon: "info.circle")
                            .padding(.leading, 54)
                            .padding(.trailing, HubMetric.rowPaddingH)
                            .padding(.bottom, 8)
                    }
                    HubDivider()
                    SettingsToggleRow(
                        icon: "widget.small",
                        title: "Glance widgets",
                        subtitle: "Keep battery, storage and app shortcuts on your desktop.",
                        isOn: glanceBinding)
                }
            }
        }
    }

    private var cameraCard: some View {
        VStack(spacing: 0) {
            HubRowButton(action: openCameraSettings) {
                HStack(spacing: 11) {
                    HubIconTile(
                        systemName: "camera",
                        tint: HubColor.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use Android camera on Mac")
                            .font(.hubRowTitle)
                            .foregroundStyle(HubColor.textPrimary)
                        Text(cameraStatus.summary)
                            .font(.hubRowSubtitle)
                            .foregroundStyle(HubColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    SettingsStatePill(
                        text: cameraStatus.badgeText, tint: cameraStatusPillTint)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Use Android camera on Mac. \(cameraStatus.summary)")

            SettingsActionStrip(actions: [
                .init(
                    title: camera.state.isPreviewing ? "Stop Preview" : "Preview Phone Camera",
                    icon: camera.state.isPreviewing ? "stop.fill" : "camera.viewfinder",
                    style: .quiet,
                    enabled: cameraCanPreview,
                    handler: {
                        guard !store.isPreview else { return }
                        if camera.state.isPreviewing {
                            camera.stopPreview()
                        } else {
                            camera.preview(deviceID: selectedDevice?.id)
                        }
                    }),
                .init(
                    title: "Camera Settings",
                    icon: "slider.horizontal.3",
                    style: .secondary,
                    enabled: true,
                    handler: openCameraSettings),
            ])

            if selectedDevice == nil {
                HubNote(
                    text: "Connect an Android device to preview its camera.",
                    icon: "info.circle")
                    .padding(.leading, 54)
                    .padding(.trailing, HubMetric.rowPaddingH)
                    .padding(.bottom, 10)
            } else if !store.isPreview, !camera.state.isScrcpyAvailable {
                HubNote(
                    text:
                        "scrcpy isn't installed. Install it with Homebrew (`brew install scrcpy`) "
                        + "to preview the camera.",
                    icon: "info.circle")
                    .padding(.leading, 54)
                    .padding(.trailing, HubMetric.rowPaddingH)
                    .padding(.bottom, 10)
            }
        }
    }
}

// MARK: - AI / Android Use

struct SettingsAISection: View {
    @ObservedObject var store: HubStore
    @ObservedObject var mcp: MCPController
    let showActivity: () -> Void

    @State private var copied = false

    private var androidUseBinding: Binding<Bool> {
        Binding(get: { mcp.isEnabled }, set: { mcp.setEnabled($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HubMetric.cardGap) {
            HubSectionHeader("AI") {
                SettingsStatePill(
                    text: mcp.isEnabled ? "On" : "Off",
                    tint: mcp.isEnabled ? HubColor.textPrimary : HubColor.textTertiary)
            }

            HubCard {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        icon: "sparkles",
                        iconTint: HubColor.accent,
                        title: "Android Use",
                        subtitle: "Let AI agents use your Android device through MCP.",
                        isOn: androidUseBinding,
                        disabled: !mcp.executableSupportsServer)

                    HubDivider()

                    SettingsStatusRow(
                        dotColor: mcp.isEnabled ? HubColor.success : HubColor.textTertiary,
                        title: "MCP server",
                        value: mcp.isEnabled ? "Ready over stdio" : "Off",
                        valueTint: HubColor.textPrimary)

                    SettingsCommandBlock(
                        label: "MCP COMMAND",
                        command: mcp.command,
                        isCopyConfirmed: copied,
                        copy: copyCommand)

                    SettingsActionStrip(actions: [
                        .init(
                            title: "AI Activity",
                            icon: "list.bullet.rectangle",
                            style: .secondary,
                            handler: showActivity),
                        .init(
                            title: "Stop Server",
                            icon: "stop.fill",
                            style: .destructive,
                            enabled: mcp.isEnabled,
                            handler: { mcp.stop() }),
                    ])

                    HubDivider()

                    SettingsEmptyNote(
                        icon: "lock",
                        text:
                            "Runs locally in this app over stdio — no network port, no cloud. "
                            + "Android Use is enforced for every tool call."
                            + (store.connectedDevices.isEmpty
                                ? " Connect an Android device to use control tools."
                                : ""))
                }
            }

            if let error = mcp.lastErrorText {
                HubNote(text: error, icon: "exclamationmark.triangle")
            }
        }
    }

    private func copyCommand() {
        mcp.copyCommand()
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            copied = false
        }
    }
}

// MARK: - Devices

struct SettingsDevicesSection: View {
    @ObservedObject var preferences: AppPreferences
    /// Snapshot state is a fixture (launch at login reads a real SMAppService
    /// status that would otherwise vary per Mac).
    var isPreview: Bool = false

    private var launchAtLogin: LaunchAtLoginController { preferences.launchAtLogin }

    private var launchIsOn: Bool { isPreview ? true : launchAtLogin.state.isRequested }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchIsOn },
            set: { enabled in
                guard !isPreview else { return }
                launchAtLogin.setEnabled(enabled)
            })
    }

    private var loginFootnote: String? {
        if isPreview { return nil }
        switch launchAtLogin.state {
        case .off, .on:
            return nil
        case .requiresApproval, .notFound, .unavailable:
            return launchAtLogin.state.detail
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HubMetric.cardGap) {
            HubSectionHeader("Devices")
            HubCard {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        icon: "power",
                        iconTint: HubColor.success,
                        title: "Launch at login",
                        subtitle: "Open AndroLaunch automatically when you log in to this Mac.",
                        footnote: loginFootnote,
                        isOn: launchBinding)

                    if !isPreview,
                        launchAtLogin.state == .requiresApproval
                            || launchAtLogin.state == .notFound
                            || isUnavailable(launchAtLogin.state)
                    {
                        SettingsActionStrip(actions: [
                            .init(
                                title: "Open Login Items",
                                icon: "gear",
                                style: .secondary,
                                handler: { launchAtLogin.openLoginItemsSettings() })
                        ])
                    }

                    HubDivider()

                    SettingsToggleRow(
                        icon: "bell.badge",
                        title: "Device connection notifications",
                        subtitle: "Show a notification when a new device connects to this Mac.",
                        isOn: $preferences.deviceConnectionNotifications)

                    HubDivider()

                    SettingsToggleRow(
                        icon: "folder.badge.minus",
                        title: "Ignore system files",
                        subtitle:
                            "Hide .DS_Store and other macOS metadata from the phone's storage.",
                        isOn: $preferences.ignoreSystemFiles)

                    HubDivider()

                    HubValueRow(
                        title: "Simultaneous devices",
                        value: "Up to 5 devices")
                }
            }
        }
    }

    private func isUnavailable(_ state: LaunchAtLoginState) -> Bool {
        if case .unavailable = state { return true }
        return false
    }
}

// MARK: - Notifications

struct SettingsNotificationsSection: View {
    @ObservedObject var store: HubStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var mirror: NotificationMirror
    let showFeatureAlerts: () -> Void

    /// Snapshot state is a fixture: the live mirror switch may legitimately be
    /// off on this Mac, but the design review needs the complete enabled screen.
    private var mirrorIsOn: Bool { store.isPreview ? true : mirror.masterEnabled }
    private var sensitiveIsOn: Bool { store.isPreview ? true : mirror.hideSensitiveApps }

    private var masterBinding: Binding<Bool> {
        Binding(
            get: { mirrorIsOn },
            set: { enabled in
                guard !store.isPreview else { return }
                mirror.setMasterEnabled(enabled)
            })
    }

    private var sensitiveBinding: Binding<Bool> {
        Binding(
            get: { sensitiveIsOn },
            set: { hidden in
                guard !store.isPreview else { return }
                mirror.setHideSensitiveApps(hidden)
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HubMetric.cardGap) {
            HubSectionHeader("Notifications") {
                SettingsStatePill(
                    text: mirrorIsOn ? "On" : "Off",
                    tint: mirrorIsOn ? HubColor.textPrimary : HubColor.textTertiary)
            }

            HubCard {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        icon: "bell",
                        title: "Mirror Android notifications",
                        subtitle: "Show new Android notifications in macOS Notification Center.",
                        footnote: store.connectedDevices.isEmpty
                            ? "Connect an Android device to mirror its notifications."
                            : nil,
                        isOn: masterBinding)

                    HubDivider()

                    SettingsToggleRow(
                        icon: "arrowshape.turn.up.left",
                        title: "Inline reply",
                        subtitle: "Reply to messages directly from the macOS notification.",
                        isOn: $preferences.inlineReply,
                        disabled: !mirrorIsOn)

                    HubDivider()

                    SettingsToggleRow(
                        icon: "eye.slash",
                        title: "Hide sensitive apps",
                        subtitle: "Keep banking, authenticator and email text off this Mac.",
                        isOn: sensitiveBinding,
                        disabled: !mirrorIsOn)

                    HubDivider()

                    HubChevronRow(
                        icon: "bell.badge",
                        title: "Feature alerts",
                        subtitle: "Choose which AndroLaunch events notify you.",
                        value: "Manage",
                        action: showFeatureAlerts)

                    HubDivider()

                    SettingsEmptyNote(
                        icon: "info.circle",
                        text:
                            "Mirroring uses the AndroLaunch companion and a local notification "
                            + "listener. Inline reply is best-effort: apps that ignore "
                            + "RemoteInput keep their reply action on the phone.")
                }
            }
        }
    }
}

// MARK: - Storage

struct SettingsStorageSection: View {
    @ObservedObject var store: HubStore
    let openStorage: (AndroidDevice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HubMetric.cardGap) {
            HubSectionHeader("Storage")
            HubCard {
                HubChevronRow(
                    icon: "internaldrive",
                    title: "Phone storage",
                    subtitle: store.selectedDevice.map {
                        "Open the storage breakdown for \($0.name)."
                    } ?? "Connect an Android device to inspect its storage.",
                    value: store.selectedDevice == nil ? "No device" : "Open",
                    valueTint: store.selectedDevice == nil
                        ? HubColor.textTertiary : HubColor.textSecondary,
                    disabled: store.selectedDevice == nil,
                    action: {
                        guard let device = store.selectedDevice else { return }
                        openStorage(device)
                    })
            }
            HubNote(
                text:
                    "Reads df/du on the phone. The breakdown stays on this Mac.",
                icon: "lock")
        }
    }
}

// MARK: - About

struct SettingsAboutSection: View {
    let showLicenses: () -> Void

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var helpURL: URL? {
        URL(string: "https://github.com/aman-senpai/AndroLaunch/issues")
    }

    private var repositoryURL: URL? {
        URL(string: "https://github.com/aman-senpai/AndroLaunch")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HubMetric.cardGap) {
            HubSectionHeader("About")
            HubCard {
                VStack(spacing: 0) {
                    HubValueRow(title: "Version", value: versionText)
                    HubDivider()

                    HubChevronRow(
                        icon: "questionmark.circle",
                        title: "Help Center",
                        subtitle: "Setup guides, troubleshooting and the issue tracker.",
                        action: {
                            if let helpURL { NSWorkspace.shared.open(helpURL) }
                        })

                    HubDivider()

                    HubChevronRow(
                        icon: "star",
                        title: "Star on GitHub",
                        subtitle: "If AndroLaunch is useful, a star helps the project.",
                        action: {
                            if let repositoryURL { NSWorkspace.shared.open(repositoryURL) }
                        })

                    HubDivider()

                    HubChevronRow(
                        icon: "doc.text",
                        title: "Licenses",
                        subtitle: "Open-source credits and acknowledgements.",
                        action: showLicenses)

                    HubDivider()

                    SettingsEmptyNote(
                        icon: "lock",
                        text:
                            "Privacy: local only. No account, no cloud service and no telemetry. "
                            + "Device data never leaves this Mac.")
                }
            }

            HubNote(
                text: "AndroLaunch \(versionText) · Designed for macOS.",
                icon: "desktopcomputer")
        }
    }
}
