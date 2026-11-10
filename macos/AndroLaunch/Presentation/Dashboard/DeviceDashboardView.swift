//
//  DeviceDashboardView.swift
//  AndroLaunch
//
//  The compact per-device dashboard: brand + device header with the Frame Mode
//  switch, five tabs (Apps / Notifications / Storage / Device / Settings), one
//  scrolling content surface and a quiet status footer.
//
//  Everything composes from the shared Hub design system (HubTheme /
//  HubComponents). The view also ships a deterministic preview initializer used
//  by the DEBUG snapshot renderer — it never touches ADB, the companion or the
//  notification mirror, so design review is reproducible.
//

import AppKit
import SwiftUI

struct DeviceDashboardView: View {
    @ObservedObject private var store: HubStore
    @ObservedObject private var mirror = NotificationMirror.shared
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var companion = CompanionClient.shared
    @ObservedObject private var windows = AppWindowController.shared

    let deviceID: String?
    let initialTab: DeviceDashboardTab
    /// Non-nil when hosted inside the menu-bar glass panel. The dashboard keeps
    /// one view tree for the window and the panel; this switches the compact
    /// chrome (tools affordance, tighter header, glass surfaces).
    private let panelActions: MenuBarPanelActions?

    /// Non-nil only for the deterministic preview/snapshot path.
    private let previewRecords: [AndroidNotificationRecord]?

    @State private var tab: DeviceDashboardTab
    @State private var meldHelpShown = false
    @State private var featurePage: PanelFeaturePage?
    @State private var showTools = false
    @State private var hoveredTab: DeviceDashboardTab?

    @Environment(\.hubSnapshotMode) private var snapshotMode
    @Environment(\.hubGlassMode) private var glassMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Init

    /// Production initializer. Keeps the original public signature.
    init(deviceID: String?, initialTab: DeviceDashboardTab) {
        self.init(deviceID: deviceID, initialTab: initialTab, panelActions: nil)
    }

    /// Production initializer with the menu-bar panel's action surface.
    init(
        deviceID: String?,
        initialTab: DeviceDashboardTab,
        panelActions: MenuBarPanelActions?
    ) {
        _store = ObservedObject(wrappedValue: HubStore.shared)
        self.deviceID = deviceID
        self.initialTab = initialTab
        self.panelActions = panelActions
        self.previewRecords = nil
        _tab = State(initialValue: initialTab)
        _showTools = State(initialValue: false)
        _hoveredTab = State(initialValue: nil)
    }

    /// Deterministic snapshot/preview initializer: a preview store with fixture
    /// devices and apps, fixture notifications and no live service calls.
    /// Usage: `DeviceDashboardView(previewTab: .apps)`.
    init(previewTab: DeviceDashboardTab) {
        self.init(previewTab: previewTab, panelActions: nil)
    }

    /// Deterministic snapshot initializer for the glass panel. `showsTools`
    /// renders the Tools overlay so its layout can be reviewed.
    init(
        previewTab: DeviceDashboardTab,
        panelActions: MenuBarPanelActions?,
        showsTools: Bool = false,
        hoveredTab: DeviceDashboardTab? = nil
    ) {
        _store = ObservedObject(
            wrappedValue: HubStore(
                previewDevices: HubPreviewData.devices, apps: HubPreviewData.apps))
        self.deviceID = HubPreviewData.pixel.id
        self.initialTab = previewTab
        self.panelActions = panelActions
        self.previewRecords = DashboardPreviewNotifications.records
        _tab = State(initialValue: previewTab)
        _showTools = State(initialValue: showsTools && panelActions != nil)
        _hoveredTab = State(initialValue: hoveredTab)
    }

    private var isPanelMode: Bool { panelActions != nil }

    private var isPreview: Bool { previewRecords != nil }

    // MARK: - Body

    var body: some View {
        surface
            .frame(width: snapshotMode ? 380 : nil)
            .frame(
                minWidth: snapshotMode ? nil : 380,
                maxWidth: snapshotMode ? nil : .infinity,
                maxHeight: (snapshotMode && !isPanelMode) ? nil : .infinity)
            .onAppear(perform: startLiveServices)
            .onChange(of: store.devices) { _, _ in startLiveServices() }
            .onChange(of: store.selectedDeviceID) { _, _ in startLiveServices() }
            .onReceive(
                NotificationCenter.default.publisher(for: .openPanelStorageAnalytics)
            ) { _ in
                withAnimation(.easeOut(duration: 0.18)) { tab = .storage }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .openPanelFeaturePage)
            ) { notification in
                guard let raw = notification.userInfo?["page"] as? String,
                    let page = PanelFeaturePage(rawValue: raw)
                else { return }
                withAnimation(.easeOut(duration: 0.18)) { featurePage = page }
            }
    }

    private var surface: some View {
        ZStack(alignment: .top) {
            if glassMode {
                Color.clear
            } else {
                HubColor.background
            }

            if let featurePage {
                PanelFeaturePageView(page: featurePage) {
                    withAnimation(.easeOut(duration: 0.18)) { self.featurePage = nil }
                }
            } else {
            VStack(spacing: 0) {
                brandHeader
                tabBar
                    .padding(.top, isPanelMode ? 4 : 2)
                    .padding(.bottom, 10)
                deviceHeader
                Rectangle()
                    .fill(HubColor.stroke)
                    .frame(height: 1)
                content
                if snapshotMode && isPanelMode {
                    Spacer(minLength: 0)
                }
                // The menu-bar panel has no bottom status bar; the context is in
                // the header and the refresh action lives in Tools.
                if !isPanelMode {
                    footer
                }
            }
            }

            if isPanelMode, showTools, let panelActions {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { showTools = false }
                    .accessibilityHidden(true)
                MenuBarPanelToolsView(
                    actions: panelActions,
                    deviceName: device?.name,
                    hasDevice: isConnected,
                    dismiss: { showTools = false })
                    .padding(.trailing, 12)
                    .padding(.top, 54)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
            }

            if isPanelMode, meldHelpShown {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { meldHelpShown = false }
                    .accessibilityHidden(true)
                meldModeHelp
                    .padding(14)
                    .hubGlassSurface(cornerRadius: 16)
                    .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
                    .padding(.trailing, 12)
                    .padding(.top, 54)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Device

    private var device: AndroidDevice? {
        if let deviceID,
            let match = store.devices.first(where: {
                $0.id == deviceID || $0.stableID == deviceID
            })
        {
            return match
        }
        return store.selectedDevice
    }

    private var isConnected: Bool { device?.isConnected ?? false }

    private var meldModeAvailable: Bool {
        guard let device else { return false }
        return MeldModeSupport.supportsVirtualDisplay(apiLevel: device.apiLevel)
    }

    private var meldModeBinding: Binding<Bool> {
        Binding(
            get: { isPreview ? true : preferences.meldModeEnabled },
            set: { newValue in
                guard !isPreview else { return }
                preferences.meldModeEnabled = newValue
            })
    }

    private var deviceSubtitle: String {
        guard let device else { return "Connect a phone to get started" }
        var parts: [String] = []
        if let version = device.androidVersion, !version.isEmpty {
            parts.append("Android \(version)")
        }
        parts.append(device.isWirelessTransport ? "Wi-Fi" : "USB")
        if let battery = device.batteryLevel {
            parts.append("\(battery)%")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Header

    /// Brand row (logo/title/transport/ellipsis). Sits above the tab bar so the
    /// panel follows the reference hierarchy: brand → tabs → device.
    private var brandHeader: some View {
        HStack(spacing: 9) {
            brandMark
            Text("AndroLaunch")
                .font(.system(size: isPanelMode ? 20 : 17, weight: .bold))
                .foregroundStyle(glassMode ? HubColor.glassTextPrimary : HubColor.textPrimary)
            Spacer(minLength: 6)
            transportPill
            if isPanelMode {
                toolsButton
            }
        }
        .padding(.horizontal, isPanelMode ? 14 : 16)
        .padding(.top, isPanelMode ? 16 : 30)
        .padding(.bottom, isPanelMode ? 8 : 10)
    }

    /// Use the exact menu-bar icon inside the expanded panel.
    private var brandMark: some View {
        MenuBarGlyph(size: isPanelMode ? 30 : 28)
    }

    /// Device row + Frame Mode control, below the tabs.
    private var deviceHeader: some View {
        HStack(spacing: 9) {
            HubIconTile(
                systemName: device?.isWirelessTransport == true ? "wifi" : "iphone.gen3",
                tint: isConnected ? HubColor.success : HubColor.warning,
                size: 28)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(device?.name ?? "No phone connected")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(
                            glassMode ? HubColor.glassTextPrimary : HubColor.textPrimary)
                        .lineLimit(1)
                    if isConnected { HubStatusDot(size: 6) }
                }
                Text(deviceSubtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(
                        glassMode ? HubColor.glassTextSecondary : HubColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            meldModeControl
        }
        .padding(.horizontal, isPanelMode ? 14 : 16)
        .padding(.bottom, 12)
    }

    private var toolsButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                showTools.toggle()
                meldHelpShown = false
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(HubColor.textSecondary)
                .frame(width: 28, height: 28)
                .background {
                    if glassMode {
                        Circle().fill(.clear).hubGlassSurface(cornerRadius: 14)
                    } else {
                        Circle().fill(HubColor.cardElevated)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Tools: mirror controls, storage, Finder, clipboard")
        .accessibilityLabel("Toggle tools")
        .accessibilityValue(showTools ? "Expanded" : "Collapsed")
    }

    private var transportPill: some View {
        HubPill(
            text: isConnected ? (device?.isWirelessTransport == true ? "Wi-Fi" : "USB") : "Offline",
            tint: HubColor.textSecondary,
            icon: device?.isWirelessTransport == true ? "wifi" : "cable.connector")
    }

    private var meldModeControl: some View {
        HStack(spacing: 5) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(
                    meldModeAvailable
                        ? (glassMode ? HubColor.glassTextSecondary : HubColor.textSecondary)
                        : (glassMode ? HubColor.glassTextTertiary : HubColor.textTertiary))
            Text("Frame Mode")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(
                    meldModeAvailable
                        ? (glassMode ? HubColor.glassTextSecondary : HubColor.textSecondary)
                        : (glassMode ? HubColor.glassTextTertiary : HubColor.textTertiary))
            HubSwitch(isOn: meldModeBinding, disabled: !meldModeAvailable)
            meldHelpButton
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Frame Mode")
    }

    private var meldHelpButton: some View {
        let button = Button {
            meldHelpShown.toggle()
        } label: {
            Image(
                systemName: meldModeAvailable
                    ? "info.circle" : "exclamationmark.circle.fill"
            )
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(
                meldModeAvailable ? HubColor.textTertiary : HubColor.warning)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("What Frame Mode needs")
        .accessibilityLabel("Frame Mode requirements")

        return Group {
            if isPanelMode {
                button
            } else {
                button.popover(
                    isPresented: $meldHelpShown, arrowEdge: .bottom
                ) {
                    meldModeHelp
                }
            }
        }
    }

    private var meldModeHelp: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Frame Mode")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HubColor.textPrimary)
            Text("Open your Android apps in their own windows on the Mac instead of mirroring the whole phone.")
                .font(.system(size: 11.5))
                .foregroundStyle(HubColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if meldModeAvailable {
                Text("Ready on this phone: it runs Android 14 or later, so each app gets a dedicated virtual display.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        glassMode ? HubColor.glassTextSecondary : HubColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("This feature requires an Android 14 device. Older phones mirror the main display instead.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        glassMode ? HubColor.glassTextTertiary : HubColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .frame(width: 232)
        .background {
            if glassMode {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(HubColor.stroke, lineWidth: 1))
            } else {
                HubColor.card
            }
        }
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                ForEach(DeviceDashboardTab.allCases) { item in
                    tabButton(item)
                }
            }
            .padding(3)
            .background {
                if glassMode {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.clear)
                        .hubGlassSurface(cornerRadius: 10)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(HubColor.windowTop.opacity(0.65))
                }
            }
            .overlay {
                if !glassMode {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(HubColor.stroke, lineWidth: 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, isPanelMode ? 12 : 14)
    }

    /// A compact, centred tab cell. The selected tab and the hovered tab show
    /// their label; hover adds a Liquid Glass highlight and a small spring
    /// expansion. Widths animate instead of snapping, so neighbours never jump.
    private func tabButton(_ item: DeviceDashboardTab) -> some View {
        let selected = item == tab
        let hovered = hoveredTab == item
        let expanded = selected || hovered
        return Button {
            withAnimation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86)
            ) {
                tab = item
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: item.icon)
                    .font(.system(size: 10.5, weight: .semibold))
                if expanded {
                    Text(item.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(
                            .opacity.combined(
                                with: .scale(scale: 0.86, anchor: .leading)))
                }
            }
            .foregroundStyle(
                selected || hovered
                    ? HubColor.textPrimary : HubColor.textSecondary)
            .padding(.horizontal, expanded ? 8 : 7)
            .frame(height: 26)
            .frame(minWidth: expanded ? 64 : 40)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(HubColor.cardElevated.opacity(glassMode ? 0.6 : 1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(HubColor.strokeStrong, lineWidth: 1))
                }
            }
            .hoverGlass(
                cornerRadius: 7,
                enabled: !reduceMotion,
                scale: 1.02,
                liftShadow: false)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                if isHovering {
                    hoveredTab = item
                } else if hoveredTab == item {
                    hoveredTab = nil
                }
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86),
            value: expanded)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if snapshotMode {
            if isPanelMode {
                // The panel is a fixed 380x760 surface with a scrolling content
                // area. ImageRenderer cannot lay out a ScrollView, so clip the
                // full-height content at the real viewport instead of letting it
                // overflow the panel frame.
                contentBody
                    .frame(
                        width: MenuBarPanelGeometry.panelWidth,
                        height: MenuBarPanelGeometry.panelContentHeight,
                        alignment: .top)
                    .clipped()
            } else {
                contentBody
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                contentBody
            }
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch tab {
            case .apps:
                DashboardAppsView(
                    store: store,
                    device: device,
                    isPreview: isPreview)
            case .notifications:
                DashboardNotificationsView(
                    store: store,
                    device: device,
                    isPreview: isPreview,
                    previewRecords: previewRecords,
                    mirror: mirror)
            case .storage:
                DeviceDashboardStorageView(device: device, isPreview: isPreview)
            case .device:
                DashboardDeviceView(device: device)
            case .settings:
                DashboardSettingsView(store: store, device: device, isPreview: isPreview)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 7) {
            HubStatusDot(color: isConnected ? HubColor.success : HubColor.warning, size: 6)
            Text(footerText)
                .font(.system(size: 10.5))
                .foregroundStyle(
                    glassMode ? HubColor.glassTextSecondary : HubColor.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Button {
                refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(HubColor.textSecondary)
                    .padding(5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(HubColor.cardElevated.opacity(glassMode ? 0.55 : 1)))
            }
            .buttonStyle(.plain)
            .help("Refresh devices and apps")
            .accessibilityLabel("Refresh")
            .disabled(isPreview)
            .hoverGlass(
                cornerRadius: 6,
                enabled: !isPreview,
                scale: 1.04,
                liftShadow: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(HubColor.stroke)
                .frame(height: 1)
        }
    }

    private var footerText: String {
        guard let device else { return "No device connected" }
        if !device.isConnected { return "\(device.name) is offline" }
        let apps = store.apps.count
        let windows = windows.openWindowCount(forDeviceID: device.id)
        if windows > 0 {
            return "\(apps) apps · \(windows) window\(windows == 1 ? "" : "s") open"
        }
        return "\(apps) apps · Frame Mode \(meldModeAvailable ? "ready" : "unavailable")"
    }

    // MARK: - Actions

    private func startLiveServices() {
        guard !isPreview else { return }
        mirror.syncDevices(store.devices)
        if let device {
            if (store.apps.isEmpty || store.selectedDeviceID != device.id),
                !store.isLoadingApps
            {
                store.loadApps(for: device.id)
            }
            CompanionClient.shared.prepare(deviceID: device.id)
        }
    }

    private func refresh() {
        guard !isPreview else { return }
        store.refresh()
        if let device {
            store.loadApps(for: device.id)
            CompanionClient.shared.prepare(deviceID: device.id)
        }
    }
}

// MARK: - Shared dashboard chrome

/// Small section label used by every dashboard tab. Kept here so the tabs share
/// one rhythm without each importing a component file of its own.
/// The menu-bar status icon reused inside the expanded panel (template image so
/// it matches the monochrome header). Falls back to the same grid symbol the
/// status item uses when the asset is unavailable.
struct MenuBarGlyph: View {
    var size: CGFloat = 30

    var body: some View {
        Group {
            if let icon = NSImage(named: "MenuIcons") {
                Image(nsImage: icon)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
            } else {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: size * 0.46, weight: .semibold))
            }
        }
        .foregroundStyle(HubColor.textPrimary)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .strokeBorder(HubColor.strokeStrong, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

struct DashboardSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.hubGlassMode) private var glassMode

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .font(.hubSectionLabel)
                .tracking(0.9)
                .foregroundStyle(
                    glassMode ? HubColor.glassTextSecondary : HubColor.textTertiary)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.leading, 2)
    }
}

/// Quiet inline feedback line used for the result of an action ("Sent to the
/// phone clipboard", "Couldn't launch the app"). Never a modal alert: the
/// dashboard stays a glanceable surface.
struct DashboardFeedback: View {
    let text: String
    var isError: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: isError ? "exclamationmark.circle" : "checkmark.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isError ? HubColor.danger : HubColor.success)
                .padding(.top, 1)
            Text(text)
                .font(.hubCaption)
                .foregroundStyle(isError ? HubColor.danger : HubColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }
}
