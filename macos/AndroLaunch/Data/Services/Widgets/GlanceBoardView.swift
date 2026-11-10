//
//  GlanceBoardView.swift
//  AndroLaunch
//
//  The Glance desktop board: device status, battery, storage and quick apps in a
//  compact floating surface. Value-driven renderer of `GlanceBoardState`; the
//  window shell is in Presentation/Overlays/GlanceBoardWindow.swift.
//
//  WidgetKit is documented as future work: it needs a separate signed extension
//  target, so this build ships a real desktop board instead of faking a widget.
//

import AppKit
import SwiftUI

// MARK: - Model

final class GlanceBoardModel: ObservableObject {
    @Published var state: GlanceBoardState
    let actions: GlanceBoardActions

    init(state: GlanceBoardState, actions: GlanceBoardActions) {
        self.state = state
        self.actions = actions
    }
}

// MARK: - View

struct GlanceBoardView: View {
    @ObservedObject var model: GlanceBoardModel

    /// Snapshots cannot draw AppKit-backed switches; they use a static shape.
    @Environment(\.hubSnapshotMode) private var snapshotMode

    private var state: GlanceBoardState { model.state }

    var body: some View {
        VStack(spacing: 10) {
            header
            if state.isConnected {
                batteryCard
                storageCard
                quickApps
            } else {
                emptyState
            }
            footer
        }
        .padding(14)
        .frame(width: 320)
        .background(HubColor.background)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 9) {
            HubLogoMark(size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.deviceName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(HubColor.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.isConnected ? HubColor.success : HubColor.textTertiary)
                        .frame(width: 5, height: 5)
                    Text(state.statusText)
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textSecondary)
                    if let transport = state.transport, state.isConnected {
                        Text("·")
                            .font(.hubCaption)
                            .foregroundStyle(HubColor.textTertiary)
                        Text(transport.label)
                            .font(.hubCaption)
                            .foregroundStyle(HubColor.textTertiary)
                    }
                }
            }
            Spacer(minLength: 4)
            GlanceIconButton(
                systemName: "arrow.clockwise", label: "Refresh Glance",
                action: model.actions.refresh)
            GlanceIconButton(
                systemName: "xmark", label: "Close Glance board",
                action: model.actions.close)
        }
    }

    // MARK: Battery

    private var batteryCard: some View {
        HubCard(padding: 11) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: batteryIcon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(batteryTint)
                    Text("Battery")
                        .font(.hubRowTitle)
                        .foregroundStyle(HubColor.textPrimary)
                    Spacer(minLength: 6)
                    if let charging = state.chargingText {
                        HubPill(text: charging, tint: HubColor.success, icon: "bolt.fill")
                    }
                    Text(state.batteryText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HubColor.textPrimary)
                        .monospacedDigit()
                }
                HubProgressBar(
                    value: Double(state.batteryLevel ?? 0) / 100,
                    tint: batteryTint,
                    height: 4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Battery \(state.batteryText)\(state.chargingText.map { ", \($0)" } ?? "")")
    }

    private var batteryIcon: String {
        if state.isCharging == true { return "battery.100percent.bolt" }
        switch state.batteryLevel ?? 0 {
        case 90...: return "battery.100percent"
        case 60..<90: return "battery.75percent"
        case 35..<60: return "battery.50percent"
        case 15..<35: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private var batteryTint: Color {
        switch state.batteryTone {
        case "success": return HubColor.success
        case "warning": return HubColor.warning
        case "danger": return HubColor.danger
        default: return HubColor.accent
        }
    }

    // MARK: Storage

    private var storageCard: some View {
        HubCard(padding: 11) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HubColor.textSecondary)
                    Text("Storage")
                        .font(.hubRowTitle)
                        .foregroundStyle(HubColor.textPrimary)
                    Spacer(minLength: 6)
                    Text(state.storageText)
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
                if let fraction = state.storageFraction {
                    HubProgressBar(
                        value: fraction,
                        tint: fraction > 0.92 ? HubColor.danger : HubColor.accent,
                        height: 4)
                } else if state.isLoadingStorage {
                    HubProgressBar(value: 0.35, tint: HubColor.textTertiary, height: 4)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Storage \(state.storageText)")
    }

    // MARK: Quick apps

    private var quickApps: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("QUICK APPS")
                    .font(.hubSectionLabel)
                    .tracking(0.9)
                    .foregroundStyle(HubColor.textTertiary)
                Spacer()
                Text(state.quickAppsCaption)
                    .font(.system(size: 9.5))
                    .foregroundStyle(HubColor.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)

            if state.apps.isEmpty {
                Text("Apps load from the phone automatically.")
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4),
                    spacing: 7
                ) {
                    ForEach(state.apps) { app in
                        GlanceAppButton(app: app) { model.actions.openApp(app) }
                    }
                }
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(HubColor.textTertiary)
            Text(state.hasDevice ? "Phone disconnected" : "No phone connected")
                .font(.hubRowTitle)
                .foregroundStyle(HubColor.textSecondary)
            Text(
                "Glance shows battery, storage and quick apps while a device is connected."
            )
            .font(.hubCaption)
            .foregroundStyle(HubColor.textTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            HubActionButton(title: "Open Dashboard", icon: "macwindow", style: .secondary) {
                model.actions.openHub()
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: HubMetric.cardRadius, style: .continuous)
                .fill(HubColor.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HubMetric.cardRadius, style: .continuous)
                .strokeBorder(HubColor.stroke, lineWidth: 1))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: state.hideUntilConnected ? "eye.slash.fill" : "eye.slash")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HubColor.textTertiary)
            Text("Hide until reconnects")
                .font(.hubCaption)
                .foregroundStyle(HubColor.textSecondary)
            if snapshotMode {
                SnapshotSwitch(isOn: state.hideUntilConnected)
            } else {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { state.hideUntilConnected },
                        set: { model.actions.setHideUntilConnected($0) })
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(HubColor.accent)
                .accessibilityLabel("Hide Glance board until a device reconnects")
            }

            Spacer(minLength: 4)

            Button(action: model.actions.openHub) {
                HStack(spacing: 4) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("Dashboard")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(HubColor.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(HubColor.accentSoft))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Open the dashboard")
            .accessibilityLabel("Open Dashboard")
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Pieces

private struct GlanceActionButton: View {
    let app: GlanceAppShortcut
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? HubColor.cardHover : HubColor.cardElevated)
                    .frame(height: 34)
                    .overlay(
                        Image(systemName: app.iconName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(HubColor.textPrimary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(HubColor.stroke, lineWidth: 1))
                Text(app.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(HubColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open \(app.name) on your Mac")
        .accessibilityLabel("Open \(app.name) on your Mac")
    }
}

/// `ImageRenderer` renders AppKit-backed switches as unsupported placeholders;
/// snapshots draw the same shape statically.
private struct SnapshotSwitch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? HubColor.accent : HubColor.controlTrack)
            .frame(width: 30, height: 18)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .padding(2)
            }
            .accessibilityHidden(true)
    }
}

/// Alias kept private so the grid reads naturally.
private typealias GlanceAppButton = GlanceActionButton

private struct GlanceIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HubColor.textTertiary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Preview

#if DEBUG
    /// Headless render used by the platform-extras snapshot harness.
    enum GlanceBoardSnapshot {
        @MainActor
        static func render(to directory: URL) {
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)

            var connected = GlanceBoardState()
            connected.deviceID = "R58M12ABCDE"
            connected.deviceName = "Pixel 9 Pro"
            connected.transport = .usb
            connected.isConnected = true
            connected.batteryLevel = 82
            connected.isCharging = false
            connected.storageFraction = 0.68
            connected.storageSummary = "174 GB of 256 GB used"
            connected.apps = [
                GlanceAppShortcut(packageName: "com.whatsapp", name: "WhatsApp", iconName: "message.fill"),
                GlanceAppShortcut(packageName: "com.spotify.music", name: "Spotify", iconName: "music.note"),
                GlanceAppShortcut(packageName: "com.google.android.youtube", name: "YouTube", iconName: "play.rectangle.fill"),
                GlanceAppShortcut(packageName: "com.google.android.apps.photos", name: "Photos", iconName: "photo.fill"),
                GlanceAppShortcut(packageName: "com.google.android.gm", name: "Gmail", iconName: "envelope.fill"),
                GlanceAppShortcut(packageName: "com.google.android.apps.maps", name: "Maps", iconName: "map.fill"),
                GlanceAppShortcut(packageName: "com.android.chrome", name: "Chrome", iconName: "globe"),
                GlanceAppShortcut(packageName: "com.google.android.apps.messaging", name: "Messages", iconName: "message.fill"),
            ]
            render(state: connected, name: "glance-board.png", in: directory)

            var disconnected = GlanceBoardState()
            disconnected.hideUntilConnected = true
            render(state: disconnected, name: "glance-board-empty.png", in: directory)
        }

        @MainActor
        private static func render(
            state: GlanceBoardState, name: String, in directory: URL
        ) {
            let model = GlanceBoardModel(state: state, actions: GlanceBoardActions())
            let renderer = ImageRenderer(
                content: GlanceBoardView(model: model)
                    .environment(\.colorScheme, .dark)
                    .environment(\.hubSnapshotMode, true)
            )
            renderer.scale = 2
            guard let cgImage = renderer.cgImage else { return }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: directory.appendingPathComponent(name))
        }
    }
#endif
