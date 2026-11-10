//
//  CameraSettingsRows.swift
//  AndroLaunch
//
//  The "Phone camera" card. A pure renderer of `CameraPreviewState`, so
//  the Hub Settings screen (owned by settings-mcp) can embed it without owning
//  any camera logic, and the DEBUG snapshot harness can render it headlessly.
//
//  Usage from Settings:
//      CameraSettingsSection(state: CameraController.shared.state,
//                            actions: CameraController.shared.actions)
//  or embed just the rows inside an existing card:
//      CameraSettingsRows(state: ..., actions: ...)
//

import SwiftUI

// MARK: - Section

struct CameraSettingsSection: View {
    let state: CameraPreviewState
    let actions: CameraSettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: HubMetric.cardGap) {
            HubSectionHeader("Phone camera")
            HubCard {
                CameraSettingsRows(state: state, actions: actions)
            }
        }
    }
}

// MARK: - Rows

struct CameraSettingsRows: View {
    let state: CameraPreviewState
    let actions: CameraSettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !state.isDeviceConnected {
                disconnectedNote
            }
            controls
            previewActions
            if let message = state.message {
                messageBanner(message)
            }
            if let hint = state.restartHint {
                HubNote(text: hint, icon: "arrow.clockwise")
            }
            extensionBlock
            HubNote(text: state.note)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 11) {
            HubIconTile(
                systemName: state.isPreviewing ? "camera.fill" : "camera",
                tint: state.isPreviewing ? HubColor.success : HubColor.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Phone camera")
                    .font(.hubRowTitle)
                    .foregroundStyle(HubColor.textPrimary)
                Text(state.statusSummary)
                    .font(.hubRowSubtitle)
                    .foregroundStyle(statusTint)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            if state.isPreviewing {
                HubStatusDot(color: HubColor.success, size: 6)
            }
            HubPill(
                text: state.lens.shortTitle,
                tint: HubColor.accent,
                icon: state.lens.icon)
        }
    }

    private var statusTint: Color {
        switch state.statusTintName {
        case "success": return HubColor.success
        case "warning": return HubColor.warning
        default: return HubColor.textSecondary
        }
    }

    private var disconnectedNote: some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HubColor.textTertiary)
            Text("Connect a device in the Hub to preview its camera.")
                .font(.hubCaption)
                .foregroundStyle(HubColor.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HubMetric.rowPaddingH)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: HubMetric.rowRadius, style: .continuous)
                .fill(HubColor.cardElevated.opacity(0.6)))
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Lens")
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textSecondary)
                    .frame(width: 54, alignment: .leading)
                HubSegmentedTabs(
                    items: CameraLens.allCases.map {
                        .init(value: $0, title: $0.shortTitle, icon: $0.icon)
                    },
                    selection: Binding(
                        get: { state.lens },
                        set: { actions.setLens($0) }),
                    compact: true)
            }

            HStack(spacing: 10) {
                Text("Aspect")
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textSecondary)
                    .frame(width: 54, alignment: .leading)
                HubSegmentedTabs(
                    items: CameraAspect.allCases.map {
                        .init(value: $0, title: $0.title, icon: nil)
                    },
                    selection: Binding(
                        get: { state.aspect },
                        set: { actions.setAspect($0) }),
                    compact: true)
            }

            zoomRow

            HubToggleRow(
                icon: "flashlight.on.fill",
                iconTint: state.torchAvailable ? HubColor.warning : HubColor.textTertiary,
                title: "Torch",
                subtitle: state.torchSubtitle,
                isOn: Binding(
                    get: { state.torchEnabled },
                    set: { actions.setTorch($0) }),
                disabled: !state.torchAvailable || !state.isDeviceConnected)
        }
        .padding(.horizontal, HubMetric.rowPaddingH)
        .padding(.vertical, 4)
    }

    private var zoomRow: some View {
        HStack(spacing: 10) {
            Text("Zoom")
                .font(.hubCaption)
                .foregroundStyle(HubColor.textSecondary)
                .frame(width: 54, alignment: .leading)
            Slider(
                value: Binding(
                    get: { state.zoom },
                    set: { actions.setZoom($0) }),
                in: CameraZoom.minimum...CameraZoom.maximum
            )
            .tint(HubColor.accent)
            .disabled(!state.isDeviceConnected)
            .accessibilityLabel("Camera zoom")
            .accessibilityValue(state.zoomLabel)
            Text(state.zoomLabel)
                .font(.hubMono)
                .foregroundStyle(HubColor.textSecondary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    // MARK: Preview actions

    private var previewActions: some View {
        HStack(spacing: 8) {
            HubActionButton(
                title: state.primaryActionTitle,
                icon: state.primaryActionIcon,
                style: .primary,
                enabled: state.canPreview || state.isPreviewing
            ) {
                if state.isPreviewing {
                    actions.stopPreview()
                } else {
                    actions.startPreview()
                }
            }

            if state.isPreviewing {
                HubActionButton(
                    title: "Switch camera",
                    icon: "arrow.triangle.2.circlepath.camera",
                    style: .secondary
                ) {
                    actions.setLens(state.lens == .back ? .front : .back)
                }
            }

            if state.needsRestart {
                HubActionButton(
                    title: "Apply & restart",
                    icon: "arrow.clockwise",
                    style: .quiet
                ) {
                    actions.restartPreview()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, HubMetric.rowPaddingH)
    }

    // MARK: Message

    private func messageBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HubColor.warning)
                .padding(.top, 1)
            Text(text)
                .font(.hubCaption)
                .foregroundStyle(HubColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: actions.clearMessage) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(HubColor.textTertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss camera message")
        }
        .padding(.horizontal, HubMetric.rowPaddingH)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: HubMetric.rowRadius, style: .continuous)
                .fill(HubColor.warningSoft))
        .padding(.horizontal, HubMetric.rowPaddingH)
    }

    // MARK: Extension

    private var extensionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(HubColor.stroke)
                .frame(height: 1)
                .padding(.horizontal, HubMetric.rowPaddingH)

            HStack(spacing: 11) {
                HubIconTile(
                    systemName: "video.badge.plus",
                    tint: state.extensionStatus.isInstalled ? HubColor.success : HubColor.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Camera extension")
                        .font(.hubRowTitle)
                        .foregroundStyle(HubColor.textPrimary)
                    Text(state.extensionRowSubtitle)
                        .font(.hubRowSubtitle)
                        .foregroundStyle(HubColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                HubPill(
                    text: state.extensionBadge,
                    tint: state.extensionBadgeIsWarning ? HubColor.warning : HubColor.success)
            }
            .padding(.horizontal, HubMetric.rowPaddingH)

            HStack(spacing: 8) {
                HubActionButton(
                    title: "Extension settings",
                    icon: "gearshape",
                    style: .secondary
                ) {
                    actions.openExtensionSettings()
                }
                if state.extensionStatus.canInstall {
                    HubActionButton(
                        title: "Install extension",
                        icon: "arrow.down.circle",
                        style: .primary
                    ) {
                        actions.installExtension()
                    }
                }
                if state.extensionStatus.isQuerying {
                    HubActionButton(
                        title: "Check again",
                        icon: "arrow.clockwise",
                        style: .quiet
                    ) {
                        actions.refreshExtensionStatus()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, HubMetric.rowPaddingH)

            if case .unavailable(let reason) = state.extensionStatus {
                Text(reason)
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, HubMetric.rowPaddingH)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
    import AppKit

    /// Renders the camera card to a PNG without a window server session. Used by
    /// the platform-extras debug snapshot harness; harmless in normal builds.
    enum CameraSettingsSnapshot {
        @MainActor
        static func render(to directory: URL) {
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            var state = CameraPreviewState()
            state.deviceID = "R58M12ABCDE"
            state.deviceName = "Pixel 9 Pro"
            state.isDeviceConnected = true
            state.isScrcpyAvailable = true
            state.extensionStatus = .unavailable(
                "No signed camera extension is installed on this Mac.")
            render(
                CameraSettingsSection(state: state, actions: CameraSettingsActions()),
                name: "camera-settings.png", in: directory)

            state.isPreviewing = true
            state.zoom = 2
            state.torchEnabled = true
            render(
                CameraSettingsSection(state: state, actions: CameraSettingsActions()),
                name: "camera-settings-previewing.png", in: directory)
        }

        @MainActor
        private static func render<V: View>(_ view: V, name: String, in directory: URL) {
            let renderer = ImageRenderer(
                content: view
                    .frame(width: 440)
                    .padding(20)
                    .background(HubColor.background)
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
