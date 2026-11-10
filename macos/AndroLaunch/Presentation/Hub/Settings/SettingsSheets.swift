//
//  SettingsSheets.swift
//  AndroLaunch
//
//  Sheets reachable from the Settings screen: AI Activity, Spotlight
//  management, feature alerts, licenses and the phone storage breakdown.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Sheet routing

enum SettingsSheet: Identifiable {
    case aiActivity
    case spotlight
    case featureAlerts
    case camera
    case licenses

    var id: String {
        switch self {
        case .aiActivity: return "ai-activity"
        case .spotlight: return "spotlight"
        case .featureAlerts: return "feature-alerts"
        case .camera: return "camera"
        case .licenses: return "licenses"
        }
    }
}

// MARK: - Sheet chrome

struct SettingsSheetHeader<Trailing: View>: View {
    let icon: String
    var iconTint: Color = HubColor.accent
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 11) {
            HubIconTile(systemName: icon, tint: iconTint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.hubCardTitle)
                    .foregroundStyle(HubColor.textPrimary)
                Text(subtitle)
                    .font(.hubCardSubtitle)
                    .foregroundStyle(HubColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
}

struct SettingsSheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(HubColor.textSecondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(HubColor.cardElevated))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .help("Close")
    }
}

// MARK: - AI Activity

struct SettingsAIActivitySheet: View {
    @ObservedObject var mcp: MCPController
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    private let refreshTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            SettingsSheetHeader(
                icon: "sparkles",
                iconTint: HubColor.accent,
                title: "AI Activity",
                subtitle:
                    "The last 100 Android Use calls. Only the tool, device, time and outcome "
                    + "are stored — never typed text, shell commands or clipboard contents."
            ) {
                SettingsSheetCloseButton { dismiss() }
            }

            Rectangle().fill(HubColor.stroke).frame(height: 1)

            if mcp.activities.isEmpty {
                HubEmptyState(
                    icon: "sparkles",
                    title: "No AI actions yet",
                    subtitle:
                        "Point an MCP client at the command in Settings → AI and ask it to call "
                        + "phone_list_devices. Calls appear here as they happen.")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(mcp.activities) { activity in
                            activityRow(activity)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }

            Rectangle().fill(HubColor.stroke).frame(height: 1)

            HStack(spacing: 8) {
                SettingsStatePill(
                    text: mcp.isEnabled ? "Android Use on" : "Android Use off",
                    tint: HubColor.textSecondary)
                Spacer(minLength: 8)
                HubActionButton(
                    title: "Show Log",
                    icon: "folder",
                    style: .quiet,
                    enabled: mcp.activities.isEmpty == false,
                    action: { mcp.revealActivityLog() })
                HubActionButton(
                    title: confirmClear ? "Confirm Clear" : "Clear Activity",
                    icon: "trash",
                    style: .secondary,
                    enabled: mcp.activities.isEmpty == false,
                    action: {
                        if confirmClear {
                            mcp.clearActivity()
                            confirmClear = false
                        } else {
                            confirmClear = true
                        }
                    })
                HubActionButton(
                    title: "Stop Android Use",
                    icon: "stop.fill",
                    style: .destructive,
                    enabled: mcp.isEnabled,
                    action: { mcp.stop() })
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 540, height: 560)
        .onAppear { mcp.refreshActivity() }
        .onReceive(refreshTimer) { _ in mcp.refreshActivity() }
    }

    private func activityRow(_ activity: MCPActivity) -> some View {
        HStack(alignment: .top, spacing: 10) {
            HubStatusDot(
                color: activity.ok ? HubColor.success : HubColor.danger, size: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(activity.tool)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HubColor.textPrimary)
                    SettingsStatePill(
                        text: activity.outcomeText,
                        tint: activity.ok ? HubColor.success : HubColor.danger)
                }
                Text(
                    [activity.timeText, activity.device ?? "no device", activity.detail]
                        .joined(separator: "  ·  ")
                )
                .font(.hubCaption)
                .foregroundStyle(HubColor.textTertiary)
                .lineLimit(2)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HubMetric.rowRadius, style: .continuous)
                .fill(HubColor.card)
                .overlay(
                    RoundedRectangle(cornerRadius: HubMetric.rowRadius, style: .continuous)
                        .strokeBorder(HubColor.stroke, lineWidth: 1)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(activity.tool), \(activity.outcomeText), \(activity.timeText), "
                + "\(activity.device ?? "no device"), \(activity.detail)")
    }
}

// MARK: - Spotlight

struct SettingsSpotlightSheet: View {
    @ObservedObject var spotlight: SpotlightService
    let selectedDevice: AndroidDevice?
    let apps: [AndroidApp]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SettingsSheetHeader(
                icon: "magnifyingglass",
                title: "Spotlight Search",
                subtitle:
                    "Find and open Android apps from Spotlight, Alfred, Raycast and the "
                    + "macOS app launcher."
            ) {
                SettingsSheetCloseButton { dismiss() }
            }

            Rectangle().fill(HubColor.stroke).frame(height: 1)

            VStack(alignment: .leading, spacing: 14) {
                SettingsToggleRow(
                    icon: "magnifyingglass",
                    title: "Index Android apps",
                    subtitle: "Add the selected device's installed apps to macOS Spotlight.",
                    isOn: Binding(
                        get: { spotlight.isEnabled },
                        set: { spotlight.setEnabled($0) }),
                    disabled: selectedDevice == nil)

                HubCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SettingsStatusRow(
                            dotColor: spotlight.isEnabled ? HubColor.textPrimary : HubColor.textTertiary,
                            title: "Status",
                            value: spotlight.isEnabled ? "Indexing on" : "Off",
                            valueTint: HubColor.textPrimary)
                        HubValueRow(
                            title: "Indexed apps", value: "\(spotlight.indexedCount)")
                        if let error = spotlight.lastError {
                            HubNote(text: error, icon: "exclamationmark.triangle")
                        }
                        HubNote(
                            text:
                                "Index entries are local to this Mac and refresh when the device "
                                + "reconnects. Nothing about your apps is uploaded.",
                            icon: "lock")
                    }
                    .padding(.vertical, 2)
                }

                HStack(spacing: 8) {
                    HubActionButton(
                        title: "Rebuild Index",
                        icon: "arrow.clockwise",
                        style: .secondary,
                        enabled: spotlight.isEnabled && selectedDevice != nil,
                        action: {
                            guard let selectedDevice else { return }
                            spotlight.rebuildIndex(apps: apps, deviceID: selectedDevice.id)
                        })
                    Spacer()
                }

                if let selectedDevice {
                    SettingsEmptyNote(
                        icon: "iphone.gen3",
                        text:
                            "Selected device: \(selectedDevice.name) · "
                            + "\(apps.count) app(s) available to index.")
                } else {
                    SettingsEmptyNote(
                        icon: "info.circle",
                        text: "Connect an Android device to index its apps.")
                }
            }
            .padding(18)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 520, height: 430)
    }
}

// MARK: - Feature alerts

struct SettingsFeatureAlertsSheet: View {
    @ObservedObject var preferences: AppPreferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SettingsSheetHeader(
                icon: "bell.badge",
                title: "Feature Alerts",
                subtitle: "Choose which AndroLaunch events appear as macOS notifications."
            ) {
                SettingsSheetCloseButton { dismiss() }
            }

            Rectangle().fill(HubColor.stroke).frame(height: 1)

            HubCard {
                VStack(spacing: 0) {
                    ForEach(
                        Array(AppFeatureAlert.allCases.enumerated()), id: \.element.id
                    ) { entry in
                        if entry.offset > 0 { HubDivider() }
                        SettingsToggleRow(
                            icon: entry.element.icon,
                            title: entry.element.title,
                            subtitle: entry.element.subtitle,
                            isOn: Binding(
                                get: { preferences.isAlertEnabled(entry.element) },
                                set: { preferences.setAlert(entry.element, enabled: $0) }))
                    }
                }
            }
            .padding(18)

            Spacer(minLength: 0)

            HubNote(
                text:
                    "Alert categories apply to notifications AndroLaunch posts itself. Mirrored "
                    + "Android notifications are governed by the Notifications section.",
                icon: "info.circle")
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .frame(width: 520, height: 430)
    }
}

// MARK: - Camera

struct SettingsCameraSheet: View {
    @ObservedObject var camera: CameraController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                SettingsSheetCloseButton { dismiss() }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            ScrollView(.vertical, showsIndicators: false) {
                CameraSettingsRows(state: camera.state, actions: camera.actions)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
            }
        }
        .frame(width: 540, height: 640)
        .background(HubColor.background)
    }
}

// MARK: - Licenses

struct SettingsLicensesSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Credit: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let url: String?
    }

    private let credits: [Credit] = [
        Credit(
            title: "scrcpy",
            detail: "Screen mirroring, camera and virtual displays. Apache License 2.0.",
            url: "https://github.com/Genymobile/scrcpy"),
        Credit(
            title: "Android platform-tools (ADB)",
            detail: "Device transport and shell access. Android SDK license.",
            url: "https://developer.android.com/tools/releases/platform-tools"),
        Credit(
            title: "AndroLaunch Comp",
            detail: "First-party Android companion installed over ADB. Part of AndroLaunch.",
            url: nil),
        Credit(
            title: "Apple frameworks",
            detail: "SwiftUI, AppKit, Network, ServiceManagement and UserNotifications.",
            url: nil),
    ]

    var body: some View {
        VStack(spacing: 0) {
            SettingsSheetHeader(
                icon: "doc.text",
                title: "Licenses & Acknowledgements",
                subtitle:
                    "AndroLaunch has no third-party runtime packages. It drives open tools "
                    + "installed by you."
            ) {
                SettingsSheetCloseButton { dismiss() }
            }

            Rectangle().fill(HubColor.stroke).frame(height: 1)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(credits) { credit in
                        HubCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(credit.title)
                                    .font(.hubRowTitle)
                                    .foregroundStyle(HubColor.textPrimary)
                                Text(credit.detail)
                                    .font(.hubCaption)
                                    .foregroundStyle(HubColor.textSecondary)
                                if let urlString = credit.url, let url = URL(string: urlString) {
                                    HubActionButton(
                                        title: "Open Project Page",
                                        icon: "arrow.up.right.square",
                                        style: .quiet,
                                        action: { NSWorkspace.shared.open(url) })
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    HubNote(
                        text:
                            "AndroLaunch is local-first: no account, no cloud service and no "
                            + "telemetry.",
                        icon: "lock")
                }
                .padding(18)
            }
        }
        .frame(width: 540, height: 520)
    }
}
