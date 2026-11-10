//
//  StorageAnalyticsWindowController.swift
//  AndroLaunch
//
//  Dedicated storage analytics window: capacity donut, colour-coded category
//  legend with drill-down, removable-volume sections and a folder detail list.
//
//  Pure SwiftUI donut (no chart framework), accessible labels, and a
//  deterministic preview initializer so the design snapshot renderer can render
//  the window without a phone.
//

import AppKit
import SwiftUI

// MARK: - Pane

enum StorageAnalyticsPane: Equatable {
    case overview
    case category(volumeID: String, role: StorageCategoryRole)
    case folder(volumeID: String, path: String, title: String)
}

// MARK: - View

struct StorageAnalyticsView: View {
    let deviceID: String
    private let previewSnapshot: StorageSnapshot?
    private let deviceNameOverride: String?
    /// Set only in snapshots: opens directly on this category's drill-down.
    private let focusedCategory: StorageCategoryRole?
    private let embedded: Bool

    @ObservedObject private var service = StorageService.shared
    @Environment(\.hubSnapshotMode) private var snapshotMode
    @State private var stack: [StorageAnalyticsPane] = []

    /// Live device.
    init(deviceID: String) {
        self.deviceID = deviceID
        self.previewSnapshot = nil
        self.deviceNameOverride = nil
        self.focusedCategory = nil
        self.embedded = false
    }

    /// Expanded inline under the Storage card: no window chrome, header or
    /// nested scroll, so the menu-bar panel owns the scroll and the back stack.
    init(deviceID: String, embedded: Bool) {
        self.deviceID = deviceID
        self.previewSnapshot = nil
        self.deviceNameOverride = nil
        self.focusedCategory = nil
        self.embedded = embedded
    }

    /// Deterministic snapshot for the DEBUG renderer. `focusedCategory` renders
    /// the folder-breakdown screen (for example `.userFiles`).
    init(
        previewSnapshot: StorageSnapshot,
        deviceName: String? = nil,
        focusedCategory: StorageCategoryRole? = nil
    ) {
        self.deviceID = previewSnapshot.deviceID
        self.previewSnapshot = previewSnapshot
        self.deviceNameOverride = deviceName
        self.focusedCategory = focusedCategory
        self.embedded = false
        if let focusedCategory {
            let volumeID = previewSnapshot.internalVolume?.id ?? "internal"
            self._stack = State(
                initialValue: [
                    .category(volumeID: volumeID, role: focusedCategory)
                ])
        } else {
            self._stack = State(initialValue: [])
        }
    }

    // MARK: Body

    var body: some View {
        Group {
            if embedded {
                contentColumn
            } else {
                VStack(spacing: 0) {
                    header
                    Rectangle()
                        .fill(HubColor.stroke)
                        .frame(height: 1)
                    if snapshotMode {
                        contentColumn
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            contentColumn
                        }
                    }
                }
                .background(HubColor.background)
                .frame(minWidth: 500, minHeight: 640)
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    private var contentColumn: some View {
        content
            .padding(.horizontal, HubMetric.pagePadding)
            .padding(.top, 16)
            .padding(.bottom, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentPane: StorageAnalyticsPane { stack.last ?? .overview }

    private var snapshot: StorageSnapshot? {
        if let previewSnapshot { return previewSnapshot }
        guard let snapshot = service.snapshot, snapshot.deviceID == deviceID else {
            return nil
        }
        return snapshot
    }

    private var resolvedDeviceName: String {
        deviceNameOverride
            ?? HubStore.shared.devices.first(where: { $0.id == deviceID })?.name
            ?? deviceID
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 11) {
            if !stack.isEmpty {
                Button {
                    popPane()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HubColor.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back")
                .accessibilityLabel("Back")
            }

            HubIconTile(
                systemName: headerIcon,
                tint: HubColor.accent,
                size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.hubCardTitle)
                    .foregroundStyle(HubColor.textPrimary)
                    .lineLimit(1)
                Text(headerSubtitle)
                    .font(.hubCardSubtitle)
                    .foregroundStyle(HubColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let focusedSizeText {
                Text(focusedSizeText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HubColor.textPrimary)
                    .monospacedDigit()
            } else if previewSnapshot == nil {
                HubActionButton(
                    title: service.isLoading ? "Reading…" : "Refresh",
                    icon: "arrow.clockwise",
                    style: .secondary,
                    enabled: !service.isLoading
                ) {
                    service.load(deviceID: deviceID)
                }
            }
            Button {
                StorageAnalyticsWindowController.shared.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(HubColor.textTertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close storage analytics")
            .accessibilityLabel("Close storage analytics")
        }
        .padding(.horizontal, HubMetric.pagePadding)
        .padding(.top, 16)
        .padding(.bottom, 13)
    }

    private var headerIcon: String {
        switch currentPane {
        case .overview: return "chart.pie.fill"
        case .category(_, let role): return role.icon
        case .folder: return "folder.fill"
        }
    }

    private var headerTitle: String {
        switch currentPane {
        case .overview: return "Storage analytics"
        case .category(_, let role): return role.title
        case .folder(_, _, let title): return title
        }
    }

    private var headerSubtitle: String {
        switch currentPane {
        case .overview: return resolvedDeviceName
        case .category:
            guard let volume = focusedVolume else { return resolvedDeviceName }
            return "\(volume.title) · \(resolvedDeviceName)"
        case .folder(_, let path, _):
            return path
        }
    }

    private var focusedVolume: StorageVolume? {
        guard case .category(let volumeID, _) = currentPane else { return nil }
        return snapshot?.allVolumes.first(where: { $0.id == volumeID })
    }

    /// Size shown in the header for a category drill-down (the category's bytes,
    /// not the whole volume).
    private var focusedSizeText: String? {
        guard case .category(let volumeID, let role) = currentPane,
            let volume = snapshot?.allVolumes.first(where: { $0.id == volumeID }),
            let category = volume.categories.first(where: { $0.role == role })
        else { return nil }
        return PhoneFormat.bytes(category.bytes)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch currentPane {
        case .overview:
            overviewContent
        case .category(let volumeID, let role):
            categoryContent(volumeID: volumeID, role: role)
        case .folder(_, let path, let title):
            folderContent(path: path, title: title)
        }
    }

    @ViewBuilder
    private var overviewContent: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: HubMetric.sectionGap) {
                if let volume = snapshot.internalVolume {
                    StorageVolumeCard(
                        volume: volume,
                        title: volume.title,
                        subtitle: resolvedDeviceName,
                        showsFolders: true,
                        onCategory: { role in
                            push(.category(volumeID: volume.id, role: role))
                        },
                        onFolder: { folder in
                            pushFolder(volume: volume, folder: folder)
                        })
                }

                ForEach(snapshot.removableVolumes) { volume in
                    StorageVolumeCard(
                        volume: volume,
                        title: volume.title,
                        subtitle: volume.mountPath,
                        showsFolders: true,
                        onCategory: { role in
                            push(.category(volumeID: volume.id, role: role))
                        },
                        onFolder: { folder in
                            pushFolder(volume: volume, folder: folder)
                        })
                }

                if !snapshot.largestItems.isEmpty {
                    largestFilesCard(snapshot.largestItems)
                }

                if !snapshot.partialReasons.isEmpty {
                    HubCard(tint: HubColor.warning) {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(HubColor.warning)
                                Text("Partial measurements")
                                    .font(.hubRowTitle)
                                    .foregroundStyle(HubColor.textPrimary)
                            }
                            ForEach(snapshot.partialReasons, id: \.self) { reason in
                                Text("• \(reason)")
                                    .font(.hubCaption)
                                    .foregroundStyle(HubColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                HubNote(
                    text:
                        "Totals come from the phone's `df`; folders come from `du` over adb. Android hides app-private data, so folder totals can differ from the phone's own Settings screen. The Finder mirror copies user folders locally — it is not a system File Provider mount.",
                    icon: "info.circle")
            }
        } else if service.isLoading {
            loadingCard(text: "Reading volumes and folder sizes…")
        } else {
            errorCard
        }
    }

    private func categoryContent(volumeID: String, role: StorageCategoryRole) -> some View {
        VStack(alignment: .leading, spacing: HubMetric.sectionGap) {
            if let volume = snapshot?.allVolumes.first(where: { $0.id == volumeID }),
                let category = volume.categories.first(where: { $0.role == role })
            {
                HubCard(tint: storageTint(for: role)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(storageTint(for: role))
                                .frame(width: 9, height: 9)
                            Text(role.title)
                                .font(.hubCardTitle)
                                .foregroundStyle(HubColor.textPrimary)
                            if category.isPartial {
                                HubPill(text: "Partial", tint: HubColor.warning)
                            }
                            Spacer(minLength: 6)
                            Text(PhoneFormat.bytes(category.bytes))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(HubColor.textPrimary)
                                .monospacedDigit()
                        }
                        Text(
                            "\(volume.title) · \(volume.mountPath) · \(categoryShareText(category: category, volume: volume))"
                        )
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textSecondary)
                    }
                }

                if let drilldownNote = role.drilldownNote {
                    HubNote(text: drilldownNote, icon: "info.circle")
                }

                if role == .userFiles {
                    let folders = folderSource(volume: volume)
                    if folders.isEmpty {
                        HubEmptyState(
                            icon: "folder",
                            title: "No folder breakdown",
                            subtitle:
                                "Android did not expose this volume's folders to adb. The File Explorer can still browse them without sizes.")
                    } else {
                        foldersCard(
                            folders: folders,
                            totalBytes: volume.totalBytes,
                            onOpen: { folder in
                                pushFolder(volume: volume, folder: folder)
                            })
                    }
                } else if role == .system {
                    largestFilesCardFallback()
                }
            } else {
                errorCard
            }
        }
    }

    private func folderContent(path: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: HubMetric.sectionGap) {
            if previewSnapshot != nil {
                HubNote(
                    text:
                        "Folder contents appear after a live scan. In the app this screen lists each child folder with its size and lets you keep drilling down.",
                    icon: "folder")
            } else if service.isLoadingFolderDetail {
                loadingCard(text: "Measuring \(title)…")
            } else if let detail = service.folderDetail, detail.path == path {
                foldersCard(
                    folders: detail.folders,
                    totalBytes: snapshot?.totalBytes ?? 0,
                    onOpen: { folder in
                        push(
                            .folder(
                                volumeID: currentPaneVolumeID,
                                path: (path as NSString).appendingPathComponent(folder.name),
                                title: folder.name))
                        service.loadChildren(
                            deviceID: deviceID,
                            path: (path as NSString).appendingPathComponent(folder.name),
                            title: folder.name)
                    })
            } else if let error = service.folderDetailError {
                HubCard(tint: HubColor.warning) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Folder unavailable")
                            .font(.hubRowTitle)
                            .foregroundStyle(HubColor.textPrimary)
                        Text(error)
                            .font(.hubCaption)
                            .foregroundStyle(HubColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                loadingCard(text: "Measuring \(title)…")
            }
            HubNote(
                text:
                    "Sizes come from `du -sk` on the phone. Virtual files, symlinks and app-private folders may be reported at their mount size or skipped.",
                icon: "info.circle")
        }
    }

    private var currentPaneVolumeID: String {
        if case .folder(let volumeID, _, _) = currentPane { return volumeID }
        return ""
    }

    // MARK: Cards

    private func foldersCard(
        folders: [StorageFolder],
        totalBytes: Int64,
        onOpen: @escaping (StorageFolder) -> Void
    ) -> some View {
        HubCard(padding: 6) {
            VStack(spacing: 0) {
                ForEach(Array(folders.prefix(14).enumerated()), id: \.element.id) {
                    index, folder in
                    Button {
                        onOpen(folder)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(HubColor.accent)
                                .frame(width: 18)
                            Text(folder.name)
                                .font(.hubRowTitle)
                                .foregroundStyle(HubColor.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(PhoneFormat.bytes(folder.bytes))
                                .font(.hubCaption)
                                .foregroundStyle(HubColor.textSecondary)
                                .monospacedDigit()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(HubColor.textTertiary)
                        }
                        .padding(.horizontal, HubMetric.rowPaddingH)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(folder.name), \(PhoneFormat.bytes(folder.bytes))")
                    if index < min(folders.count, 14) - 1 {
                        HubDivider()
                    }
                }
            }
        }
    }

    private func largestFilesCard(_ items: [StorageItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader("Largest media files")
            HubCard(padding: 6) {
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(8).enumerated()), id: \.element.id) {
                        index, item in
                        HStack(spacing: 10) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 11))
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
                        if index < min(items.count, 8) - 1 { HubDivider() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func largestFilesCardFallback() -> some View {
        if let items = snapshot?.largestItems, !items.isEmpty {
            largestFilesCard(items)
        } else {
            HubNote(
                text:
                    "System & Others is the remainder of the volume: system image, caches, filesystem overhead and data Android does not expose to adb.",
                icon: "gearshape.2")
        }
    }

    private func loadingCard(text: String) -> some View {
        HubCard {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(text)
                    .font(.hubBody)
                    .foregroundStyle(HubColor.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
        }
    }

    private var errorCard: some View {
        HubCard {
            VStack(alignment: .leading, spacing: 10) {
                HubEmptyState(
                    icon: "internaldrive",
                    title: "Storage is not available",
                    subtitle: service.lastError
                        ?? "Connect the device and try again.")
                if previewSnapshot == nil {
                    HubActionButton(
                        title: "Try again", icon: "arrow.clockwise", style: .secondary
                    ) {
                        service.load(deviceID: deviceID)
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private func folderSource(volume: StorageVolume) -> [StorageFolder] {
        if volume.kind == .internalStorage {
            return snapshot?.folders ?? volume.folders
        }
        return volume.folders
    }

    private func folderBasePath(for volume: StorageVolume) -> String {
        switch volume.kind {
        case .internalStorage, .sharedStorage:
            return "/storage/emulated/0"
        case .removable:
            return volume.mountPath
        }
    }

    private func categoryShareText(
        category: StorageCategory, volume: StorageVolume
    ) -> String {
        guard volume.usedBytes > 0 else { return "no measured data" }
        let share = Double(category.bytes) / Double(volume.usedBytes)
        return "\(Int((share * 100).rounded()))% of used space"
    }

    private func storageTint(for role: StorageCategoryRole) -> Color {
        switch role {
        case .apps: return HubColor.accent
        case .userFiles: return HubColor.success
        case .system: return HubColor.textTertiary
        }
    }

    private func loadIfNeeded() {
        guard previewSnapshot == nil else { return }
        if service.snapshot?.deviceID != deviceID, !service.isLoading {
            service.load(deviceID: deviceID)
        }
    }

    // MARK: Navigation

    private func push(_ pane: StorageAnalyticsPane) {
        stack.append(pane)
    }

    private func pushFolder(volume: StorageVolume, folder: StorageFolder) {
        let base = folderBasePath(for: volume)
        let path = (base as NSString).appendingPathComponent(folder.name)
        push(.folder(volumeID: volume.id, path: path, title: folder.name))
        if previewSnapshot == nil {
            service.loadChildren(deviceID: deviceID, path: path, title: folder.name)
        }
    }

    private func popPane() {
        guard !stack.isEmpty else { return }
        let popped = stack.removeLast()
        if case .folder = popped, previewSnapshot == nil {
            service.clearFolderDetail()
        }
    }
}

// MARK: - Volume card

private struct StorageVolumeCard: View {
    let volume: StorageVolume
    let title: String
    let subtitle: String
    let showsFolders: Bool
    let onCategory: (StorageCategoryRole) -> Void
    let onFolder: (StorageFolder) -> Void

    var body: some View {
        HubCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.hubCardTitle)
                        .foregroundStyle(HubColor.textPrimary)
                    Spacer(minLength: 8)
                    if volume.hasOwnCapacity {
                        Text(volume.usedPercentText)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(HubColor.textPrimary)
                            .monospacedDigit()
                    }
                }
                HStack(alignment: .center, spacing: 20) {
                    StorageDonutChart(volume: volume, size: 148)
                    VStack(alignment: .leading, spacing: 4) {
                        if volume.hasOwnCapacity {
                            Text(volume.usedOfTotalText)
                                .font(.hubRowTitle)
                                .foregroundStyle(HubColor.textPrimary)
                            Text(volume.freeText)
                                .font(.hubCaption)
                                .foregroundStyle(HubColor.textSecondary)
                                .padding(.bottom, 4)
                        } else {
                            Text(subtitle)
                                .font(.hubCaption)
                                .foregroundStyle(HubColor.textSecondary)
                                .padding(.bottom, 4)
                        }
                        ForEach(volume.categories) { category in
                            categoryRow(category)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if showsFolders, !volume.folders.isEmpty {
                    Rectangle()
                        .fill(HubColor.stroke)
                        .frame(height: 1)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("TOP FOLDERS")
                                .font(.hubSectionLabel)
                                .tracking(0.9)
                                .foregroundStyle(HubColor.textTertiary)
                            Spacer()
                            Text("Tap to drill down")
                                .font(.system(size: 9.5))
                                .foregroundStyle(HubColor.textTertiary)
                        }
                        .padding(.bottom, 4)
                        ForEach(Array(volume.folders.prefix(6).enumerated()), id: \.element.id) {
                            index, folder in
                            Button {
                                onFolder(folder)
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(HubColor.accent)
                                        .frame(width: 16)
                                    Text(folder.name)
                                        .font(.hubBody)
                                        .foregroundStyle(HubColor.textPrimary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    Text(PhoneFormat.bytes(folder.bytes))
                                        .font(.hubCaption)
                                        .foregroundStyle(HubColor.textSecondary)
                                        .monospacedDigit()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8.5, weight: .semibold))
                                        .foregroundStyle(HubColor.textTertiary)
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                "\(folder.name), \(PhoneFormat.bytes(folder.bytes))")
                            if index < min(volume.folders.count, 6) - 1 {
                                HubDivider()
                            }
                        }
                    }
                }

                if volume.isPartial {
                    HubNote(
                        text:
                            "Some values on this volume are partial; Android did not expose every folder to adb.",
                        icon: "exclamationmark.circle")
                }
            }
        }
    }

    private func categoryRow(_ category: StorageCategory) -> some View {
        Button {
            onCategory(category.role)
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(tint(for: category.role))
                    .frame(width: 7, height: 7)
                Text(category.title)
                    .font(.hubRowSubtitle)
                    .foregroundStyle(HubColor.textPrimary)
                    .lineLimit(1)
                if category.isPartial {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle(HubColor.warning)
                        .help("Partial measurement")
                }
                Spacer(minLength: 6)
                Text(PhoneFormat.bytes(category.bytes))
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textSecondary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(HubColor.textTertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(category.title), \(PhoneFormat.bytes(category.bytes))\(category.isPartial ? ", partial" : "")"
        )
    }

    private func tint(for role: StorageCategoryRole) -> Color {
        switch role {
        case .apps: return HubColor.accent
        case .userFiles: return HubColor.success
        case .system: return HubColor.textTertiary
        }
    }
}

// MARK: - Donut

struct StorageDonutChart: View {
    let volume: StorageVolume
    var size: CGFloat = 148

    var body: some View {
        let arcs = StorageDonutMath.arcs(
            categories: volume.categories,
            usedBytes: volume.usedBytes,
            totalBytes: volume.totalBytes)
        ZStack {
            Circle()
                .stroke(HubColor.controlTrack, lineWidth: 13)
            ForEach(arcs) { arc in
                Circle()
                    .trim(from: arc.start, to: arc.end)
                    .stroke(
                        color(for: arc.role),
                        style: StrokeStyle(lineWidth: 13, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            Circle()
                .stroke(HubColor.stroke, lineWidth: 1)
                .padding(26)
            VStack(spacing: 1) {
                Text(PhoneFormat.bytes(volume.usedBytes))
                    .font(.system(size: size * 0.125, weight: .bold))
                    .foregroundStyle(HubColor.textPrimary)
                    .monospacedDigit()
                Text("of \(PhoneFormat.bytes(volume.totalBytes))")
                    .font(.system(size: size * 0.072, weight: .medium))
                    .foregroundStyle(HubColor.textSecondary)
                    .monospacedDigit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(volume.title) donut chart: \(volume.usedOfTotalText), \(volume.usedPercentText) used, \(volume.freeText)"
        )
    }

    private func color(for role: StorageCategoryRole) -> Color {
        switch role {
        case .apps: return HubColor.accent
        case .userFiles: return HubColor.success
        case .system: return HubColor.textTertiary
        }
    }
}

// MARK: - Window controller

final class StorageAnalyticsWindowController: NSWindowController {
    static let shared = StorageAnalyticsWindowController()

    private init() {
        let hosting = NSHostingController(rootView: StorageAnalyticsView(deviceID: ""))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 760),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "Storage analytics"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 640)
        window.contentViewController = hosting
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(deviceID: String) {
        window?.contentViewController = NSHostingController(
            rootView: StorageAnalyticsView(deviceID: deviceID))
        window?.title = "Storage analytics"
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func close() {
        window?.orderOut(nil)
    }
}
