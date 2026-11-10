//
//  DeviceDashboardStorageView.swift
//  AndroLaunch
//
//  Storage tab of the compact dashboard. The rich file-management card is owned
//  by the storage feature (`StorageOverviewCard`); this tab embeds it, wires its
//  Finder-mirror and analytics actions, and keeps a privacy note.
//

import SwiftUI

struct DeviceDashboardStorageView: View {
    let device: AndroidDevice?
    let isPreview: Bool

    @ObservedObject private var access = StorageAccessModel.shared
    @State private var showAnalytics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isPreview, let device, device.isConnected, access.needsGrant {
                storageAccessCard(device)
            }
            if isPreview {
                // Deterministic snapshot data: no ADB, no Finder work.
                StorageOverviewCard(
                    previewSnapshot: .preview,
                    deviceName: device?.name ?? "Android device")
            } else if let device, device.isConnected {
                StorageOverviewCard(
                    deviceID: device.id,
                    deviceName: device.name,
                    onOpen: { scope in
                        FinderMirrorService.shared.open(
                            deviceID: device.id, scope: scope)
                    },
                    onMount: { scope in
                        FinderMirrorService.shared.refresh(
                            deviceID: device.id, scope: scope)
                    },
                    onAnalytics: {
                        withAnimation(.easeOut(duration: 0.18)) {
                            showAnalytics.toggle()
                        }
                    })
                if showAnalytics {
                    VStack(alignment: .leading, spacing: 8) {
                        DashboardSectionHeader("Storage analytics")
                        StorageAnalyticsView(deviceID: device.id, embedded: true)
                    }
                    .padding(.top, 2)
                }
            } else {
                HubCard {
                    HubEmptyState(
                        icon: "internaldrive",
                        title: device == nil
                            ? "No phone connected"
                            : "\(device?.name ?? "The phone") is offline",
                        subtitle: "File management appears once the phone is connected.")
                }
            }

            HubNote(
                text:
                    "Storage is read over ADB. Finder mirrors are written under Application Support on this Mac and are never uploaded.",
                icon: "lock")
        }
        .onAppear {
            guard !isPreview, let device, device.isConnected else { return }
            access.refresh(deviceID: device.id)
        }
        .onChange(of: device?.id) { _, _ in
            guard !isPreview, let device, device.isConnected else { return }
            access.refresh(deviceID: device.id)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .openPanelStorageAnalytics)
        ) { _ in
            withAnimation(.easeOut(duration: 0.18)) { showAnalytics = true }
        }
    }

    /// Android 11+ hides most of the shared folder tree until the companion is
    /// granted All-files (or the legacy read permission on older releases). The
    /// grant is always a user action in Android Settings; this card only opens
    /// that screen and re-reads the result.
    private func storageAccessCard(_ device: AndroidDevice) -> some View {
        HubCard(padding: 0) {
            HStack(alignment: .top, spacing: 10) {
                HubIconTile(
                    systemName: "folder.badge.questionmark",
                    tint: HubColor.textSecondary,
                    size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Allow storage access")
                        .font(.hubRowTitle)
                        .foregroundStyle(HubColor.textPrimary)
                    Text(access.detailText)
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                if access.isRequesting {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Allow") {
                        access.requestAccess(deviceID: device.id)
                    }
                    .buttonStyle(.plain)
                    .font(.hubButton)
                    .foregroundStyle(HubColor.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .hubGlassSurface(cornerRadius: 8)
                }
            }
            .padding(12)
        }
        .onTapGesture {
            // no-op: the explicit Allow button is the only action
        }
    }
}
