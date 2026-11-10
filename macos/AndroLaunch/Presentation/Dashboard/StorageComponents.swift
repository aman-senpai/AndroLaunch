//
//  StorageComponents.swift
//  AndroLaunch
//
//  File-management card shared by the device dashboard and the storage window.
//  Shows the used/total bar with the category split, then Camera / SD Card / Root
//  rows whose "Open" and "Mount" actions materialize a local Finder mirror.
//
//  Owned by the storage feature. The dashboard embeds this card and optionally
//  supplies its own callbacks; with no callbacks the card drives the storage and
//  Finder services directly.
//

import SwiftUI

// MARK: - Card

struct StorageOverviewCard: View {
    let deviceID: String
    let deviceName: String?
    private let onAnalytics: (() -> Void)?
    private let onOpen: ((FinderMirrorScope) -> Void)?
    private let onMount: ((FinderMirrorScope) -> Void)?
    private let previewSnapshot: StorageSnapshot?

    @ObservedObject private var service = StorageService.shared
    @ObservedObject private var finder = FinderMirrorService.shared

    /// Dashboard usage: live storage for a device.
    /// `onAnalytics` is last so existing trailing-closure call sites keep working.
    init(
        deviceID: String,
        deviceName: String? = nil,
        onOpen: ((FinderMirrorScope) -> Void)? = nil,
        onMount: ((FinderMirrorScope) -> Void)? = nil,
        onAnalytics: (() -> Void)? = nil
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.onAnalytics = onAnalytics
        self.onOpen = onOpen
        self.onMount = onMount
        self.previewSnapshot = nil
    }

    /// DEBUG snapshot renderer / SwiftUI preview: deterministic data, no ADB.
    init(
        previewSnapshot: StorageSnapshot,
        deviceName: String? = nil,
        onAnalytics: (() -> Void)? = nil
    ) {
        self.deviceID = previewSnapshot.deviceID
        self.deviceName = deviceName
        self.onAnalytics = onAnalytics
        self.onOpen = nil
        self.onMount = nil
        self.previewSnapshot = previewSnapshot
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HubCard {
                VStack(alignment: .leading, spacing: 13) {
                    titleRow
                    categoryStrip
                    finderNote
                    scopeRow
                    footer
                }
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    private var snapshot: StorageSnapshot? {
        if let previewSnapshot { return previewSnapshot }
        guard let snapshot = service.snapshot, snapshot.deviceID == deviceID else {
            return nil
        }
        return snapshot
    }

    private var volume: StorageVolume? {
        snapshot?.internalVolume
    }

    private var resolvedDeviceName: String {
        deviceName
            ?? HubStore.shared.devices.first(where: { $0.id == deviceID })?.name
            ?? "Android device"
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HubColor.textSecondary)
            Text(resolvedDeviceName)
                .font(.hubCaption)
                .foregroundStyle(HubColor.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if snapshot?.isPartial == true {
                HubPill(text: "Partial", tint: HubColor.warning, icon: "exclamationmark.circle.fill")
            }
        }
    }

    // MARK: Title + capacity

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 11) {
            HubIconTile(systemName: "internaldrive.fill", size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("File management")
                    .font(.hubCardTitle)
                    .foregroundStyle(HubColor.textPrimary)
                Text(capacityText)
                    .font(.hubCardSubtitle)
                    .foregroundStyle(HubColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if let volume, volume.hasOwnCapacity {
                Text(volume.usedPercentText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HubColor.textPrimary)
                    .monospacedDigit()
            } else if let snapshot, snapshot.totalBytes == 0 {
                Text("Reading…")
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textTertiary)
            }
        }
    }

    private var capacityText: String {
        if let snapshot {
            return "Used \(PhoneFormat.bytes(snapshot.usedBytes)), total \(PhoneFormat.bytes(snapshot.totalBytes))"
        }
        if let error = service.lastError, !error.isEmpty {
            return error
        }
        return service.isLoading ? "Reading storage…" : "Storage is not available."
    }

    // MARK: Category strip

    private var categoryStrip: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                if let volume, volume.hasOwnCapacity {
                    ForEach(stripSegments(volume: volume)) { segment in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(color(for: segment.role))
                            .frame(width: max(2, geometry.size.width * segment.fraction))
                    }
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(HubColor.controlTrack)
                        .frame(
                            width: max(
                                2, geometry.size.width * max(0, 1 - volume.usedFraction)))
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(HubColor.controlTrack)
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(categoryAccessibilityLabel)
    }

    private struct StripSegment: Identifiable {
        let role: StorageCategoryRole
        let fraction: Double
        var id: String { role.rawValue }
    }

    private func stripSegments(volume: StorageVolume) -> [StripSegment] {
        let categories = volume.categories.filter { $0.bytes > 0 }
        let total = categories.reduce(Int64(0)) { $0 + $1.bytes }
        guard total > 0 else { return [] }
        let used = volume.usedFraction
        return categories.map {
            StripSegment(
                role: $0.role,
                // Fractions of the whole bar; the track fills the free part.
                fraction: used * Double($0.bytes) / Double(total))
        }
    }

    private var categoryAccessibilityLabel: String {
        guard let volume else { return "Storage categories are loading" }
        let parts = volume.categories.map {
            "\($0.title) \(PhoneFormat.bytes($0.bytes))"
        }
        return (["Storage split:"] + parts + ["\(volume.freeText)"])
            .joined(separator: ", ")
    }

    // MARK: Finder note

    private var finderNote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(HubColor.textTertiary)
                .padding(.top, 1)
            Text(
                "Finder mirror: folders are copied locally to ~/AndroLaunch. A system File Provider mount is a signed extension and ships separately."
            )
            .font(.hubCaption)
            .foregroundStyle(HubColor.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 1)
    }

    // MARK: Scopes

    private var scopeRow: some View {
        HStack(alignment: .top, spacing: 8) {
            scopeColumn(
                scope: .camera,
                enabled: snapshot != nil,
                mountOnly: false)
            scopeColumn(
                scope: .sdCard,
                enabled: snapshot.map { !$0.removableVolumes.isEmpty } ?? false,
                mountOnly: false)
            scopeColumn(
                scope: .root,
                enabled: snapshot != nil,
                mountOnly: true)
        }
    }

    private func scopeColumn(
        scope: FinderMirrorScope, enabled: Bool, mountOnly: Bool
    ) -> some View {
        VStack(spacing: 6) {
            HubIconTile(
                systemName: scope.icon,
                tint: enabled ? HubColor.accent : HubColor.textTertiary,
                size: 28)
            Text(scope.title)
                .font(.hubRowTitle)
                .foregroundStyle(enabled ? HubColor.textPrimary : HubColor.textTertiary)
                .lineLimit(1)
            if scope == .sdCard, !enabled {
                Text("No SD card")
                    .font(.system(size: 9.5))
                    .foregroundStyle(HubColor.textTertiary)
            } else if mountOnly {
                ScopeActionButton(
                    title: "Mount",
                    icon: "arrow.up.to.line",
                    enabled: enabled,
                    accessibilityLabel: "Mount \(scope.title) in Finder"
                ) {
                    mount(scope)
                }
            } else {
                HStack(spacing: 5) {
                    ScopeActionButton(
                        title: "Open",
                        icon: nil,
                        enabled: enabled,
                        accessibilityLabel: "Open \(scope.title) in Finder"
                    ) {
                        open(scope)
                    }
                    ScopeActionButton(
                        title: nil,
                        icon: "arrow.up.to.line",
                        enabled: enabled,
                        accessibilityLabel: "Mount \(scope.title) in Finder"
                    ) {
                        mount(scope)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let progress = finder.progressText, finder.isRefreshing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progress)
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }

            if let error = finder.lastError ?? service.lastError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(HubColor.warning)
                        .padding(.top, 1)
                    Text(error)
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(HubColor.warningSoft))
            }

            HStack(spacing: 8) {
                HubActionButton(
                    title: service.isLoading ? "Reading…" : "Refresh",
                    icon: "arrow.clockwise",
                    style: .secondary,
                    enabled: !service.isLoading && previewSnapshot == nil
                ) {
                    guard previewSnapshot == nil else { return }
                    service.load(deviceID: deviceID)
                }
                HubActionButton(
                    title: "Analytics",
                    icon: "chart.pie",
                    style: .quiet
                ) {
                    if let onAnalytics {
                        onAnalytics()
                    } else {
                        StorageAnalyticsWindowController.shared.show(deviceID: deviceID)
                    }
                }
                Spacer(minLength: 0)
            }

            if let snapshot {
                Text("Updated \(snapshot.scannedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9.5))
                    .foregroundStyle(HubColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: Actions

    private func loadIfNeeded() {
        guard previewSnapshot == nil else { return }
        if service.snapshot?.deviceID != deviceID, !service.isLoading {
            service.load(deviceID: deviceID)
        }
    }

    private func open(_ scope: FinderMirrorScope) {
        if let onOpen {
            onOpen(scope)
        } else if previewSnapshot == nil {
            FinderMirrorService.shared.open(deviceID: deviceID, scope: scope)
        }
    }

    private func mount(_ scope: FinderMirrorScope) {
        if let onMount {
            onMount(scope)
        } else if previewSnapshot == nil {
            FinderMirrorService.shared.mount(deviceID: deviceID, scope: scope)
        }
    }

    // MARK: Palette

    private func color(for role: StorageCategoryRole) -> Color {
        switch role {
        case .apps: return HubColor.accent
        case .userFiles: return HubColor.success
        case .system: return HubColor.textTertiary
        }
    }
}

// MARK: - Scope button

/// Compact pill used by the three scope columns; the dashboard card is narrow.
private struct ScopeActionButton: View {
    let title: String?
    let icon: String?
    let enabled: Bool
    let accessibilityLabel: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                }
                if let title {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .foregroundStyle(enabled ? HubColor.textPrimary : HubColor.textTertiary)
            .padding(.horizontal, title == nil ? 7 : 9)
            .padding(.vertical, 5)
            .frame(minHeight: 22)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering && enabled ? HubColor.cardHover : HubColor.cardElevated))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(HubColor.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.7)
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}
