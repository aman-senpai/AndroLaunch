//
//  StorageView.swift
//  AndroLaunch
//
//  Compact storage sheet for one device: used/total ring, the internal category
//  split, removable volumes and the top folder list. The full analytics surface
//  (donut + drill-down) lives in the dedicated storage window.
//
//  Uses only the shared design system (HubTheme / HubCard / HubProgressBar …).
//

import AppKit
import SwiftUI

struct StorageView: View {
    let deviceID: String
    var deviceName: String? = nil

    @ObservedObject private var service = StorageService.shared
    @ObservedObject private var finder = FinderMirrorService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: HubMetric.sectionGap) {
                    capacityCard
                    categoriesCard
                    removableCard
                    foldersCard
                    largestCard
                    HubNote(
                        text:
                            "Totals are exact from `df`; folders are measured over adb. Android hides app-private data, so folder totals can differ from the phone's own Settings screen. Finder access is a local mirror, not a system File Provider mount.",
                        icon: "info.circle")
                }
                .padding(.horizontal, HubMetric.pagePadding)
                .padding(.bottom, 22)
            }
        }
        .frame(width: 480, height: 660)
        .background(HubColor.background)
        .onAppear {
            if service.snapshot?.deviceID != deviceID { service.load(deviceID: deviceID) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 11) {
            HubIconTile(systemName: "internaldrive", tint: HubColor.accent, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Phone storage")
                    .font(.hubCardTitle)
                    .foregroundStyle(HubColor.textPrimary)
                Text(deviceName ?? deviceID)
                    .font(.hubCardSubtitle)
                    .foregroundStyle(HubColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if service.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Reading storage")
            } else {
                HubActionButton(
                    title: "Refresh", icon: "arrow.clockwise", style: .secondary
                ) {
                    service.load(deviceID: deviceID)
                }
            }
            Button {
                StorageSheetController.shared.close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(HubColor.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close storage")
            .help("Close")
        }
        .padding(.horizontal, HubMetric.pagePadding)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    // MARK: - Capacity

    private var capacityCard: some View {
        HubCard(tint: HubColor.accent) {
            VStack(alignment: .leading, spacing: 12) {
                if let snapshot = service.snapshot {
                    HStack(alignment: .center, spacing: 18) {
                        capacityRing(snapshot)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(snapshot.usedOfTotalText)
                                .font(.hubRowTitle)
                                .foregroundStyle(HubColor.textPrimary)
                            Text(snapshot.freeText)
                                .font(.hubCardSubtitle)
                                .foregroundStyle(HubColor.textSecondary)
                            HStack(spacing: 6) {
                                HubPill(
                                    text: snapshot.source == .companion
                                        ? "Companion" : "adb",
                                    tint: snapshot.source == .companion
                                        ? HubColor.success : HubColor.textSecondary)
                                if snapshot.isPartial {
                                    HubPill(
                                        text: "Partial", tint: HubColor.warning,
                                        icon: "exclamationmark.circle.fill")
                                }
                            }
                            Text(
                                "Updated \(snapshot.scannedAt.formatted(date: .omitted, time: .shortened))"
                            )
                            .font(.hubCaption)
                            .foregroundStyle(HubColor.textTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        HubActionButton(
                            title: "Open Analytics", icon: "chart.pie", style: .quiet
                        ) {
                            PanelRouter.openStorageAnalytics()
                        }
                        HubActionButton(
                            title: "Open in Finder", icon: "folder", style: .secondary
                        ) {
                            FinderMirrorService.shared.open(
                                deviceID: deviceID, scope: .userFiles)
                        }
                        Spacer(minLength: 0)
                    }
                } else if service.isLoading {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Reading storage…")
                            .font(.hubBody)
                            .foregroundStyle(HubColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HubEmptyState(
                            icon: "internaldrive",
                            title: "Storage is not available",
                            subtitle: service.lastError
                                ?? "Connect the device and try again.")
                        HubActionButton(
                            title: "Try again", icon: "arrow.clockwise", style: .secondary
                        ) {
                            service.load(deviceID: deviceID)
                        }
                    }
                }
            }
        }
    }

    private func capacityRing(_ snapshot: StorageSnapshot) -> some View {
        ZStack {
            Circle()
                .stroke(HubColor.controlTrack, lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0.02, snapshot.usedFraction))
                .stroke(
                    colorForUsed(snapshot.usedFraction),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(Int((snapshot.usedFraction * 100).rounded()))%")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(HubColor.textPrimary)
                Text("used")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(HubColor.textTertiary)
            }
        }
        .frame(width: 84, height: 84)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Storage \(Int((snapshot.usedFraction * 100).rounded())) percent used, \(snapshot.usedOfTotalText)"
        )
    }

    // MARK: - Categories

    @ViewBuilder
    private var categoriesCard: some View {
        if let volume = service.snapshot?.internalVolume, !volume.categories.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HubSectionHeader("Breakdown")
                HubCard(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach(Array(volume.categories.enumerated()), id: \.element.id) {
                            index, category in
                            HStack(spacing: 9) {
                                Circle()
                                    .fill(tint(for: category.role))
                                    .frame(width: 7, height: 7)
                                Text(category.title)
                                    .font(.hubRowTitle)
                                    .foregroundStyle(HubColor.textPrimary)
                                if category.isPartial {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 8.5))
                                        .foregroundStyle(HubColor.warning)
                                }
                                Spacer(minLength: 8)
                                Text(PhoneFormat.bytes(category.bytes))
                                    .font(.hubCaption)
                                    .foregroundStyle(HubColor.textSecondary)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, HubMetric.rowPaddingH)
                            .padding(.vertical, 9)
                            if index < volume.categories.count - 1 { HubDivider() }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Removable volumes

    @ViewBuilder
    private var removableCard: some View {
        if let volumes = service.snapshot?.removableVolumes, !volumes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HubSectionHeader("Removable storage")
                ForEach(volumes) { volume in
                    HubCard(padding: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                HubIconTile(systemName: "sdcard.fill", size: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(volume.title)
                                        .font(.hubRowTitle)
                                        .foregroundStyle(HubColor.textPrimary)
                                    Text(volume.mountPath)
                                        .font(.hubCaption)
                                        .foregroundStyle(HubColor.textTertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(volume.usedPercentText)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(HubColor.textPrimary)
                                    .monospacedDigit()
                            }
                            HubProgressBar(
                                value: volume.usedFraction, tint: HubColor.success, height: 4)
                            Text(
                                "\(volume.usedOfTotalText) · \(volume.freeText)"
                            )
                            .font(.hubCaption)
                            .foregroundStyle(HubColor.textSecondary)
                            HStack(spacing: 8) {
                                HubActionButton(
                                    title: "Open", icon: "folder", style: .secondary
                                ) {
                                    FinderMirrorService.shared.open(
                                        deviceID: deviceID, scope: .sdCard)
                                }
                                HubActionButton(
                                    title: "Mount", icon: "arrow.up.to.line", style: .quiet
                                ) {
                                    FinderMirrorService.shared.mount(
                                        deviceID: deviceID, scope: .sdCard)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Folders

    private var foldersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader("Top folders")
            HubCard(padding: 6) {
                VStack(spacing: 0) {
                    if let snapshot = service.snapshot, !snapshot.folders.isEmpty {
                        let folders = Array(snapshot.folders.prefix(8))
                        ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                            folderRow(folder, snapshot: snapshot)
                            if index < folders.count - 1 {
                                HubDivider()
                            }
                        }
                    } else if service.isLoading {
                        loadingRow("Measuring folders…")
                    } else {
                        HubEmptyState(
                            icon: "folder",
                            title: "No folder breakdown",
                            subtitle:
                                "The phone did not expose its shared storage to this scan.")
                            .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private func folderRow(_ folder: StorageFolder, snapshot: StorageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(HubColor.accent)
                Text(folder.name)
                    .font(.hubRowTitle)
                    .foregroundStyle(HubColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(PhoneFormat.bytes(folder.bytes))
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textSecondary)
                    .monospacedDigit()
            }
            HubProgressBar(
                value: snapshot.fraction(for: folder), tint: HubColor.accent, height: 4)
        }
        .padding(.horizontal, HubMetric.rowPaddingH)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Largest media

    @ViewBuilder
    private var largestCard: some View {
        if let snapshot = service.snapshot, !snapshot.largestItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HubSectionHeader("Largest media files")
                HubCard(padding: 6) {
                    VStack(spacing: 0) {
                        let items = Array(snapshot.largestItems.prefix(8))
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 10) {
                                Image(systemName: iconForMedia(item.name))
                                    .font(.system(size: 12))
                                    .foregroundStyle(HubColor.textSecondary)
                                    .frame(width: 18)
                                Text(item.name)
                                    .font(.hubBody)
                                    .foregroundStyle(HubColor.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 8)
                                Text(PhoneFormat.bytes(item.bytes))
                                    .font(.hubCaption)
                                    .foregroundStyle(HubColor.textSecondary)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, HubMetric.rowPaddingH)
                            .padding(.vertical, 9)
                            if index < items.count - 1 { HubDivider() }
                        }
                    }
                }
                HubNote(
                    text:
                        "MediaStore files above 10 MB, largest first. App-private data is not listed.",
                    icon: "photo")
            }
        }
    }

    private func iconForMedia(_ name: String) -> String {
        let lowered = name.lowercased()
        if lowered.hasSuffix(".mp4") || lowered.hasSuffix(".mkv") || lowered.hasSuffix(".mov") {
            return "film"
        }
        if lowered.hasSuffix(".png") || lowered.hasSuffix(".jpg")
            || lowered.hasSuffix(".jpeg") || lowered.hasSuffix(".webp")
        {
            return "photo"
        }
        return "doc"
    }

    private func loadingRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.hubBody)
                .foregroundStyle(HubColor.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HubMetric.rowPaddingH)
        .padding(.vertical, 16)
    }

    private func colorForUsed(_ fraction: Double) -> Color {
        if fraction >= 0.92 { return HubColor.danger }
        if fraction >= 0.8 { return HubColor.warning }
        return HubColor.accent
    }

    private func tint(for role: StorageCategoryRole) -> Color {
        switch role {
        case .apps: return HubColor.accent
        case .userFiles: return HubColor.success
        case .system: return HubColor.textTertiary
        }
    }
}

// MARK: - Presentation

/// Presents `StorageView` in its own small window.
///
/// The menu row and Settings can open it without the Hub (the app is an accessory
/// app), and a single controller keeps the window reused across devices instead
/// of stacking copies.
final class StorageSheetController {

    static let shared = StorageSheetController()

    private var window: NSWindow?

    private init() {}

    /// Closes the storage window (also used by the in-sheet close button).
    func close() {
        window?.orderOut(nil)
    }

    func present(deviceID: String, deviceName: String?) {
        let resolvedTitle = deviceName.map { "Storage — \($0)" } ?? "Phone storage"
        if let window {
            window.contentView = NSHostingView(
                rootView: StorageView(deviceID: deviceID, deviceName: deviceName))
            window.title = resolvedTitle
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 660),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = resolvedTitle
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(HubColor.card)
        window.contentView = NSHostingView(
            rootView: StorageView(deviceID: deviceID, deviceName: deviceName))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
