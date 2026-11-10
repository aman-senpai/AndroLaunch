//
//  AppsRootView.swift
//  AndroLaunch
//
//  The Apps surface: searchable catalog of the selected phone's apps,
//  per-app Frame Mode windows, the package inspector/installer, pinning,
//  drag-and-drop file transfer and desktop shortcuts.
//

import AppKit
import SwiftUI

// MARK: - Banner

private struct AppsBanner: Identifiable, Equatable {
    enum Kind { case info, success, error }
    let id = UUID()
    let text: String
    let kind: Kind
}

// MARK: - View

struct AppsRootView: View {
    @ObservedObject var store: HubStore

    @ObservedObject private var windows = AppWindowController.shared
    @ObservedObject private var installer = PackageInstaller.shared
    @ObservedObject private var pins = AppPinsStore.shared
    @ObservedObject private var spotlight = SpotlightService.shared
    @ObservedObject private var preferences = AppPreferences.shared

    @AppStorage("apps.launchMode") private var launchModeRaw = AppLaunchMode.meldWindow.rawValue
    @AppStorage("apps.viewMode") private var viewModeRaw = AppsViewMode.grid.rawValue

    @Environment(\.hubSnapshotMode) private var snapshotMode
    @Environment(\.hubPreviewScenario) private var previewScenario

    @State private var searchText = ""
    @State private var showInstaller = false
    @State private var isDropTargeted = false
    @State private var banner: AppsBanner?

    /// Snapshots must not include the AppKit-backed drop target: ImageRenderer
    /// draws it as an unavailable-view placeholder. Dropping is real in the app.
    @ViewBuilder
    private var contentWithOptionalDrop: some View {
        if snapshotMode {
            pageContent
        } else {
            pageContent
                .dropDestination(for: URL.self) { urls, _ in
                    handleDroppedURLs(urls)
                } isTargeted: { targeted in
                    isDropTargeted = targeted
                }
        }
    }

    private var pageContent: some View {
        HubPage(topPadding: 12) {
            toolbar
            if let banner {
                bannerView(banner)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            deviceCard
            if let recent = recentWindow {
                handoffRow(recent)
            }
            appsSection
            dropZone
            HubNote(
                text:
                    "Frame Mode gives each app its own window on Android 14+. On Android 12–13 the app opens on a mirrored main display. ",
                icon: "info.circle")
        }
    }

    var body: some View {
        contentWithOptionalDrop
        .onChange(of: installer.inspection) { _, inspection in
            if inspection != nil { showInstaller = true }
        }
        .onChange(of: installer.isInspecting) { _, inspecting in
            if inspecting { showInstaller = true }
        }
        .onChange(of: windows.lastError) { _, message in
            guard let message else { return }
            showBanner(message, kind: .error)
            windows.clearError()
        }
        .onChange(of: store.apps) { _, apps in
            guard !store.isPreview, let device = store.selectedDevice else { return }
            spotlight.rebuildIndex(apps: apps, deviceID: device.id)
            // Real launcher icons arrive from the companion in batches; the store
            // coalesces this list into a few requests and falls back to symbols.
            AppIconStore.shared.ensureIcons(for: apps, deviceID: device.id)
        }
        .onAppear(perform: loadIfNeeded)
        .sheet(isPresented: $showInstaller) {
            PackageInspectorSheet(installer: installer, device: store.selectedDevice)
        }
    }

    // MARK: - Derived

    private var launchMode: AppLaunchMode {
        AppLaunchMode(rawValue: launchModeRaw) ?? .meldWindow
    }

    /// Settings → Fusion mode → Frame Mode. When off, the whole surface behaves as
    /// Screen Mirroring even if the stored launch-mode preference says Meld.
    private var effectiveLaunchMode: AppLaunchMode {
        preferences.meldModeEnabled ? launchMode : .mirror
    }

    private var viewMode: AppsViewMode {
        // Snapshots always render the grid so design review is deterministic;
        // the renderer can request the list layout with the "apps-list" scenario.
        if previewScenario == "apps-list" { return .list }
        if snapshotMode { return .grid }
        return AppsViewMode(rawValue: viewModeRaw) ?? .grid
    }

    private var launchModeBinding: Binding<AppLaunchMode> {
        Binding(
            get: { effectiveLaunchMode },
            set: { launchModeRaw = $0.rawValue })
    }

    private var displayedPinnedIDs: Set<String> {
        store.isPreview
            ? Set(AppPinsStore.previewPins)
            : Set(pins.pinnedPackageIDs)
    }

    private var filteredApps: [AndroidApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matching = store.apps.filter { app in
            guard !query.isEmpty else { return true }
            return app.name.lowercased().contains(query)
                || app.packageName.lowercased().contains(query)
        }
        let pinned = displayedPinnedIDs
        return matching.sorted { lhs, rhs in
            let leftPinned = pinned.contains(lhs.packageName)
            let rightPinned = pinned.contains(rhs.packageName)
            if leftPinned != rightPinned { return leftPinned }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var recentWindow: OpenAppWindow? {
        guard !store.isPreview, preferences.handoffEnabled else { return nil }
        return windows.mostRecent
    }

    private var dropTargetName: String {
        store.selectedDevice?.name ?? "your phone"
    }

    private var selectedModeBehavior: MeldWindowBehavior? {
        guard let device = store.selectedDevice else { return nil }
        return windows.behavior(for: device)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            if snapshotMode {
                snapshotSearchField
            } else {
                HubSearchField(text: $searchText, placeholder: "Search apps or packages")
            }
            HubActionButton(
                title: "Install APK",
                icon: "square.and.arrow.down",
                style: .quiet
            ) {
                installer.presentOpenPanel()
            }
            .accessibilityHint("Choose an APK, APKS, APKM or XAPK package to inspect and install")
        }
    }

    /// ImageRenderer cannot draw AppKit-backed `TextField`; the snapshot uses a
    /// pixel-identical static field so design review stays faithful.
    private var snapshotSearchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HubColor.textTertiary)
            Text("Search apps or packages")
                .font(.hubBody)
                .foregroundStyle(HubColor.textTertiary)
            Spacer(minLength: 0)
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
    }

    // MARK: - Device card

    @ViewBuilder
    private var deviceCard: some View {
        if let device = store.selectedDevice {
            HubCard(padding: 13, tint: HubColor.accent) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        HubIconTile(
                            systemName: device.isWirelessTransport
                                ? "wifi" : "iphone.gen3",
                            tint: device.isConnected ? HubColor.success : HubColor.warning,
                            size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                deviceNameLabel(device)
                                if device.isConnected {
                                    HubStatusDot()
                                }
                            }
                            Text(deviceSubtitle(device))
                                .font(.hubCaption)
                                .foregroundStyle(HubColor.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        if store.isLoadingApps {
                            ProgressView()
                                .controlSize(.small)
                                .tint(HubColor.accent)
                                .accessibilityLabel("Loading apps")
                        } else {
                            HubPill(
                                text: "\(store.apps.count) apps",
                                tint: HubColor.textSecondary)
                        }
                    }

                    HStack(spacing: 8) {
                        Text("OPEN APPS IN")
                            .font(.hubSectionLabel)
                            .tracking(0.9)
                            .foregroundStyle(HubColor.textTertiary)
                        Spacer(minLength: 6)
                        HubSegmentedTabs(
                            items: AppLaunchMode.allCases.map {
                                HubSegmentedTabs<AppLaunchMode>.Item(
                                    value: $0, title: $0.shortTitle, icon: $0.icon)
                            },
                            selection: launchModeBinding,
                            compact: true
                        )
                        .frame(width: 218)
                    }

                    if effectiveLaunchMode == .meldWindow,
                        case .mainDisplayFallback(let reason) = selectedModeBehavior
                    {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(HubColor.warning)
                                .padding(.top, 1)
                            Text(reason)
                                .font(.hubCaption)
                                .foregroundStyle(HubColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    } else if !preferences.meldModeEnabled {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(HubColor.textTertiary)
                                .padding(.top, 1)
                            Text("Frame Mode is off in Settings. Apps open in Screen Mirroring.")
                                .font(.hubCaption)
                                .foregroundStyle(HubColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        } else {
            HubCard {
                HubEmptyState(
                    icon: "iphone.slash",
                    title: "No phone connected",
                    subtitle:
                        "Connect over USB or Wi-Fi to browse installed apps and open them in Mac windows.")
                HubActionButton(
                    title: "Open Devices",
                    icon: "cable.connector",
                    style: .quiet,
                    fullWidth: true
                ) {
                    store.tab = .devices
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func deviceNameLabel(_ device: AndroidDevice) -> some View {
        if store.devices.count > 1 && !snapshotMode {
            Menu {
                ForEach(store.devices) { candidate in
                    Button {
                        store.select(candidate)
                    } label: {
                        Text(
                            candidate.isConnected
                                ? candidate.name
                                : "\(candidate.name) (offline)")
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(device.name)
                        .font(.hubRowTitle)
                        .foregroundStyle(HubColor.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(HubColor.textTertiary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Selected phone: \(device.name). Change phone")
        } else {
            Text(device.name)
                .font(.hubRowTitle)
                .foregroundStyle(HubColor.textPrimary)
                .lineLimit(1)
        }
    }

    private func deviceSubtitle(_ device: AndroidDevice) -> String {
        var parts: [String] = []
        if let version = device.androidVersion, !version.isEmpty {
            parts.append("Android \(version)")
        }
        parts.append(device.isWirelessTransport ? "Wi-Fi" : "USB")
        parts.append(device.isConnected ? "Connected" : "Offline")
        return parts.joined(separator: " · ")
    }

    // MARK: - Handoff

    private func handoffRow(_ window: OpenAppWindow) -> some View {
        HStack(spacing: 10) {
            HubIconTile(systemName: "macwindow.on.rectangle", tint: HubColor.success, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Continue in \(window.displayName)")
                    .font(.hubRowTitle)
                    .foregroundStyle(HubColor.textPrimary)
                Text(
                    "\(window.mode == .meldWindow ? "Frame Mode window" : "Mirror window")"
                        + " · \(window.isVirtualDisplay ? "virtual display" : "main display")"
                )
                .font(.hubCaption)
                .foregroundStyle(HubColor.textSecondary)
            }
            Spacer(minLength: 6)
            HubActionButton(title: "Show", style: .secondary) {
                windows.activate(window)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: HubMetric.cardRadius, style: .continuous)
                .fill(HubColor.greenWash))
        .overlay(
            RoundedRectangle(cornerRadius: HubMetric.cardRadius, style: .continuous)
                .strokeBorder(HubColor.success.opacity(0.22), lineWidth: 1))
    }

    // MARK: - Apps

    private var appsSection: some View {
        VStack(spacing: 8) {
            HubSectionHeader("All apps") {
                HStack(spacing: 8) {
                    Text(
                        searchText.isEmpty
                            ? "\(store.apps.count)"
                            : "\(filteredApps.count) of \(store.apps.count)"
                    )
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textTertiary)
                    viewModeControl
                }
            }
            appsContent
        }
    }

    @ViewBuilder
    private var appsContent: some View {
        if store.selectedDevice == nil {
            HubCard {
                HubEmptyState(
                    icon: "square.grid.2x2",
                    title: "Apps appear once a phone is connected",
                    subtitle: "AndroLaunch reads the launchable app list over ADB.")
            }
        } else if store.apps.isEmpty {
            if store.isLoadingApps {
                loadingCard
            } else {
                HubCard {
                    HubEmptyState(
                        icon: "square.grid.2x2",
                        title: "No launchable apps found",
                        subtitle:
                            "The phone didn't report any launchable apps. Refresh, or check that USB debugging is authorised.")
                    HubActionButton(
                        title: "Refresh Apps",
                        icon: "arrow.clockwise",
                        style: .quiet,
                        fullWidth: true
                    ) {
                        refreshApps()
                    }
                    .padding(.top, 2)
                }
            }
        } else if filteredApps.isEmpty {
            HubCard {
                HubEmptyState(
                    icon: "magnifyingglass",
                    title: "No apps match “\(searchText)”",
                    subtitle: "Try the app name or part of the package name.")
            }
        } else if viewMode == .list {
            appList
        } else {
            appGrid
        }
    }

    private var loadingCard: some View {
        HubCard {
            HStack(spacing: 11) {
                ProgressView()
                    .controlSize(.small)
                    .tint(HubColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Loading apps from \(store.selectedDevice?.name ?? "the phone")")
                        .font(.hubRowTitle)
                        .foregroundStyle(HubColor.textPrimary)
                    Text("This usually takes a couple of seconds over ADB.")
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var appGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 92, maximum: 150), spacing: 8)],
            spacing: 7
        ) {
            ForEach(filteredApps) { app in
                AppGridTile(
                    app: app,
                    iconName: AppIconMapper.getIconName(for: app),
                    deviceID: store.selectedDevice?.id,
                    isPinned: displayedPinnedIDs.contains(app.packageName),
                    hasOpenWindow: openWindowCount(for: app) > 0,
                    isOffline: store.selectedDevice?.isConnected == false,
                    onLaunch: { launch(app) }
                )
                .contextMenu { appMenu(for: app) }
            }
        }
    }

    private var appList: some View {
        VStack(spacing: 6) {
            ForEach(filteredApps) { app in
                AppListRow(
                    app: app,
                    iconName: AppIconMapper.getIconName(for: app),
                    deviceID: store.selectedDevice?.id,
                    isPinned: displayedPinnedIDs.contains(app.packageName),
                    openCount: openWindowCount(for: app),
                    isOffline: store.selectedDevice?.isConnected == false,
                    onLaunch: { launch(app) },
                    onTogglePin: { togglePin(app) }
                )
                .contextMenu { appMenu(for: app) }
            }
        }
    }

    private var viewModeControl: some View {
        HStack(spacing: 2) {
            viewModeButton(.grid, icon: "square.grid.2x2.fill", label: "Grid view")
            viewModeButton(.list, icon: "list.bullet", label: "List view")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(HubColor.windowTop.opacity(0.7)))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(HubColor.stroke, lineWidth: 1))
    }

    private func viewModeButton(_ mode: AppsViewMode, icon: String, label: String) -> some View {
        let selected = viewMode == mode
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { viewModeRaw = mode.rawValue }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(selected ? HubColor.textPrimary : HubColor.textTertiary)
                .frame(width: 22, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(selected ? HubColor.cardElevated : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        HStack(spacing: 11) {
            HubIconTile(
                systemName: isDropTargeted ? "arrow.down.circle.fill" : "tray.and.arrow.down",
                tint: isDropTargeted ? HubColor.success : HubColor.accent,
                size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    isDropTargeted
                        ? "Release to send to \(dropTargetName)"
                        : "Drop files to send to \(dropTargetName)"
                )
                .font(.hubRowTitle)
                .foregroundStyle(HubColor.textPrimary)
                Text(
                    "APK, APKS, APKM and XAPK open the installer. Other files go to /sdcard/Download."
                )
                .font(.hubCaption)
                .foregroundStyle(HubColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            HubPill(
                text: isDropTargeted ? "Drop now" : "Drag & Drop",
                tint: isDropTargeted ? HubColor.success : HubColor.textSecondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: HubMetric.cardRadius, style: .continuous)
                .fill(isDropTargeted ? HubColor.successSoft : HubColor.card))
        .overlay(
            RoundedRectangle(cornerRadius: HubMetric.cardRadius, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? HubColor.success.opacity(0.6) : HubColor.strokeStrong,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    // MARK: - Banner

    private func bannerView(_ banner: AppsBanner) -> some View {
        let tint: Color
        let icon: String
        switch banner.kind {
        case .info:
            tint = HubColor.accent
            icon = "arrow.up.circle.fill"
        case .success:
            tint = HubColor.success
            icon = "checkmark.circle.fill"
        case .error:
            tint = HubColor.danger
            icon = "exclamationmark.triangle.fill"
        }
        return HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(banner.text)
                .font(.hubCaption)
                .foregroundStyle(HubColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Button {
                self.banner = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(HubColor.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss message")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: HubMetric.rowRadius, style: .continuous)
                .fill(tint.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: HubMetric.rowRadius, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1))
    }

    // MARK: - Menu

    @ViewBuilder
    private func appMenu(for app: AndroidApp) -> some View {
        let isOpen = openWindowCount(for: app) > 0
        Button {
            launch(app, mode: effectiveLaunchMode)
        } label: {
            Label("Open in \(effectiveLaunchMode.title)", systemImage: "play.fill")
        }
        Button {
            launch(app, mode: effectiveLaunchMode == .meldWindow ? .mirror : .meldWindow)
        } label: {
            Label(
                effectiveLaunchMode == .meldWindow
                    ? "Open as Screen Mirroring" : "Open as Frame Mode Window",
                systemImage: effectiveLaunchMode == .meldWindow ? "iphone.gen3" : "macwindow.on.rectangle")
        }
        Divider()
        Button {
            togglePin(app)
        } label: {
            Label(
                displayedPinnedIDs.contains(app.packageName) ? "Unpin" : "Pin to Top",
                systemImage: displayedPinnedIDs.contains(app.packageName) ? "pin.slash" : "pin")
        }
        Button {
            addShortcut(app)
        } label: {
            Label("Add to Desktop", systemImage: "plus.rectangle.on.rectangle")
        }
        Button {
            showAppInfo(app)
        } label: {
            Label("App Info", systemImage: "info.circle")
        }
        if isOpen {
            Divider()
            Button(role: .destructive) {
                guard let device = store.selectedDevice else { return }
                windows.closeApp(packageID: app.packageName, deviceID: device.id)
            } label: {
                Label("Close Window", systemImage: "xmark.circle")
            }
        }
    }

    // MARK: - Actions

    private func launch(_ app: AndroidApp, mode: AppLaunchMode? = nil) {
        guard let device = store.selectedDevice else {
            showBanner("Connect a phone before opening an app.", kind: .error)
            return
        }
        let targetMode = (mode ?? launchMode) == .meldWindow && !preferences.meldModeEnabled
            ? .mirror
            : (mode ?? launchMode)
        let opened = AppWindowController.shared.openApp(
            app, deviceID: device.id, mode: targetMode)
        if !opened, let message = AppWindowController.shared.lastError {
            showBanner(message, kind: .error)
            AppWindowController.shared.clearError()
        } else if opened, targetMode == .meldWindow,
            let notice = AppWindowController.shared.lastNotice
        {
            showBanner(notice, kind: .info)
            AppWindowController.shared.clearNotice()
        }
    }

    private func togglePin(_ app: AndroidApp) {
        guard !store.isPreview else { return }
        AppPinsStore.shared.togglePin(packageID: app.packageName)
    }

    private func addShortcut(_ app: AndroidApp) {
        guard let device = store.selectedDevice else {
            showBanner("Connect a phone before adding a shortcut.", kind: .error)
            return
        }
        spotlight.addDesktopShortcut(app: app, deviceID: device.id)
        if let error = spotlight.lastError {
            showBanner(error, kind: .error)
            spotlight.clearMessages()
        } else if let name = spotlight.lastShortcutName {
            showBanner("Added “\(name)” to the Desktop.", kind: .success)
            spotlight.clearMessages()
        }
    }

    private func showAppInfo(_ app: AndroidApp) {
        guard let device = store.selectedDevice else { return }
        let window = windows.window(packageID: app.packageName, deviceID: device.id)
        let behavior = windows.behavior(for: device)
        var lines: [String] = [
            "Package: \(app.packageName)",
            "Device: \(device.name)"
                + (device.androidVersion.map { " (Android \($0))" } ?? ""),
            "Window: \(window == nil ? "Not open" : "Open")",
            "Frame Mode: \(behavior.isVirtualDisplay ? "Virtual display (Android 14+)" : "Main-display mirror")",
        ]
        if case .mainDisplayFallback(let reason) = behavior {
            lines.append(reason)
        }
        if displayedPinnedIDs.contains(app.packageName) {
            lines.append("Pinned to the top of the Apps list.")
        }

        let alert = NSAlert()
        alert.messageText = app.name
        alert.informativeText = lines.joined(separator: "\n")
        alert.alertStyle = .informational
        alert.addButton(withTitle: window == nil ? "Open Window" : "Close Window")
        alert.addButton(withTitle: "Done")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        if window == nil {
            launch(app)
        } else {
            windows.closeApp(packageID: app.packageName, deviceID: device.id)
        }
    }

    private func refreshApps() {
        guard let device = store.selectedDevice else { return }
        DependencyContainer.shared.deviceRepository.forceRefreshApps(for: device.id)
    }

    private func loadIfNeeded() {
        guard !store.isPreview, let device = store.selectedDevice else { return }
        if store.apps.isEmpty {
            store.loadApps(for: device.id)
        }
        spotlight.rebuildIndex(apps: store.apps, deviceID: device.id)
    }

    private func openWindowCount(for app: AndroidApp) -> Int {
        guard let device = store.selectedDevice else { return 0 }
        return windows.openWindows.filter {
            $0.packageID == app.packageName && $0.deviceID == device.id
        }.count
    }

    // MARK: - Drag & drop

    private func handleDroppedURLs(_ urls: [URL]) -> Bool {
        guard !store.isPreview else { return false }
        guard let device = store.selectedDevice, device.isConnected else {
            showBanner("Connect a phone before dropping files.", kind: .error)
            return false
        }
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else {
            showBanner("Those items aren't files that can be sent.", kind: .error)
            return false
        }

        // Package containers go to the inspector; everything else is pushed to
        // /sdcard/Download. One gate decision covers the whole drop so a batch
        // never stops half way through.
        var pendingPushes: [URL] = []
        for url in files {
            if PackageFormat.detect(fileName: url.lastPathComponent) != .unknown {
                installer.inspect(url: url)
                showInstaller = true
                continue
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                !isDirectory.boolValue
            else {
                showBanner("Folders can't be sent yet — drop individual files.", kind: .error)
                continue
            }
            pendingPushes.append(url)
        }

        guard !pendingPushes.isEmpty else { return true }
        for url in pendingPushes {
            pushFile(url, device: device)
        }
        return true
    }

    /// Pushes one dropped file. A transfer already in flight is never interrupted.
    private func pushFile(_ url: URL, device: AndroidDevice) {
        showBanner("Sending \(url.lastPathComponent) to \(device.name)…", kind: .info)
        let remotePath = "/sdcard/Download/\(url.lastPathComponent)"
        DependencyContainer.shared.deviceRepository.pushFile(
            deviceID: device.id, localPath: url.path, remotePath: remotePath
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    showBanner(
                        "Sent \(url.lastPathComponent) to \(device.name).", kind: .success)
                case .failure(let error):
                    showBanner(
                        "Couldn't send \(url.lastPathComponent): \(error.localizedDescription)",
                        kind: .error)
                }
            }
        }
    }

    private func showBanner(_ text: String, kind: AppsBanner.Kind) {
        let item = AppsBanner(text: text, kind: kind)
        withAnimation(.easeOut(duration: 0.16)) { banner = item }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
            guard banner?.id == item.id else { return }
            withAnimation(.easeOut(duration: 0.2)) { banner = nil }
        }
    }
}

// MARK: - View mode

enum AppsViewMode: String {
    case grid
    case list
}

// MARK: - Grid tile

private struct AppGridTile: View {
    let app: AndroidApp
    let iconName: String
    let deviceID: String?
    let isPinned: Bool
    let hasOpenWindow: Bool
    let isOffline: Bool
    let onLaunch: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onLaunch) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 5) {
                    ZStack(alignment: .bottomTrailing) {
                        // Real launcher icon when the companion can supply it; the
                        // AppIconMapper symbol remains the fallback.
                        AppIconView(
                            packageName: app.packageName,
                            fallbackSymbol: iconName,
                            size: 42,
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
                    .frame(width: 42, height: 42)

                    Text(app.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(isOffline ? HubColor.textSecondary : HubColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(app.packageName)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(HubColor.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 89)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(hovering ? HubColor.cardHover : HubColor.card))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isPinned
                                ? HubColor.accent.opacity(0.32)
                                : (hovering ? HubColor.strokeStrong : HubColor.stroke),
                            lineWidth: 1))

                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(HubColor.accent)
                        .padding(4)
                        .background(Circle().fill(HubColor.accentSoft))
                        .padding(5)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens this app in a Mac window")
        .help("\(app.name)\n\(app.packageName)")
    }

    private var accessibilityLabel: String {
        var label = app.name
        if isPinned { label += ", pinned" }
        if hasOpenWindow { label += ", window open" }
        if isOffline { label += ", phone offline" }
        return label
    }
}

// MARK: - List row

private struct AppListRow: View {
    let app: AndroidApp
    let iconName: String
    let deviceID: String?
    let isPinned: Bool
    let openCount: Int
    let isOffline: Bool
    let onLaunch: () -> Void
    let onTogglePin: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            AppIconView(
                packageName: app.packageName,
                fallbackSymbol: iconName,
                size: 28,
                deviceID: deviceID,
                dimmed: isOffline)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(app.name)
                        .font(.hubRowTitle)
                        .foregroundStyle(isOffline ? HubColor.textSecondary : HubColor.textPrimary)
                        .lineLimit(1)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(HubColor.accent)
                            .accessibilityLabel("Pinned")
                    }
                }
                Text(app.packageName)
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if openCount > 0 {
                HubPill(text: openCount > 1 ? "\(openCount) open" : "Open", tint: HubColor.success)
            }
            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "pin.slash" : "pin")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isPinned ? HubColor.accent : HubColor.textTertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPinned ? "Unpin \(app.name)" : "Pin \(app.name) to top")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: HubMetric.rowRadius, style: .continuous)
                .fill(hovering ? HubColor.cardHover : HubColor.card))
        .overlay(
            RoundedRectangle(cornerRadius: HubMetric.rowRadius, style: .continuous)
                .strokeBorder(HubColor.stroke, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onLaunch)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(app.name)
        .accessibilityHint("Opens this app in a Mac window")
        .help("\(app.name)\n\(app.packageName)")
    }
}
