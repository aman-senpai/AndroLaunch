//
//  PackageInspectorSheet.swift
//  AndroLaunch
//
//  Pre-install inspection for APK / APKS / APKM / XAPK packages.
//  Everything shown is read from the archive or `aapt2`; missing details are
//  labelled as unavailable instead of being guessed.
//

import AppKit
import SwiftUI

struct PackageInspectorSheet: View {
    @ObservedObject var installer: PackageInstaller
    let device: AndroidDevice?

    @Environment(\.dismiss) private var dismiss
    @State private var showAllPermissions = false

    private var inspection: PackageInspection? { installer.inspection }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(HubColor.stroke)
                .frame(height: 1)
            ScrollView(.vertical, showsIndicators: false) {
                content
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
            Rectangle()
                .fill(HubColor.stroke)
                .frame(height: 1)
            footer
        }
        .frame(width: 470, height: 640)
        .background(HubColor.background)
        .onDisappear {
            if !installer.isInstalling {
                installer.reset()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 11) {
            HubIconTile(systemName: "shippingbox.fill", tint: HubColor.accent, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.hubCardTitle)
                    .foregroundStyle(HubColor.textPrimary)
                    .lineLimit(1)
                Text(headerSubtitle)
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(HubColor.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close package inspector")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var headerTitle: String {
        if let inspection { return inspection.displayName }
        if installer.isInspecting { return "Inspecting package…" }
        return "Install package"
    }

    private var headerSubtitle: String {
        if let inspection {
            var parts = [inspection.format.displayName, inspection.sizeText]
            parts.append("\(inspection.splitCount + 1) APK\(inspection.splitCount == 0 ? "" : "s")")
            return parts.joined(separator: " · ")
        }
        return "APK, APKS, APKM and XAPK are supported"
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if installer.isInspecting {
            inspectingCard
        } else if let inspection {
            VStack(alignment: .leading, spacing: HubMetric.sectionGap) {
                if let success = installer.lastSuccess {
                    successCard(success)
                }
                if let error = installer.lastError {
                    errorCard(error)
                }
                if let compatibility = installer.compatibilityNote(for: device) {
                    warningCard(compatibility)
                }
                packageCard(inspection)
                if !inspection.permissions.isEmpty {
                    permissionsCard(inspection.permissions)
                }
                installCard(inspection)
                targetCard
            }
        } else {
            emptyCard
        }
    }

    private var inspectingCard: some View {
        HubCard {
            HStack(spacing: 11) {
                ProgressView()
                    .controlSize(.small)
                    .tint(HubColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(installer.progressText ?? "Reading package…")
                        .font(.hubRowTitle)
                        .foregroundStyle(HubColor.textPrimary)
                    Text("Splits are extracted to a temporary folder and removed afterwards.")
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: HubMetric.sectionGap) {
            HubCard {
                HubEmptyState(
                    icon: "shippingbox",
                    title: "Choose a package to inspect",
                    subtitle:
                        "APK, APKS, APKM and XAPK files work. AndroLaunch shows the package name, version, minimum Android and permissions before installing.")
                HubActionButton(
                    title: "Choose Package…",
                    icon: "folder",
                    style: .quiet,
                    fullWidth: true
                ) {
                    installer.presentOpenPanel()
                }
                .padding(.top, 2)
            }
            if let error = installer.lastError {
                errorCard(error)
            }
        }
    }

    private func successCard(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(HubColor.success)
            Text(message)
                .font(.hubRowTitle)
                .foregroundStyle(HubColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: HubMetric.cardRadius, style: .continuous)
                .fill(HubColor.greenWash))
        .overlay(
            RoundedRectangle(cornerRadius: HubMetric.cardRadius, style: .continuous)
                .strokeBorder(HubColor.success.opacity(0.28), lineWidth: 1))
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HubColor.danger)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't install")
                    .font(.hubRowTitle)
                    .foregroundStyle(HubColor.textPrimary)
                Text(message)
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: HubMetric.cardRadius, style: .continuous)
                .fill(HubColor.dangerSoft))
        .overlay(
            RoundedRectangle(cornerRadius: HubMetric.cardRadius, style: .continuous)
                .strokeBorder(HubColor.danger.opacity(0.28), lineWidth: 1))
    }

    private func warningCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HubColor.warning)
                .padding(.top, 1)
            Text(message)
                .font(.hubCaption)
                .foregroundStyle(HubColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: HubMetric.cardRadius, style: .continuous)
                .fill(HubColor.warningSoft))
        .overlay(
            RoundedRectangle(cornerRadius: HubMetric.cardRadius, style: .continuous)
                .strokeBorder(HubColor.warning.opacity(0.25), lineWidth: 1))
    }

    // MARK: - Cards

    private func packageCard(_ inspection: PackageInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader("Package")
            HubCard(padding: 12) {
                VStack(spacing: 0) {
                    HubValueRow(
                        title: "Package name",
                        value: inspection.packageName ?? "Not available",
                        valueTint: inspection.packageName == nil
                            ? HubColor.warning : HubColor.textPrimary)
                    divider
                    HubValueRow(
                        title: "Version",
                        value: versionText(inspection),
                        valueTint: HubColor.textPrimary)
                    divider
                    HubValueRow(
                        title: "Minimum Android",
                        value: inspection.minSDK.map { "API \($0)" } ?? "Not available",
                        valueTint: inspection.minSDK == nil
                            ? HubColor.textTertiary : HubColor.textPrimary)
                    if let activity = inspection.launchableActivity {
                        divider
                        HubValueRow(
                            title: "Launch activity",
                            value: activity,
                            valueTint: HubColor.textSecondary)
                    }
                }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(HubColor.stroke)
            .frame(height: 1)
            .padding(.leading, HubMetric.rowPaddingH)
    }

    private func versionText(_ inspection: PackageInspection) -> String {
        if let versionName = inspection.versionName, let versionCode = inspection.versionCode {
            return "\(versionName) (\(versionCode))"
        }
        return inspection.versionName ?? inspection.versionCode ?? "Not available"
    }

    private func permissionsCard(_ permissions: [String]) -> some View {
        let visible = showAllPermissions ? permissions : Array(permissions.prefix(6))
        return VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader("Permissions") {
                Text("\(permissions.count)")
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textTertiary)
            }
            HubCard(padding: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { index, permission in
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(HubColor.textTertiary)
                            Text(permission)
                                .font(.hubMono)
                                .foregroundStyle(HubColor.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 5)
                        if index < visible.count - 1 {
                            divider
                        }
                    }
                    if permissions.count > 6 {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                showAllPermissions.toggle()
                            }
                        } label: {
                            Text(
                                showAllPermissions
                                    ? "Show fewer permissions"
                                    : "Show all \(permissions.count) permissions"
                            )
                            .font(.hubCaption)
                            .foregroundStyle(HubColor.accent)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                }
            }
        }
    }

    private func installCard(_ inspection: PackageInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader("Install")
            HubCard(padding: 12) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        infoPill(
                            icon: "shippingbox",
                            text: "\(inspection.splitCount + 1) APK\(inspection.splitCount == 0 ? "" : "s")",
                            tint: HubColor.accent)
                        infoPill(
                            icon: "internaldrive",
                            text: inspection.sizeText,
                            tint: HubColor.textSecondary)
                        if inspection.usesMultipleAPKs {
                            infoPill(
                                icon: "square.stack.3d.up",
                                text: "install-multiple",
                                tint: HubColor.success)
                        }
                    }

                    if let aapt2Path = inspection.aapt2Path {
                        noteRow(
                            icon: "checkmark.circle",
                            tint: HubColor.success,
                            text: "Package details read with aapt2 at \(aapt2Path).")
                    } else {
                        noteRow(
                            icon: "exclamationmark.circle",
                            tint: HubColor.warning,
                            text:
                                "aapt2 is not available, so package details may be missing. Install Android SDK build-tools to read the full manifest.")
                    }

                    ForEach(Array(inspection.notes.enumerated()), id: \.offset) { _, note in
                        noteRow(icon: "info.circle", tint: HubColor.textTertiary, text: note)
                    }

                    if inspection.format == .xapk || inspection.format == .apks
                        || inspection.format == .apkm
                    {
                        noteRow(
                            icon: "info.circle",
                            tint: HubColor.textTertiary,
                            text:
                                "The archive was extracted to a temporary folder that is removed after installing.")
                    }
                }
            }
        }
    }

    private func infoPill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.12)))
    }

    private func noteRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)
            Text(text)
                .font(.hubCaption)
                .foregroundStyle(HubColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader("Target")
            HubCard(padding: 12) {
                HStack(spacing: 10) {
                    HubIconTile(
                        systemName: device?.isWirelessTransport == true ? "wifi" : "iphone.gen3",
                        tint: device?.isConnected == true ? HubColor.success : HubColor.warning,
                        size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device?.name ?? "No phone connected")
                            .font(.hubRowTitle)
                            .foregroundStyle(HubColor.textPrimary)
                        Text(targetSubtitle)
                            .font(.hubCaption)
                            .foregroundStyle(HubColor.textSecondary)
                    }
                    Spacer(minLength: 6)
                    HubPill(
                        text: device == nil
                            ? "No device"
                            : (device?.isConnected == true ? "Connected" : "Offline"),
                        tint: device?.isConnected == true
                            ? HubColor.success : HubColor.warning)
                }
            }
        }
    }

    private var targetSubtitle: String {
        guard let device else {
            return "Connect a phone in the Devices tab to install."
        }
        var parts: [String] = []
        if let version = device.androidVersion { parts.append("Android \(version)") }
        parts.append(device.isWirelessTransport ? "Wi-Fi" : "USB")
        parts.append("Installs with adb on this Mac")
        return parts.joined(separator: " · ")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            HubActionButton(
                title: "Choose Another…",
                icon: "folder",
                style: .secondary,
                enabled: !installer.isInstalling
            ) {
                installer.presentOpenPanel()
            }

            Spacer(minLength: 8)

            if installer.isInstalling {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(HubColor.accent)
                    Text(installer.progressText ?? "Installing…")
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textSecondary)
                        .lineLimit(1)
                }
                HubActionButton(
                    title: "Cancel Install",
                    icon: "xmark",
                    style: .destructive
                ) {
                    installer.cancelInstall()
                }
            } else if installer.lastSuccess != nil {
                if let packageID = installer.installedPackageName,
                    let device,
                    device.isConnected
                {
                    HubActionButton(title: "Open App", icon: "play.fill", style: .quiet) {
                        AppWindowController.shared.openApp(
                            packageID: packageID,
                            appName: installer.inspection?.displayName ?? packageID,
                            deviceID: device.id,
                            mode: .meldWindow)
                        dismiss()
                    }
                }
                HubActionButton(title: "Done", style: .primary) {
                    dismiss()
                }
            } else {
                HubActionButton(title: "Close", style: .secondary) {
                    dismiss()
                }
                HubActionButton(
                    title: installButtonTitle,
                    icon: "arrow.down.circle.fill",
                    style: .primary,
                    enabled: canInstall
                ) {
                    guard let device else { return }
                    installer.install(deviceID: device.id)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var canInstall: Bool {
        inspection != nil && device != nil && device?.isConnected == true
            && !installer.isInspecting && !installer.isInstalling
    }

    private var installButtonTitle: String {
        guard let device else { return "Connect a Phone" }
        guard device.isConnected else { return "Phone Offline" }
        return "Install on \(device.name)"
    }
}
