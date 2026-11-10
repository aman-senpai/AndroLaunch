//
//  MenuBarPanelToolsView.swift
//  AndroLaunch
//
//  Compact "Tools" overlay for the menu-bar glass panel. With the Hub removed
//  this is the complete secondary surface: it reaches the features that do not
//  have a permanent row in the five dashboard tabs (mirror + camera, Wi-Fi and
//  virtual devices, saved commands, storage, Finder, clipboard, Trackpad,
//  Glance, camera extension and the classic right-click menu).
//
//  Monochrome by design: neutral greys and the glass surface, no purple.
//

import AppKit
import SwiftUI

struct MenuBarPanelToolsView: View {
    let actions: MenuBarPanelActions
    var deviceName: String? = nil
    var hasDevice: Bool = false
    let dismiss: () -> Void

    @ObservedObject private var surface = PanelFeatureSurface.shared
    @Environment(\.hubGlassMode) private var glassMode
    @Environment(\.hubSnapshotMode) private var snapshotMode

    @State private var feedback: String?
    @State private var feedbackIsError = false

    private var disabledNote: String { "Connect a phone to use this" }
    private var deviceLabel: String { deviceName ?? "the phone" }

    /// Snapshot/preview values keep design review deterministic without starting
    /// the live services.
    private var virtualDeviceCount: Int {
        snapshotMode ? 3 : surface.virtualDeviceCount
    }

    private var virtualDeviceSummary: String {
        snapshotMode ? "3 virtual devices · 1 running" : surface.virtualDeviceSummary
    }

    private var commandCount: Int {
        snapshotMode ? 3 : surface.commandCount
    }

    private var extensionSummary: String {
        snapshotMode
            ? "Signed-extension status; preview works in-app."
            : surface.cameraExtensionStatus.summary
    }

    private var primaryText: Color {
        glassMode ? HubColor.glassTextPrimary : HubColor.textPrimary
    }

    private var secondaryText: Color {
        glassMode ? HubColor.glassTextSecondary : HubColor.textSecondary
    }

    private var tertiaryText: Color {
        glassMode ? HubColor.glassTextTertiary : HubColor.textTertiary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(spacing: 1) {
                sectionLabel("Device")
                toolRow(
                    icon: "iphone.gen3",
                    title: "Mirror Screen",
                    subtitle: hasDevice
                        ? "Open the live phone screen on this Mac."
                        : disabledNote,
                    enabled: hasDevice
                ) {
                    apply(surface.mirrorScreen(deviceID: nil))
                }

                toolRow(
                    icon: "slider.horizontal.3",
                    title: "Mirror Controls",
                    subtitle: hasDevice
                        ? "Audio, pin, screen off, clipboard and frame."
                        : disabledNote,
                    enabled: hasDevice
                ) {
                    apply(surface.openMirrorControls(deviceID: nil))
                }

                toolRow(
                    icon: "camera.fill",
                    title: "Camera Preview",
                    subtitle: hasDevice
                        ? "Back lens · front lens is on the Device tab."
                        : disabledNote,
                    enabled: hasDevice
                ) {
                    apply(surface.startCameraPreview(deviceID: nil, lens: .back))
                }

                toolRow(
                    icon: "rectangle.on.rectangle",
                    title: "Frame Mode",
                    subtitle: hasDevice
                        ? "Android apps in their own windows."
                        : disabledNote,
                    enabled: hasDevice
                ) {
                    apply(surface.toggleFrameMode(deviceID: nil))
                }

                toolRow(
                    icon: "camera.viewfinder",
                    title: "Screenshot",
                    subtitle: hasDevice
                        ? "Save the phone screen to Pictures."
                        : disabledNote,
                    enabled: hasDevice,
                    dismissBefore: false
                ) {
                    surface.takeScreenshot(deviceID: nil) { result in
                        apply(result)
                    }
                }

                sectionLabel("Connect")
                toolRow(
                    icon: "wifi",
                    title: "Wi-Fi Connection",
                    subtitle: "QR code, pairing code, IP and companion."
                ) {
                    surface.openWiFiConnection(initialTab: .qr)
                }

                toolRow(
                    icon: "macbook.and.iphone",
                    title: "Virtual Devices",
                    subtitle: virtualDeviceCount > 0
                        ? virtualDeviceSummary
                        : "Create and run Android emulators (AVDs).",
                    badge: virtualDeviceCount > 0 ? "\(virtualDeviceCount)" : nil
                ) {
                    surface.openEmulatorManager()
                }

                toolRow(
                    icon: "terminal",
                    title: "Commands",
                    subtitle: commandCount > 0
                        ? "\(commandCount) saved shell command\(commandCount == 1 ? "" : "s")."
                        : "Create saved shell commands and run them on the phone.",
                    badge: commandCount > 0 ? "\(commandCount)" : nil
                ) {
                    surface.openCommandsManager()
                }

                sectionLabel("Tools")
                toolRow(
                    icon: "hand.draw",
                    title: "Trackpad",
                    subtitle: hasDevice
                        ? "Back, home, recents and scrolling."
                        : disabledNote,
                    enabled: hasDevice
                ) {
                    apply(surface.showTrackpad(deviceID: nil))
                }

                toolRow(
                    icon: "rectangle.3.group",
                    title: "Glance Board",
                    subtitle: "Battery, storage and app shortcuts."
                ) {
                    apply(surface.toggleGlance())
                }

                toolRow(
                    icon: "video.badge.plus",
                    title: "Camera Extension",
                    subtitle: extensionSummary
                ) {
                    apply(surface.openCameraExtension())
                }

                toolRow(
                    icon: "chart.pie.fill",
                    title: "Storage Analytics",
                    subtitle: hasDevice
                        ? "Capacity, categories and folder drill-down."
                        : disabledNote,
                    enabled: hasDevice
                ) {
                    actions.openStorageAnalytics()
                }

                toolRow(
                    icon: "folder.badge.gearshape",
                    title: "Finder Mirror",
                    subtitle: hasDevice
                        ? "Local Finder copy of the phone's files."
                        : disabledNote,
                    enabled: hasDevice
                ) {
                    actions.openFinderMirror()
                }

                toolRow(
                    icon: "doc.on.clipboard",
                    title: "Copy Clipboard to Android",
                    subtitle: hasDevice
                        ? "Send the Mac clipboard to \(deviceLabel)."
                        : disabledNote,
                    enabled: hasDevice,
                    dismissBefore: false
                ) {
                    if let message = actions.copyClipboardToAndroid() {
                        withAnimation(.easeOut(duration: 0.16)) {
                            feedback = message
                            feedbackIsError = message.hasPrefix("Couldn't")
                                || message.hasPrefix("Copy some text")
                                || message.hasPrefix("Connect")
                        }
                    }
                }

                Divider()
                    .overlay(HubColor.stroke)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)

            }
            .padding(.bottom, 2)

            if let feedback {
                HStack(alignment: .top, spacing: 6) {
                    Image(
                        systemName: feedbackIsError
                            ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(
                            feedbackIsError ? HubColor.danger : HubColor.success)
                        .padding(.top, 1)
                    Text(feedback)
                        .font(.system(size: 10.5))
                        .foregroundStyle(feedbackIsError ? HubColor.danger : secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 2)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            }

            Text("Finder mirror is a local copy, not a File Provider mount.")
                .font(.system(size: 9))
                .foregroundStyle(tertiaryText)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .padding(.top, 2)
        }
        .frame(width: 306)
        .hubGlassSurface(cornerRadius: 18)
        .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tools")
        .onAppear {
            if !snapshotMode {
                surface.refreshVirtualDeviceCount()
            }
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(secondaryText)
            Text("Tools")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(primaryText)
            Spacer(minLength: 6)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(secondaryText)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close tools")
            .help("Close")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func sectionLabel(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(tertiaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 1)
    }

    // MARK: - Row

    private func toolRow(
        icon: String,
        title: String,
        subtitle: String,
        enabled: Bool = true,
        badge: String? = nil,
        dismissBefore: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        PanelToolRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            enabled: enabled,
            badge: badge,
            dismissBefore: dismissBefore,
            dismiss: dismiss,
            action: action)
    }

    private func apply(_ result: PanelFeatureFeedback) {
        withAnimation(.easeOut(duration: 0.16)) {
            feedback = result.message
            feedbackIsError = result.isError
        }
    }
}

// MARK: - Row

private struct PanelToolRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let enabled: Bool
    let badge: String?
    let dismissBefore: Bool
    let dismiss: () -> Void
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.hubGlassMode) private var glassMode

    private var primaryText: Color {
        glassMode ? HubColor.glassTextPrimary : HubColor.textPrimary
    }

    private var secondaryText: Color {
        glassMode ? HubColor.glassTextSecondary : HubColor.textSecondary
    }

    private var tertiaryText: Color {
        glassMode ? HubColor.glassTextTertiary : HubColor.textTertiary
    }

    var body: some View {
        Button {
            guard enabled else { return }
            if dismissBefore { dismiss() }
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(enabled ? (hovering ? primaryText : secondaryText) : tertiaryText)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(enabled ? primaryText : tertiaryText)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 6)
                if let badge {
                    Text(badge)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                if enabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(tertiaryText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background {
                if hovering && enabled {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.clear)
                        .hubGlassSurface(cornerRadius: 8, interactive: true)
                        .padding(.horizontal, 8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}
