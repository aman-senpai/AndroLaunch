//
//  DashboardAppsView.swift
//  AndroLaunch
//
//  Apps tab of the compact dashboard: search across names and packages, a
//  "Copy to Android" result when the query is text rather than an app, the
//  companion install helper when AndroLaunch Comp is missing, and the 4-column
//  app grid that opens Frame Mode windows.
//

import AppKit
import SwiftUI

struct DashboardAppsView: View {
    @ObservedObject var store: HubStore
    let device: AndroidDevice?
    let isPreview: Bool

    @ObservedObject private var companion = CompanionClient.shared
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var windows = AppWindowController.shared

    @State private var searchText = ""
    @State private var feedback: String?
    @State private var feedbackIsError = false
    @State private var isInstalling = false
    /// Brief grace period while the first app scan is still starting. Without
    /// this the grid flashes “No launchable apps” for a second or two when the
    /// menu-bar panel opens before the device feed has delivered the phone.
    @State private var loadingGraceElapsed = false

    @Environment(\.hubSnapshotMode) private var snapshotMode
    @Environment(\.hubPreviewScenario) private var previewScenario
    @Environment(\.hubGlassMode) private var glassMode

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchField
            if let feedback {
                DashboardFeedback(text: feedback, isError: feedbackIsError)
            }
            if showsInstallCard {
                installCard
            }
            appContent
        }
        .onAppear(perform: handleAppear)
        .onChange(of: store.apps) { _, _ in ensureIcons() }
        .onChange(of: device?.id) { _, _ in ensureIcons() }
    }

    private func handleAppear() {
        ensureIcons()
        guard !isPreview, !loadingGraceElapsed else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
            withAnimation(.easeOut(duration: 0.18)) {
                loadingGraceElapsed = true
            }
        }
    }

    /// Real launcher icons load in batches from the companion; snapshots and
    /// previews never touch ADB, so they keep the SF Symbol fallback.
    private func ensureIcons() {
        guard !isPreview, let device else { return }
        AppIconStore.shared.ensureIcons(for: store.apps, deviceID: device.id)
    }

    // MARK: - Search

    private var searchField: some View {
        Group {
            if snapshotMode {
                // ImageRenderer cannot draw the AppKit-backed TextField; the
                // snapshot uses a pixel-identical static field.
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HubColor.textTertiary)
                    Text(
                        trimmedQuery.isEmpty
                            ? "Apps, text, links…" : effectiveQuery
                    )
                    .font(.hubBody)
                    .foregroundStyle(
                        trimmedQuery.isEmpty ? HubColor.textTertiary : HubColor.textPrimary)
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(HubColor.strokeStrong)
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(HubColor.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(HubColor.cardElevated))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(HubColor.stroke, lineWidth: 1))
                .accessibilityHidden(true)
            } else {
                HubSearchField(text: $searchText, placeholder: "Apps, text, links…")
                    .accessibilityLabel("Search apps, or type text to copy to Android")
            }
        }
    }

    // MARK: - Search result

    private var searchItems: [DashboardSearchItem] {
        store.apps.map {
            DashboardSearchItem(id: $0.id, name: $0.name, packageName: $0.packageName)
        }
    }

    /// Design-review scenarios may type a query deterministically; production
    /// always uses what the user typed.
    private var effectiveQuery: String {
        if isPreview, previewScenario == "dashboard-copy" {
            return "https://androlaunch.app/setup"
        }
        return searchText
    }

    private var outcome: DashboardSearchOutcome {
        DeviceDashboardLogic.searchOutcome(query: effectiveQuery, items: searchItems)
    }

    private var displayedApps: [AndroidApp] {
        guard case .matches(let ids) = outcome else { return [] }
        let wanted = Set(ids)
        return store.apps
            .filter { wanted.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var isCopyOffer: Bool {
        if case .copyToAndroid = outcome { return true }
        return false
    }

    private var trimmedQuery: String {
        effectiveQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Content

    @ViewBuilder
    private var appContent: some View {
        if isCopyOffer {
            copyToAndroidCard
        } else {
            appsGridSection
        }
    }

    private var appsGridSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            DashboardSectionHeader("Apps") {
                Text(countText)
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textTertiary)
            }

            if device == nil {
                HubCard {
                    HubEmptyState(
                        icon: "iphone.slash",
                        title: "No phone connected",
                        subtitle:
                            "Connect over USB or Wi-Fi to browse installed apps and open them in Mac windows.")
                }
            } else if let device, !device.isConnected {
                HubCard {
                    HubEmptyState(
                        icon: "wifi.exclamationmark",
                        title: "\(device.name) is offline",
                        subtitle: "Reconnect the phone to load its apps.")
                }
            } else if isLoadingSkeleton {
                loadingCard
            } else if store.apps.isEmpty {
                HubCard {
                    HubEmptyState(
                        icon: "square.grid.2x2",
                        title: "No launchable apps found",
                        subtitle:
                            "The phone didn't report any launchable apps. Refresh, or check that USB debugging is authorised.")
                    HubActionButton(
                        title: "Refresh Apps",
                        icon: "arrow.clockwise",
                        style: .secondary,
                        fullWidth: true
                    ) {
                        refreshApps()
                    }
                    .padding(.top, 2)
                    .disabled(isPreview)
                }
            } else {
                appGrid
            }
        }
    }

    /// True while the first scan is still running (or the deterministic loading
    /// scenario is requested), so the grid can show neutral skeleton tiles
    /// instead of flashing "No launchable apps found".
    private var isLoadingSkeleton: Bool {
        if isPreview, previewScenario == "dashboard-loading" { return true }
        guard device?.isConnected == true else { return false }
        return store.apps.isEmpty && (store.isLoadingApps || !loadingGraceElapsed)
    }

    private var countText: String {
        if isLoadingSkeleton { return "" }
        if trimmedQuery.isEmpty {
            return "\(store.apps.count)"
        }
        return "\(displayedApps.count) of \(store.apps.count)"
    }

    /// Neutral skeleton instead of a premature "No launchable apps" card while
    /// the first ADB scan is still running. The tile geometry matches the real
    /// grid so there is no layout jump when the apps arrive.
    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Text("Loading apps from \(device?.name ?? "the phone")")
                    .font(.hubCaption)
                    .foregroundStyle(
                        glassMode ? HubColor.glassTextSecondary : HubColor.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.leading, 2)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<8, id: \.self) { _ in
                    VStack(spacing: 6) {
                        loadingBlock(width: 46, height: 46, radius: 12)
                        loadingBlock(width: 42, height: 7, radius: 4)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.top, 2)
    }

    /// One neutral skeleton block. Glass mode keeps the panel backdrop visible
    /// through the placeholder so the loading state belongs to the same surface.
    private func loadingBlock(width: CGFloat, height: CGFloat, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(glassMode ? Color.clear : HubColor.controlTrack)
            .frame(width: width, height: height)
            .overlay {
                if glassMode {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
    }

    private var appGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(displayedApps) { app in
                DashboardAppTile(
                    app: app,
                    iconName: AppIconMapper.getIconName(for: app),
                    deviceID: device?.id,
                    hasOpenWindow: hasOpenWindow(app),
                    isOffline: device?.isConnected == false
                ) {
                    launch(app)
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Copy to Android

    private var copyToAndroidCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            DashboardSectionHeader("Text")
            HubCard(padding: 0, tint: HubColor.accent) {
                HubRowButton(action: copyToAndroid) {
                    HStack(spacing: 10) {
                        HubIconTile(
                            systemName: "doc.on.clipboard", tint: HubColor.accent, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Copy to Android")
                                .font(.hubRowTitle)
                                .foregroundStyle(HubColor.textPrimary)
                            Text("Send “\(trimmedQuery)” to the phone clipboard")
                                .font(.hubRowSubtitle)
                                .foregroundStyle(HubColor.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(HubColor.textTertiary)
                    }
                }
            }
            HubNote(
                text:
                    "No app matches “\(trimmedQuery)”. Copying puts the text on the phone so you can paste it there.",
                icon: "info.circle")
        }
    }

    // MARK: - Companion install helper

    private var companionState: CompanionClient.State {
        guard let device else { return .unknown }
        return companion.state(for: device.id)
    }

    private var showsInstallCard: Bool {
        guard let device, device.isConnected else { return false }
        if isPreview { return true }
        if isInstalling { return true }
        return !companion.isReady(device.id)
    }

    private var installCard: some View {
        HubCard(tint: HubColor.accent) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    HubIconTile(
                        systemName: "puzzlepiece.extension", tint: HubColor.accent, size: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Install AndroLaunch Comp")
                            .font(.hubCardTitle)
                            .foregroundStyle(HubColor.textPrimary)
                        Text(installSubtitle)
                            .font(.hubCaption)
                            .foregroundStyle(HubColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                }
                HStack {
                    Spacer(minLength: 0)
                    HubActionButton(
                        title: isInstalling ? "Installing…" : "Install Comp",
                        icon: isInstalling ? nil : "arrow.down.circle"
                    ) {
                        installCompanion()
                    }
                    .disabled(isInstalling || isPreview)
                }
            }
        }
    }

    private var installSubtitle: String {
        if isInstalling { return "Installing over ADB. Accept the prompt on the phone if it appears." }
        if case .failed(let message) = companionState {
            return message
        }
        return "AndroLaunch Comp adds notifications, clipboard and app actions over ADB. It ships with AndroLaunch."
    }

    // MARK: - Actions

    private func launch(_ app: AndroidApp) {
        guard !isPreview, let device else { return }
        let mode: AppLaunchMode =
            preferences.meldModeEnabled ? .meldWindow : .mirror
        let opened = AppWindowController.shared.openApp(
            app, deviceID: device.id, mode: mode)
        if opened {
            feedback = "Opening \(app.name) on \(device.name)."
            feedbackIsError = false
            if let notice = AppWindowController.shared.lastNotice {
                feedback = notice
            }
        } else {
            feedback =
                AppWindowController.shared.lastError
                ?? "The app window couldn't open. Check that scrcpy is installed."
            feedbackIsError = true
            AppWindowController.shared.clearError()
        }
    }

    private func copyToAndroid() {
        guard !isPreview, let device else { return }
        guard DeviceDashboardLogic.isCopyable(trimmedQuery) else {
            feedback = "That text is too long to send to the phone clipboard in one copy."
            feedbackIsError = true
            return
        }
        let copied = CopyToAndroidService.shared.copy(trimmedQuery, deviceID: device.id)
        if copied {
            feedback = "Sent to the phone clipboard. Paste it in any app on \(device.name)."
            feedbackIsError = false
        } else {
            feedback = "Connect a phone before copying text to Android."
            feedbackIsError = true
        }
    }

    private func installCompanion() {
        guard !isPreview, let device else { return }
        isInstalling = true
        feedback = nil
        companion.install(deviceID: device.id) { result in
            DispatchQueue.main.async {
                isInstalling = false
                switch result {
                case .success:
                    feedback = "AndroLaunch Comp is installed and running on \(device.name)."
                    feedbackIsError = false
                case .failure(let error):
                    feedback = error.localizedDescription
                    feedbackIsError = true
                }
            }
        }
    }

    private func refreshApps() {
        guard !isPreview, let device else { return }
        DependencyContainer.shared.deviceRepository.forceRefreshApps(for: device.id)
    }

    private func hasOpenWindow(_ app: AndroidApp) -> Bool {
        guard let device else { return false }
        return windows.isOpen(packageID: app.packageName, deviceID: device.id)
    }
}

// MARK: - Tile

private struct DashboardAppTile: View {
    let app: AndroidApp
    let iconName: String
    let deviceID: String?
    let hasOpenWindow: Bool
    let isOffline: Bool
    let onLaunch: () -> Void

    var body: some View {
        Button(action: onLaunch) {
            VStack(spacing: 5) {
                ZStack(alignment: .bottomTrailing) {
                    AppIconView(
                        packageName: app.packageName,
                        fallbackSymbol: iconName,
                        size: 46,
                        deviceID: deviceID,
                        dimmed: isOffline)

                    if hasOpenWindow {
                        Circle()
                            .fill(HubColor.success)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(HubColor.card, lineWidth: 1.5))
                            .offset(x: 2, y: 2)
                    }
                }
                .frame(width: 46, height: 46)

                Text(app.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(isOffline ? HubColor.textSecondary : HubColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 27, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverGlass(cornerRadius: 12, scale: 1.05, liftShadow: false)
        .help("\(app.name)\n\(app.packageName)")
        .accessibilityLabel(app.name)
        .accessibilityHint("Open this app in a Mac window")
    }
}
