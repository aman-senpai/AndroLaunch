//
//  DashboardDeviceView.swift
//  AndroLaunch
//
//  Device tab of the compact dashboard. With the Hub removed this is the one
//  place that gathers the phone's identity plus every device action that used to
//  live behind the Hub or only in the legacy menu: mirror, camera (back/front),
//  frame mode, screenshot, ring, storage, Wi-Fi pairing, the companion, Android
//  virtual devices, saved commands, Trackpad, Glance, the camera extension and
//  the classic right-click menu.
//
//  The surface is monochrome: neutral greys from the shared design system, no
//  purple. In the menu-bar panel (glass mode) cards and hovered rows use the
//  Liquid Glass surface; in a normal window they use the opaque card fill.
//

import AppKit
import SwiftUI

// MARK: - Device tab

struct DashboardDeviceView: View {
    let device: AndroidDevice?

    @Environment(\.hubSnapshotMode) private var snapshotMode

    var body: some View {
        if snapshotMode {
            DashboardDevicePanelContent(
                device: device,
                context: .snapshotPreview(device: device),
                onAction: { _ in })
        } else {
            DashboardDeviceLiveContent(device: device)
        }
    }
}


// MARK: - Device switcher

/// The Device tab is a fleet view, not a single-device inspector: every
/// connected phone is listed, tapping a row selects it and expands its details.
private struct DeviceSwitcherCard: View {
    @ObservedObject var store: HubStore
    let selectedID: String?

    @State private var expandedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DashboardSectionHeader("Devices") {
                Text("\(store.devices.count)")
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textTertiary)
            }
            HubCard(padding: 0) {
                VStack(spacing: 0) {
                    if store.devices.isEmpty {
                        HubEmptyState(
                            icon: "iphone.slash",
                            title: "No devices connected",
                            subtitle: "Connect a phone over USB or Wi-Fi to manage it here.")
                            .padding(.vertical, 12)
                    } else {
                        ForEach(Array(store.devices.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { HubDivider() }
                            deviceRow(item)
                        }
                    }
                }
            }
        }
    }

    private func deviceRow(_ item: AndroidDevice) -> some View {
        let selected = item.id == selectedID
        let expanded = expandedID == item.id
        return VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                    store.select(item)
                    expandedID = expanded ? nil : item.id
                }
            } label: {
                HStack(spacing: 9) {
                    HubIconTile(
                        systemName: item.isWirelessTransport ? "wifi" : "iphone.gen3",
                        tint: selected ? HubColor.textPrimary : HubColor.textSecondary,
                        size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(item.name)
                                .font(.hubRowTitle)
                                .foregroundStyle(HubColor.textPrimary)
                                .lineLimit(1)
                            if selected { HubStatusDot(size: 5) }
                        }
                        Text(deviceSubtitle(item))
                            .font(.hubCaption)
                            .foregroundStyle(HubColor.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(HubColor.textTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .hoverGlass(cornerRadius: 10, enabled: true, scale: 1.004, liftShadow: false)

            if expanded {
                VStack(spacing: 0) {
                    HubDivider()
                    HStack(spacing: 8) {
                        detail("Model", item.model ?? "—")
                        detail("Android", item.androidVersion ?? "—")
                        detail("API", item.apiLevel ?? "—")
                        detail("Battery", item.batteryLevel.map { "\($0)%" } ?? "—")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    if selectedID != item.id {
                        Button("Use this device") { store.select(item) }
                            .buttonStyle(.plain)
                            .font(.hubButton)
                            .foregroundStyle(HubColor.textPrimary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .hubGlassSurface(cornerRadius: 7)
                            .padding(.bottom, 9)
                    }
                }
            }
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(HubColor.textTertiary)
            Text(value)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(HubColor.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deviceSubtitle(_ item: AndroidDevice) -> String {
        var parts = [item.isWirelessTransport ? "Wi-Fi" : "USB"]
        if let battery = item.batteryLevel { parts.append("\(battery)%") }
        if !item.isConnected { parts.append("Offline") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Live context

private struct DashboardDeviceLiveContent: View {
    let device: AndroidDevice?

    @ObservedObject private var surface = PanelFeatureSurface.shared
    @ObservedObject private var camera = CameraController.shared
    @ObservedObject private var companion = CompanionClient.shared
    @ObservedObject private var ring = RingService.shared
    @ObservedObject private var trackpad = TrackpadController.shared
    @ObservedObject private var glance = GlanceBoardController.shared
    @ObservedObject private var menuViewModel = DependencyContainer.shared.menuViewModel
    @ObservedObject private var store = HubStore.shared

    @State private var feedback: String?
    @State private var feedbackIsError = false
    @State private var isCapturing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeviceSwitcherCard(store: store, selectedID: device?.id)
            DashboardDevicePanelContent(
                device: device,
                context: context,
                onAction: perform)
        }
        .onAppear(perform: refreshLiveState)
        .onChange(of: device?.id) { _, _ in refreshLiveState() }
    }

    private var context: DevicePanelContext {
        DevicePanelContext(
            device: device,
            camera: camera.state,
            companionState: companion.state(for: device?.id ?? ""),
            isRinging: device.map { ring.isRinging(deviceID: $0.id) } ?? false,
            isTrackpadShown: trackpad.isPresented,
            isGlanceShown: glance.isVisible,
            virtualDeviceCount: surface.virtualDeviceCount,
            runningVirtualDeviceCount: surface.runningVirtualDeviceCount,
            commands: menuViewModel.getGlobalShellCommands(),
            cameraExtension: camera.state.extensionStatus,
            feedback: feedback,
            feedbackIsError: feedbackIsError,
            isCapturing: isCapturing)
    }

    private func refreshLiveState() {
        surface.refreshVirtualDeviceCount()
        surface.refreshCommandCount()
        if let device, device.isConnected {
            companion.prepare(deviceID: device.id, completion: nil)
        }
    }

    private func perform(_ action: PanelDeviceAction) {
        switch action {
        case .mirror:
            apply(surface.mirrorScreen(deviceID: device?.id))
        case .cameraMenu:
            break  // Presentational expansion is handled inside the content view.
        case .camera(let lens):
            apply(surface.startCameraPreview(deviceID: device?.id, lens: lens))
        case .stopCamera:
            apply(surface.stopCameraPreview())
        case .frameMode:
            apply(surface.toggleFrameMode(deviceID: device?.id))
        case .screenshot:
            isCapturing = true
            surface.takeScreenshot(deviceID: device?.id) { result in
                isCapturing = false
                apply(result)
            }
        case .ring:
            apply(surface.toggleRing(deviceID: device?.id))
        case .storage:
            apply(surface.openStorageAnalytics(deviceID: device?.id))
        case .wifi:
            surface.openWiFiConnection(initialTab: .qr)
        case .companion:
            surface.openWiFiConnection(initialTab: .companion)
        case .installCompanion:
            apply(.ok("Installing AndroLaunch Comp…"))
            surface.installCompanion(deviceID: device?.id) { result in
                apply(result)
            }
        case .virtualDevices:
            surface.openEmulatorManager()
        case .usbGuidance:
            surface.showUSBGuidance()
        case .runCommand(let command):
            apply(surface.runCommand(command, deviceID: device?.id))
        case .manageCommands:
            surface.openCommandsManager()
        case .trackpad:
            apply(surface.showTrackpad(deviceID: device?.id))
        case .glance:
            apply(surface.toggleGlance())
        case .cameraExtension:
            apply(surface.openCameraExtension())
        }
    }

    private func apply(_ result: PanelFeatureFeedback) {
        feedback = result.message
        feedbackIsError = result.isError
    }
}

// MARK: - Context

struct DevicePanelContext {
    var device: AndroidDevice?
    var camera: CameraPreviewState
    var companionState: CompanionClient.State
    var isRinging: Bool
    var isTrackpadShown: Bool
    var isGlanceShown: Bool
    var virtualDeviceCount: Int
    var runningVirtualDeviceCount: Int
    var commands: [ShellCommand]
    var cameraExtension: CameraExtensionStatus
    var feedback: String?
    var feedbackIsError: Bool
    var isCapturing: Bool

    static func snapshotPreview(device: AndroidDevice?) -> DevicePanelContext {
        var camera = CameraPreviewState()
        camera.deviceID = device?.id
        camera.deviceName = device?.name
        camera.isDeviceConnected = true
        camera.isScrcpyAvailable = true
        camera.extensionStatus = .unavailable("Requires a signed camera extension.")
        return DevicePanelContext(
            device: device,
            camera: camera,
            companionState: .ready(version: "3.1"),
            isRinging: false,
            isTrackpadShown: false,
            isGlanceShown: false,
            virtualDeviceCount: 3,
            runningVirtualDeviceCount: 1,
            commands: [
                ShellCommand(
                    name: "Battery stats", command: "dumpsys battery",
                    isBackground: false),
                ShellCommand(
                    name: "Restart Wi-Fi", command: "svc wifi disable; svc wifi enable",
                    isBackground: false),
                ShellCommand(
                    name: "Logcat to file", command: "logcat -d > /sdcard/logcat.txt",
                    isBackground: true),
            ],
            cameraExtension: .unavailable("Requires a signed camera extension."),
            feedback: nil,
            feedbackIsError: false,
            isCapturing: false)
    }

    var companionLabel: String {
        switch companionState {
        case .unknown: return "Checking…"
        case .notInstalled: return "Not installed"
        case .stopped: return "Stopped"
        case .ready(let version): return "Ready · v\(version)"
        case .failed: return "Needs attention"
        }
    }

    var companionIsReady: Bool {
        if case .ready = companionState { return true }
        return false
    }

    var virtualDeviceSummary: String {
        if virtualDeviceCount == 0 { return "No virtual devices yet" }
        var summary = "\(virtualDeviceCount) virtual device\(virtualDeviceCount == 1 ? "" : "s")"
        if runningVirtualDeviceCount > 0 {
            summary += " · \(runningVirtualDeviceCount) running"
        }
        return summary
    }
}

// MARK: - Actions

enum PanelDeviceAction {
    case mirror
    case cameraMenu
    case camera(CameraLens)
    case stopCamera
    case frameMode
    case screenshot
    case ring
    case storage
    case wifi
    case companion
    case installCompanion
    case virtualDevices
    case usbGuidance
    case runCommand(ShellCommand)
    case manageCommands
    case trackpad
    case glance
    case cameraExtension
}

// MARK: - Presentational content (shared by live and snapshot)

private struct DashboardDevicePanelContent: View {
    let device: AndroidDevice?
    let context: DevicePanelContext
    let onAction: (PanelDeviceAction) -> Void

    @Environment(\.hubGlassMode) private var glassMode
    @Environment(\.colorScheme) private var colorScheme
    @State private var cameraMenuExpanded = false

    private var isConnected: Bool { device?.isConnected ?? false }

    private var frameModeAvailable: Bool {
        guard let device else { return false }
        return MeldModeSupport.supportsVirtualDisplay(apiLevel: device.apiLevel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            identityCard

            if device != nil {
                actionsSection
                if cameraMenuExpanded {
                    cameraLensRow
                }
                if context.camera.isPreviewing || context.camera.message != nil {
                    cameraStatusCard
                }
                connectionCard
                commandsCard
                allToolsCard
            } else {
                noDeviceCard
            }

            if let feedback = context.feedback {
                DashboardFeedback(text: feedback, isError: context.feedbackIsError)
            }

            Text(
                "Mirror and camera preview open separate scrcpy windows; screenshots and commands use ADB. Every action here is also available in the classic menu on right-click."
            )
            .font(.system(size: 9.5))
            .foregroundStyle(secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
            .padding(.top, 2)
        }
    }

    // MARK: Text tones

    private var primaryText: Color {
        glassMode ? HubColor.glassTextPrimary : HubColor.textPrimary
    }

    private var secondaryText: Color {
        glassMode ? HubColor.glassTextSecondary : HubColor.textSecondary
    }

    private var tertiaryText: Color {
        glassMode ? HubColor.glassTextTertiary : HubColor.textTertiary
    }

    // MARK: Identity

    private var identityCard: some View {
        DevicePanelCard(padding: 11) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    identityCell("Name", device?.name ?? "—")
                    identityCell("Model", displayModel)
                }
                HStack(spacing: 8) {
                    identityCell("Android", displayAndroid)
                    identityCell("API", device?.apiLevel ?? "—")
                }
                HStack(spacing: 8) {
                    identityCell(
                        "Battery", displayBattery,
                        tint: batteryTint)
                    identityCell("Connection", displayConnection)
                }
                HStack(spacing: 6) {
                    Text("SERIAL")
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(tertiaryText)
                    Text(displaySerial)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func identityCell(
        _ label: String, _ value: String, tint: Color? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(tertiaryText)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint ?? primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayModel: String {
        guard let model = device?.model?.trimmingCharacters(in: .whitespacesAndNewlines),
            !model.isEmpty
        else { return "—" }
        return model
    }

    private var displayAndroid: String {
        guard
            let version = device?.androidVersion?.trimmingCharacters(
                in: .whitespacesAndNewlines),
            !version.isEmpty
        else { return "—" }
        return "Android \(version)"
    }

    private var displayBattery: String {
        guard let level = device?.batteryLevel else { return "—" }
        if device?.isCharging == true { return "\(level)% · Charging" }
        return "\(level)%"
    }

    private var batteryTint: Color {
        guard let level = device?.batteryLevel else { return secondaryText }
        if level <= 15 { return HubColor.danger }
        if level <= 30 { return HubColor.warning }
        return secondaryText
    }

    private var displayConnection: String {
        guard let device else { return "—" }
        let transport = device.isWirelessTransport ? "Wi-Fi" : "USB"
        return device.isConnected ? "\(transport) · Connected" : "\(transport) · Offline"
    }

    private var displaySerial: String {
        guard let device else { return "—" }
        let serial = device.serialNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let serial, !serial.isEmpty { return serial }
        return device.id
    }

    // MARK: No device

    private var noDeviceCard: some View {
        DevicePanelCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tertiaryText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No phone connected")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(primaryText)
                        Text("Connect over USB or Wi-Fi to unlock the device tools.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                monochromeButton("Wi-Fi Connection", icon: "wifi", prominent: false) {
                    onAction(.wifi)
                }
                monochromeButton("USB Connection Guide", icon: "cable.connector", prominent: false) {
                    onAction(.usbGuidance)
                }
            }
        }
    }

    // MARK: Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DashboardSectionHeader("Actions") {
                if !isConnected {
                    Text("OFFLINE")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(HubColor.warning)
                }
            }

            HStack(spacing: 7) {
                actionTile(
                    "Mirror", icon: "iphone.gen3", prominent: true,
                    enabled: isConnected
                ) { onAction(.mirror) }
                actionTile(
                    "Camera", icon: "camera.fill", prominent: false,
                    enabled: isConnected
                ) {
                    withAnimation(.easeOut(duration: 0.14)) {
                        cameraMenuExpanded.toggle()
                    }
                }
                actionTile(
                    frameModeTitle, icon: "rectangle.on.rectangle", prominent: false,
                    enabled: isConnected && frameModeAvailable
                ) { onAction(.frameMode) }
            }

            HStack(spacing: 7) {
                actionTile(
                    context.isCapturing ? "Saving…" : "Screenshot",
                    icon: "camera.viewfinder", prominent: false,
                    enabled: isConnected && !context.isCapturing
                ) { onAction(.screenshot) }
                actionTile(
                    context.isRinging ? "Stop Ring" : "Ring Phone",
                    icon: "bell.badge.fill", prominent: false,
                    enabled: isConnected
                ) { onAction(.ring) }
                actionTile(
                    "Storage", icon: "internaldrive", prominent: false,
                    enabled: isConnected
                ) { onAction(.storage) }
            }
        }
    }

    private var frameModeTitle: String { "Frame Mode" }

    private var cameraLensRow: some View {
        DevicePanelCard(padding: 8) {
            HStack(spacing: 6) {
                compactButton("Back", icon: "camera.fill") { onAction(.camera(.back)) }
                compactButton("Front", icon: "person.crop.square") { onAction(.camera(.front)) }
                if context.camera.isPreviewing {
                    compactButton("Stop", icon: "stop.fill", destructive: true) {
                        onAction(.stopCamera)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var cameraStatusCard: some View {
        DevicePanelCard(padding: 10) {
            HStack(spacing: 9) {
                Image(
                    systemName: context.camera.isPreviewing
                        ? "camera.fill" : "camera"
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(
                    context.camera.isPreviewing ? primaryText : secondaryText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        context.camera.isPreviewing
                            ? "\(context.camera.lens.title) preview running"
                            : "Camera preview"
                    )
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(primaryText)
                    if let message = context.camera.message {
                        Text(message)
                            .font(.system(size: 10))
                            .foregroundStyle(HubColor.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Runs in a separate scrcpy window · audio stays on the phone")
                            .font(.system(size: 10))
                            .foregroundStyle(secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Connection

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            DashboardSectionHeader("Connection")
            DevicePanelCard(padding: 6) {
                VStack(spacing: 2) {
                    panelRow(
                        icon: "wifi",
                        title: "Wi-Fi Connection",
                        subtitle: "QR code, pairing code, IP address and companion"
                    ) { onAction(.wifi) }

                    panelRow(
                        icon: "ipad.and.iphone",
                        title: "AndroLaunch Comp",
                        subtitle: context.companionLabel,
                        badge: context.companionIsReady ? "READY" : nil,
                        badgeTint: secondaryText
                    ) { onAction(.companion) }

                    if !context.companionIsReady {
                        panelRow(
                            icon: "arrow.down.circle",
                            title: "Install Companion",
                            subtitle: "Bundled APK installed over ADB"
                        ) { onAction(.installCompanion) }
                    }

                    panelRow(
                        icon: "macbook.and.iphone",
                        title: "Virtual Devices",
                        subtitle: context.virtualDeviceSummary,
                        badge: context.virtualDeviceCount > 0
                            ? "\(context.virtualDeviceCount)" : nil,
                        badgeTint: secondaryText
                    ) { onAction(.virtualDevices) }

                    if isConnected {
                        panelRow(
                            icon: device?.isWirelessTransport == true
                                ? "cable.connector" : "checkmark.seal",
                            title: device?.isWirelessTransport == true
                                ? "USB Connection" : "USB Debugging",
                            subtitle: device?.isWirelessTransport == true
                                ? "Prefer a cable for faster transfers"
                                : "Authorised on this Mac"
                        ) { onAction(.usbGuidance) }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Commands

    private var commandsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            DashboardSectionHeader("Commands") {
                Text("\(context.commands.count)")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(tertiaryText)
            }
            DevicePanelCard(padding: 6) {
                VStack(spacing: 2) {
                    if context.commands.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "terminal")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(tertiaryText)
                            Text("No saved commands yet")
                                .font(.system(size: 11))
                                .foregroundStyle(secondaryText)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 9)
                    } else {
                        ForEach(Array(context.commands.prefix(4))) { command in
                            panelRow(
                                icon: "terminal",
                                title: command.name,
                                subtitle: command.command,
                                monoSubtitle: true,
                                trailingIcon: "play.fill"
                            ) { onAction(.runCommand(command)) }
                        }
                    }
                    panelRow(
                        icon: "slider.horizontal.3",
                        title: "Manage Commands",
                        subtitle: "Create, edit and export saved shell commands"
                    ) { onAction(.manageCommands) }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: All tools

    private var allToolsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            DashboardSectionHeader("All tools")
            DevicePanelCard(padding: 6) {
                VStack(spacing: 2) {
                    panelRow(
                        icon: "hand.draw",
                        title: "Trackpad",
                        subtitle: context.isTrackpadShown
                            ? "Floating gesture panel is open" : "Gestures, back/home/recents",
                        badge: context.isTrackpadShown ? "SHOWN" : nil,
                        badgeTint: secondaryText
                    ) { onAction(.trackpad) }

                    panelRow(
                        icon: "rectangle.3.group",
                        title: "Glance Board",
                        subtitle: context.isGlanceShown
                            ? "Desktop board is visible" : "Battery, storage and apps on the desktop",
                        badge: context.isGlanceShown ? "SHOWN" : nil,
                        badgeTint: secondaryText
                    ) { onAction(.glance) }

                    panelRow(
                        icon: "video.badge.plus",
                        title: "Camera Extension",
                        subtitle: context.cameraExtension.summary,
                        badge: context.cameraExtension.badgeText.uppercased(),
                        badgeTint: secondaryText
                    ) { onAction(.cameraExtension) }

                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Rows & tiles

    private func actionTile(
        _ title: String,
        icon: String,
        prominent: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tileForeground(prominent: prominent))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tileProminentFill)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(glassMode ? 0.06 : 0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.clear)
                                .hubGlassSurface(cornerRadius: 10, interactive: true))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(HubColor.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(title)
    }

    private var tileProminentFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.92) : Color.black.opacity(0.86)
    }

    private func tileForeground(prominent: Bool) -> Color {
        guard prominent else { return primaryText }
        return colorScheme == .dark ? .black : .white
    }

    private func panelRow(
        icon: String,
        title: String,
        subtitle: String,
        monoSubtitle: Bool = false,
        badge: String? = nil,
        badgeTint: Color = HubColor.textTertiary,
        trailingIcon: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        PanelLinkRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            monoSubtitle: monoSubtitle,
            badge: badge,
            badgeTint: badgeTint,
            trailingIcon: trailingIcon,
            action: action)
    }

    private func monochromeButton(
        _ title: String, icon: String, prominent: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(prominent ? (colorScheme == .dark ? .black : .white) : primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        prominent
                            ? tileProminentFill : Color.primary.opacity(glassMode ? 0.06 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(HubColor.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func compactButton(
        _ title: String, icon: String, destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(destructive ? HubColor.danger : primaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(glassMode ? 0.06 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(HubColor.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Reusable monochrome panel surfaces

struct DevicePanelCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: () -> Content
    @Environment(\.hubGlassMode) private var glassMode

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if glassMode {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.clear)
                        .hubGlassSurface(cornerRadius: 12)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(HubColor.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(HubColor.stroke, lineWidth: 1))
                }
            }
    }
}

struct PanelLinkRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var monoSubtitle: Bool = false
    var badge: String? = nil
    var badgeTint: Color = HubColor.textTertiary
    var trailingIcon: String? = nil
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.hubGlassMode) private var glassMode

    private var primaryText: Color {
        glassMode ? HubColor.glassTextPrimary : HubColor.textPrimary
    }

    private var secondaryText: Color {
        glassMode ? HubColor.glassTextSecondary : HubColor.textSecondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        hovering ? primaryText : (glassMode
                            ? HubColor.glassTextSecondary : HubColor.textSecondary))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(
                            monoSubtitle
                                ? .system(size: 9.5, design: .monospaced)
                                : .system(size: 10))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                        .truncationMode(monoSubtitle ? .middle : .tail)
                }
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.system(size: 8.5, weight: .semibold))
                        .tracking(0.3)
                        .foregroundStyle(badgeTint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(badgeTint.opacity(0.12)))
                }
                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .frame(width: 16)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(
                            glassMode ? HubColor.glassTextTertiary : HubColor.textTertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background {
                if hovering {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.clear)
                        .hubGlassSurface(cornerRadius: 8, interactive: true)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.clear)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(title). \(subtitle)")
    }
}
