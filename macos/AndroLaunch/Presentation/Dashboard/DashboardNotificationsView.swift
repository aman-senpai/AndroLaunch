//
//  DashboardNotificationsView.swift
//  AndroLaunch
//
//  Premium Notifications tab of the compact dashboard.
//
//  Layout follows the current reference: a "Showing N" disclosure with a
//  clear-view affordance, one glass card per app with the real launcher icon,
//  app name, sender (for mail), time-ago, headline, preview line and the
//  "N notifications mirrored" count, then compact glass actions (Open, Delete,
//  Mark as read, Reply) and a focused reply composer. A separate Hidden section
//  keeps content the phone or the privacy policy will not expose.
//
//  Everything here is monochrome by design: text stays on the semantic
//  primary/secondary/tertiary colours, surfaces use the shared glass helper and
//  no action uses the accent tint. Grouping/decision logic lives in
//  `NotificationGroupingLogic` (Foundation-only, covered by tests).
//

import AppKit
import SwiftUI

struct DashboardNotificationsView: View {
    @ObservedObject var store: HubStore
    let device: AndroidDevice?
    let isPreview: Bool
    let previewRecords: [AndroidNotificationRecord]?
    @ObservedObject var mirror: NotificationMirror

    @State private var showingExpanded = true
    @State private var hiddenExpanded = false
    @State private var canceledExpanded = true
    @State private var recentlyCanceled: [NotificationDisplayItem] = []
    @State private var cleared = false
    @State private var expandedGroups: Set<String> = []
    @State private var feedback: String?
    @State private var feedbackIsError = false
    @State private var liveRecords: [AndroidNotificationRecord] = []
    @State private var removedKeys: Set<String> = []
    @State private var replyingKey: String?
    @State private var replyText = ""
    @State private var isSendingReply = false
    @FocusState private var replyFieldFocused: Bool

    init(
        store: HubStore,
        device: AndroidDevice?,
        isPreview: Bool,
        previewRecords: [AndroidNotificationRecord]?,
        mirror: NotificationMirror
    ) {
        self.store = store
        self.device = device
        self.isPreview = isPreview
        self.previewRecords = previewRecords
        self.mirror = mirror
        _recentlyCanceled = State(
            initialValue: previewRecords != nil
                ? DashboardPreviewNotifications.canceledItems : [])
        // Snapshots show the compact hierarchy from the reference: Showing and
        // Hidden collapsed, Recently Canceled expanded. Live starts expanded.
        _showingExpanded = State(initialValue: previewRecords == nil)
    }

    @Environment(\.hubGlassMode) private var glassMode
    @Environment(\.hubSnapshotMode) private var snapshotMode

    private let refreshTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            syncRow
            if let feedback {
                DashboardFeedback(text: feedback, isError: feedbackIsError)
            }
            if showsSections {
                if cleared {
                    clearedState
                } else {
                    if !sections.visible.isEmpty {
                        visibleSection
                    }
                    if !sections.hidden.isEmpty {
                        hiddenSection
                    }
                    if !recentlyCanceled.isEmpty {
                        recentlyCanceledSection
                    }
                    if sections.isEmpty && recentlyCanceled.isEmpty {
                        emptyOnState
                    }
                }
            } else {
                syncOffState
            }
            HubNote(
                text:
                    "Sensitive apps, locked-phone content and ongoing notifications never leave the phone.",
                icon: "lock")
        }
        .onAppear(perform: handleAppear)
        .onChange(of: mirror.deviceStates) { _, _ in refreshRecords() }
        .onChange(of: sections.visibleCount) { _, _ in
            // A newly arrived notification brings the list back.
            if cleared { withAnimation(.easeOut(duration: 0.16)) { cleared = false } }
        }
        .onReceive(refreshTimer) { _ in
            guard !isPreview else { return }
            refreshRecords()
        }
    }

    // MARK: - Records

    private var records: [AndroidNotificationRecord] {
        if let previewRecords { return previewRecords }
        guard !removedKeys.isEmpty else { return liveRecords }
        return liveRecords.filter { !removedKeys.contains($0.key) }
    }

    private func handleAppear() {
        if isPreview {
            if recentlyCanceled.isEmpty {
                recentlyCanceled = DashboardPreviewNotifications.canceledItems
            }
        } else {
            refreshRecords()
        }
    }

    /// `NotificationMirror` only republishes when its device state changes, so the
    /// dashboard snapshots the latest record list on a light timer while it is
    /// open. The read itself is free: the mirror keeps the poll result.
    private func refreshRecords() {
        guard !isPreview, let device else {
            liveRecords = []
            return
        }
        let next = mirror.latestRecords(for: device)
        // A notification that disappears between polls was canceled on the phone
        // (or by another app). Keep a short local "Recently Canceled" trail so the
        // panel can show it like the reference product.
        let nextKeys = Set(next.map(\.key))
        for old in liveRecords where !nextKeys.contains(old.key) {
            rememberCanceled(NotificationGroupingLogic.displayItem(from: old))
        }
        liveRecords = next
    }

    private func rememberCanceled(_ item: NotificationDisplayItem) {
        guard !recentlyCanceled.contains(where: { $0.key == item.key }) else { return }
        recentlyCanceled.insert(item, at: 0)
        if recentlyCanceled.count > 20 {
            recentlyCanceled = Array(recentlyCanceled.prefix(20))
        }
    }

    private var recentlyCanceledSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: "Recently Canceled \(recentlyCanceled.count)",
                expanded: $canceledExpanded,
                close: nil)
            if canceledExpanded {
                ForEach(recentlyCanceled) { item in
                    canceledCard(item)
                }
            }
        }
    }

    private func canceledCard(_ item: NotificationDisplayItem) -> some View {
        HubCard(padding: 11) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    NotificationAppIcon(
                        packageName: item.packageName,
                        fallbackSymbol: iconName(for: item.packageName),
                        deviceID: device?.id,
                        size: 24,
                        isPreview: isPreview)
                    Text(displayName(for: item.packageName))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(timeText(item.postTime))
                        .font(.system(size: 10))
                        .foregroundStyle(tertiaryText)
                }
                if let title = item.title {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(primaryText)
                        .lineLimit(2)
                }
                if let body = item.body, body != item.title {
                    Text(body)
                        .font(.system(size: 11.5))
                        .foregroundStyle(secondaryText)
                        .lineLimit(2)
                }
            }
        }
    }

    private var appNames: [String: String] {
        var names = isPreview ? DashboardPreviewNotifications.appNames : [:]
        // The companion is a first-party app and is not always in the catalog
        // snapshot, so name it explicitly instead of showing a raw package.
        names[CompanionClient.packageName] = "AndroLaunch Comp"
        for app in store.apps where names[app.packageName] == nil {
            names[app.packageName] = app.name
        }
        return names
    }

    /// The preview fixture is deliberately deterministic: it shows the Gmail card
    /// the reference has, while the Hidden section still demonstrates the
    /// contentless rows. Live use always honours "Hide sensitive apps".
    private var hideSensitive: Bool {
        isPreview ? false : NotificationPrivacy.hideSensitiveApps
    }

    private var sections: NotificationSections {
        NotificationGroupingLogic.sections(
            records: records, appNames: appNames, hideSensitive: hideSensitive)
    }

    // MARK: - Colours

    private var primaryText: Color {
        glassMode ? HubColor.glassTextPrimary : HubColor.textPrimary
    }

    private var secondaryText: Color {
        glassMode ? HubColor.glassTextSecondary : HubColor.textSecondary
    }

    private var tertiaryText: Color {
        glassMode ? HubColor.glassTextTertiary : HubColor.textTertiary
    }

    // MARK: - Sync toggle

    private var isSyncOn: Bool {
        if isPreview { return true }
        guard let device else { return false }
        return mirror.isEnabled(for: device)
    }

    private var syncBinding: Binding<Bool> {
        Binding(
            get: { isSyncOn },
            set: { newValue in
                guard !isPreview, let device else { return }
                mirror.setDeviceEnabled(newValue, for: device)
            })
    }

    private var syncStatus: String {
        if isPreview { return "Mirroring" }
        guard let device else { return "No phone connected" }
        if !device.isConnected { return "Offline — reconnect the phone" }
        return mirror.statusText(for: device)
    }

    private var showsSections: Bool { isSyncOn }

    private var syncRow: some View {
        HubCard(padding: 11) {
            HStack(spacing: 9) {
                Image(systemName: device?.isWirelessTransport == true ? "wifi" : "iphone.gen3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(secondaryText)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device?.name ?? "No phone connected")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                    Text(syncStatus)
                        .font(.system(size: 10))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("Sync to Mac")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(secondaryText)
                NotificationNeutralSwitch(isOn: syncBinding, disabled: device == nil)
                    .accessibilityLabel("Sync notifications to the Mac")
            }
        }
    }

    // MARK: - Sections

    private var visibleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: "Showing \(sections.visible.count)",
                expanded: $showingExpanded,
                close: {
                    withAnimation(.easeOut(duration: 0.16)) { cleared = true }
                })
            if showingExpanded {
                ForEach(sections.visible) { group in
                    groupCard(group)
                }
            }
        }
    }

    private var hiddenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: "Hidden \(sections.hidden.count)",
                expanded: $hiddenExpanded,
                close: nil)
            if hiddenExpanded {
                hiddenCard
            }
        }
    }

    private func sectionHeader(
        title: String,
        expanded: Binding<Bool>,
        close: (() -> Void)?
    ) -> some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.14)) { expanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tertiaryText)
                        .rotationEffect(.degrees(expanded.wrappedValue ? 0 : -90))
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint(expanded.wrappedValue ? "Collapse" : "Expand")

            Spacer(minLength: 6)

            if let close {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(tertiaryText)
                        .frame(width: 18, height: 18)
                        .background {
                            Circle()
                                .fill(glassMode ? Color.clear : HubColor.cardElevated)
                                .hubGlassSurface(cornerRadius: 9, interactive: true)
                        }
                }
                .buttonStyle(.plain)
                .help("Clear the list from the dashboard. Notifications stay on the phone.")
                .accessibilityLabel("Clear notification list")
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Group card

    private func groupCard(_ group: NotificationPackageGroup) -> some View {
        let expanded = expandedGroups.contains(group.packageName)
        return HubCard(padding: 11) {
            VStack(alignment: .leading, spacing: 8) {
                groupHeader(group, expanded: expanded)
                if let item = group.items.first {
                    itemText(item, fullBody: expanded)
                    if expanded && group.count > 1 {
                        ForEach(Array(group.items.dropFirst())) { extra in
                            Rectangle()
                                .fill(HubColor.stroke)
                                .frame(height: 1)
                                .padding(.vertical, 1)
                            itemText(extra, fullBody: true)
                            actionRow(item: extra)
                        }
                    }
                    if !expanded && group.count > 1 {
                        Text(group.mirroredCountText)
                            .font(.system(size: 10.5))
                            .foregroundStyle(tertiaryText)
                            .padding(.leading, 2)
                    }
                    actionRow(item: item)
                }
            }
        }
    }

    private func groupHeader(_ group: NotificationPackageGroup, expanded: Bool) -> some View {
        HStack(spacing: 7) {
            NotificationAppIcon(
                packageName: group.packageName,
                fallbackSymbol: iconName(for: group.packageName),
                deviceID: device?.id,
                size: 24,
                isPreview: isPreview)

            HStack(spacing: 5) {
                Text(group.displayName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                if let sender = group.items.first?.sender {
                    Text("·")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(tertiaryText)
                    Text(sender)
                        .font(.system(size: 11))
                        .foregroundStyle(tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 6)

            Text(timeText(group.latestPostTime))
                .font(.system(size: 10))
                .foregroundStyle(tertiaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)

            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    if expanded {
                        expandedGroups.remove(group.packageName)
                    } else {
                        expandedGroups.insert(group.packageName)
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(tertiaryText)
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? "Collapse notifications" : "Show all notifications from this app")
            .accessibilityLabel(expanded ? "Collapse \(group.displayName)" : "Expand \(group.displayName)")

            accessory(group)
        }
    }

    @ViewBuilder
    private func accessory(_ group: NotificationPackageGroup) -> some View {
        if let sender = group.items.first?.sender,
            let initial = group.items.first?.senderInitial
        {
            SenderAvatar(initial: initial, size: 28)
                .accessibilityLabel("From \(sender)")
        } else if group.count > 1 {
            NotificationAppIcon(
                packageName: group.packageName,
                fallbackSymbol: iconName(for: group.packageName),
                deviceID: device?.id,
                size: 28,
                isPreview: isPreview)
        }
    }

    private func itemText(_ item: NotificationDisplayItem, fullBody: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let title = item.title {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(fullBody ? 4 : 2)
            }
            if let body = item.body, body != item.title {
                Text(body)
                    .font(.system(size: 11.5))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(fullBody ? 6 : 2)
            } else if item.title == nil && item.body == nil {
                Text("(No displayable content)")
                    .font(.system(size: 11))
                    .foregroundStyle(tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 2)
    }

    // MARK: - Actions

    private func actionRow(item: NotificationDisplayItem) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            if replyingKey == item.key {
                replyComposer(item)
            }
            HStack(spacing: 5) {
                Spacer(minLength: 0)
                if item.canDismiss {
                    NotificationGlassPill(title: "Delete", icon: "trash") {
                        delete(item)
                    }
                }
                if let readIndex = item.readActionIndex {
                    NotificationGlassPill(title: "Mark as read", icon: "checkmark") {
                        markAsRead(item, actionIndex: readIndex)
                    }
                }
                NotificationGlassPill(
                    title: "Reply", icon: "arrowshape.turn.up.left",
                    enabled: item.hasReply && !isPreview
                ) {
                    beginReply(item)
                }
                NotificationGlassPill(title: "Open", icon: "arrow.up.forward.app") {
                    open(item)
                }
            }
        }
        .padding(.top, 1)
    }

    private func replyComposer(_ item: NotificationDisplayItem) -> some View {
        HStack(spacing: 6) {
            TextField("Reply…", text: $replyText)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(primaryText)
                .focused($replyFieldFocused)
                .onSubmit { sendReply(item) }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(glassMode ? Color.clear : HubColor.cardElevated)
                        .hubGlassSurface(cornerRadius: 8)
                }
            NotificationGlassPill(
                title: isSendingReply ? "Sending…" : "Send",
                icon: "paperplane",
                enabled: !trimmedReply.isEmpty && !isSendingReply
            ) {
                sendReply(item)
            }
            NotificationGlassPill(title: "Cancel", icon: nil, enabled: true) {
                cancelReply()
            }
        }
    }

    // MARK: - Hidden

    private var hiddenCard: some View {
        HubCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(sections.hidden.enumerated()), id: \.offset) { index, group in
                    if index > 0 {
                        Rectangle()
                            .fill(HubColor.stroke)
                            .frame(height: 1)
                            .padding(.leading, 38)
                    }
                    hiddenRow(group)
                }
            }
        }
    }

    private func hiddenRow(_ group: NotificationPackageGroup) -> some View {
        HStack(spacing: 9) {
            NotificationAppIcon(
                packageName: group.packageName,
                fallbackSymbol: iconName(for: group.packageName),
                deviceID: device?.id,
                size: 20,
                isPreview: isPreview)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(group.displayName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                    if group.count > 1 {
                        Text("\(group.count)")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(tertiaryText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(HubColor.controlTrack))
                    }
                }
                Text("(No displayable content)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(tertiaryText)
            }
            Spacer(minLength: 6)
            Text(timeText(group.latestPostTime))
                .font(.system(size: 10))
                .foregroundStyle(tertiaryText)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
    }

    // MARK: - Empty / cleared states

    private var syncOffState: some View {
        HubCard {
            HubEmptyState(
                icon: "bell.slash",
                title: "Notifications stay on the phone",
                subtitle:
                    "Turn on Sync to Mac to read them here. Nothing is read or mirrored until you do.")
        }
    }

    private var emptyOnState: some View {
        HubCard {
            HubEmptyState(
                icon: "bell",
                title: "No notifications right now",
                subtitle: "New notifications appear here without leaving the phone.")
        }
    }

    private var clearedState: some View {
        HubCard {
            HubEmptyState(
                icon: "bell.slash",
                title: "List cleared from the dashboard",
                subtitle:
                    "Notifications are still on the phone. New ones appear here automatically.")
            Button {
                withAnimation(.easeOut(duration: 0.16)) { cleared = false }
            } label: {
                Text("Show again")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        Capsule()
                            .fill(glassMode ? Color.clear : HubColor.cardElevated)
                            .hubGlassSurface(cornerRadius: 12, interactive: true)
                    }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Actions

    private func open(_ item: NotificationDisplayItem) {
        guard !isPreview, let device else { return }
        guard ADBService.isSafePackageIdentifier(item.packageName) else {
            report("That notification has no launchable app behind it.", isError: true)
            return
        }
        DependencyContainer.shared.adb.launchPackageOnDevice(
            deviceID: device.id, packageID: item.packageName
        ) { success in
            DispatchQueue.main.async {
                if success {
                    report("Opened \(displayName(for: item.packageName)) on \(device.name).")
                } else {
                    report("The phone couldn't open that app.", isError: true)
                }
            }
        }
    }

    private func delete(_ item: NotificationDisplayItem) {
        guard !isPreview, let device else { return }
        CompanionClient.shared.dismissNotification(
            key: item.key, deviceID: device.id
        ) { success, message in
            DispatchQueue.main.async {
                if success {
                    report("Deleted on \(device.name).")
                    rememberCanceled(item)
                    removedKeys.insert(item.key)
                    refreshRecords()
                } else {
                    report(message ?? "The notification may already be gone.", isError: true)
                }
            }
        }
    }

    private func markAsRead(_ item: NotificationDisplayItem, actionIndex: Int) {
        guard !isPreview, let device else { return }
        CompanionClient.shared.actionNotification(
            key: item.key, actionIndex: actionIndex, deviceID: device.id
        ) { success, message in
            DispatchQueue.main.async {
                if success {
                    report("Marked as read on \(device.name).")
                } else {
                    report(
                        Self.actionFailureText(message, action: "mark it as read"),
                        isError: true)
                }
            }
        }
    }

    private func beginReply(_ item: NotificationDisplayItem) {
        guard !isPreview else { return }
        withAnimation(.easeOut(duration: 0.14)) {
            replyingKey = item.key
            replyText = ""
        }
        DispatchQueue.main.async { replyFieldFocused = true }
    }

    private func cancelReply() {
        withAnimation(.easeOut(duration: 0.14)) {
            replyingKey = nil
            replyText = ""
        }
        replyFieldFocused = false
    }

    private func sendReply(_ item: NotificationDisplayItem) {
        guard !isPreview, let device else { return }
        let text = trimmedReply
        guard !text.isEmpty else { return }
        isSendingReply = true
        CompanionClient.shared.reply(
            toNotificationKey: item.key,
            actionIndex: item.replyActionIndex,
            text: text,
            deviceID: device.id
        ) { success, message in
            DispatchQueue.main.async {
                isSendingReply = false
                if success {
                    report("Reply sent from \(device.name).")
                    cancelReply()
                } else {
                    report(
                        NotificationMirror.replyFailureText(message),
                        isError: true)
                }
            }
        }
    }

    private var trimmedReply: String {
        replyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func report(_ text: String, isError: Bool = false) {
        withAnimation(.easeOut(duration: 0.14)) {
            feedback = text
            feedbackIsError = isError
        }
    }

    /// Turns a companion action failure into copy people can act on.
    static func actionFailureText(_ message: String?, action: String) -> String {
        guard let message, !message.isEmpty else {
            return "The phone didn't let us \(action) this notification."
        }
        if message.contains("unknown_command") {
            return "Update AndroLaunch Comp on the phone to \(action) from the Mac."
        }
        if message == "no_action" {
            return "This app doesn't expose that action. Open it on the phone instead."
        }
        if message == "gone" {
            return "That notification is no longer on the phone."
        }
        return message
    }

    // MARK: - Helpers

    private func timeText(_ postTime: Int64) -> String {
        DeviceDashboardLogic.relativeTime(postTimeMilliseconds: postTime)
    }

    private func displayName(for packageName: String) -> String {
        NotificationGroupingLogic.displayName(
            for: packageName, appNames: appNames)
    }

    /// Neutral SF Symbol for the app's fallback tile (used until the real icon
    /// arrives, and deterministically in snapshots).
    private func iconName(for packageName: String) -> String {
        if let app = store.apps.first(where: { $0.packageName == packageName }) {
            return AppIconMapper.getIconName(for: app)
        }
        if packageName.contains("systemui") { return "gearshape.fill" }
        if packageName.contains("security") { return "shield.lefthalf.filled" }
        if packageName.contains("notification") { return "bell.fill" }
        if packageName.contains("gmail") || packageName.contains("mail") {
            return "envelope.fill"
        }
        if packageName.contains("message") || packageName.contains("whatsapp") {
            return "message.fill"
        }
        if packageName.contains("androlaunch") || packageName.contains("senpai") {
            return "ant.fill"
        }
        return "app.fill"
    }
}

// MARK: - Glass controls

/// Compact monochrome action pill. Uses the shared glass surface when the
/// dashboard is hosted in the menu-bar glass panel and a neutral fill otherwise.
private struct NotificationGlassPill: View {
    let title: String
    var icon: String? = nil
    var enabled: Bool = true
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.hubGlassMode) private var glassMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(
                enabled
                    ? (hovering
                        ? (glassMode ? HubColor.glassTextPrimary : HubColor.textPrimary)
                        : (glassMode ? HubColor.glassTextSecondary : HubColor.textSecondary))
                    : (glassMode ? HubColor.glassTextTertiary : HubColor.textTertiary))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(pillBackground)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.6)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .hoverGlassCapsule(enabled: enabled, scale: 1.05, liftShadow: false)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var pillBackground: some View {
        if glassMode {
            Capsule()
                .fill(Color.clear)
                .hubGlassSurface(cornerRadius: 12, interactive: true)
        } else {
            Capsule()
                .fill(hovering ? HubColor.cardHover : HubColor.cardElevated)
                .overlay(Capsule().strokeBorder(HubColor.stroke, lineWidth: 1))
        }
    }
}

/// Monochrome switch used by the Notifications tab (the shared `HubSwitch`
/// carries the accent tint, which this redesign deliberately avoids).
private struct NotificationNeutralSwitch: View {
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        Button {
            guard !disabled else { return }
            withAnimation(.easeOut(duration: 0.16)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? HubColor.textPrimary.opacity(0.88) : HubColor.controlTrack)
                    .frame(width: 32, height: 19)
                    .overlay(
                        Capsule().strokeBorder(HubColor.stroke, lineWidth: 1))
                Circle()
                    .fill(isOn ? HubColor.windowTop : HubColor.textPrimary.opacity(0.85))
                    .frame(width: 15, height: 15)
                    .padding(2)
                    .shadow(color: .black.opacity(0.2), radius: 1.2, y: 0.5)
            }
            .opacity(disabled ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// Neutral sender avatar, the reference product's monochrome initial circle.
private struct SenderAvatar: View {
    let initial: String
    var size: CGFloat = 28

    @Environment(\.hubGlassMode) private var glassMode

    var body: some View {
        Circle()
            .fill(glassMode ? Color.clear : HubColor.cardElevated)
            .frame(width: size, height: size)
            .overlay {
                if glassMode {
                    Circle().fill(.ultraThinMaterial)
                }
            }
            .overlay(
                Circle().strokeBorder(HubColor.stroke, lineWidth: 1))
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(
                        glassMode ? HubColor.glassTextPrimary : HubColor.textPrimary))
    }
}

/// App icon for notification rows.
///
/// Production uses the shared `AppIconView` + `AppIconStore` so real launcher
/// artwork appears. While the cache is still empty (or in deterministic
/// snapshots, which never start network work) it draws the neutral monochrome
/// tile instead, which keeps the redesign free of the accent tint and avoids a
/// symbol→photo flash.
private struct NotificationAppIcon: View {
    let packageName: String
    let fallbackSymbol: String
    let deviceID: String?
    var size: CGFloat = 24
    let isPreview: Bool

    @ObservedObject private var iconStore = AppIconStore.shared
    @Environment(\.hubGlassMode) private var glassMode
    @Environment(\.hubSnapshotMode) private var snapshotMode

    var body: some View {
        Group {
            if let deviceID, !isPreview,
                iconStore.cachedImage(deviceID: deviceID, packageName: packageName) != nil
            {
                AppIconView(
                    packageName: packageName,
                    fallbackSymbol: fallbackSymbol,
                    size: size,
                    deviceID: deviceID)
            } else {
                monochromeTile
            }
        }
        .frame(width: size, height: size)
        .onAppear(perform: requestIconIfNeeded)
    }

    private var monochromeTile: some View {
        RoundedRectangle(cornerRadius: max(6, size * 0.235), style: .continuous)
            .fill(glassMode ? Color.clear : HubColor.cardElevated)
            .frame(width: size, height: size)
            .overlay {
                if glassMode {
                    RoundedRectangle(cornerRadius: max(6, size * 0.235), style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay(
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(
                        glassMode ? HubColor.glassTextSecondary : HubColor.textSecondary))
            .overlay(
                RoundedRectangle(cornerRadius: max(6, size * 0.235), style: .continuous)
                    .strokeBorder(HubColor.stroke, lineWidth: 1))
    }

    private func requestIconIfNeeded() {
        guard !isPreview, !snapshotMode, let deviceID, deviceID.isEmpty == false else { return }
        iconStore.ensureIcons(packages: [packageName], deviceID: deviceID)
    }
}

// MARK: - Preview fixtures

/// Deterministic notification records for the snapshot renderer, shaped like the
/// current reference: four mirrored companion notifications, a Gmail card with a
/// sender and read/reply actions, the android wireless-debugging row, and hidden
/// system rows with no displayable content. Times are relative to now so the
/// rendered "ago" copy stays realistic; no record ever comes from a device.
enum DashboardPreviewNotifications {

    /// Three deterministic cards for the Recently Canceled section.
    static var canceledItems: [NotificationDisplayItem] {
        var items: [NotificationDisplayItem] = []
        if let companion = records.first(where: {
            $0.packageName == CompanionClient.packageName
        }) {
            items.append(NotificationGroupingLogic.displayItem(from: companion))
        }
        if let mail = records.first(where: { $0.packageName == "com.google.android.gm" }) {
            items.append(NotificationGroupingLogic.displayItem(from: mail))
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let buds = AndroidNotificationRecord(
            packageName: "com.google.android.gms",
            key: "preview|canceled|gms",
            postTime: now - 23 * 60 * 1000,
            title: "Aman's realme Buds Air 2 Neo",
            text: "Left 100% Right 100%",
            flags: 0,
            isMedia: false)
        items.append(NotificationGroupingLogic.displayItem(from: buds))
        return items
    }

    /// Friendly labels for fixture packages the preview catalog does not carry.
    static var appNames: [String: String] {
        [
            "com.android.systemui": "android",
            "com.miui.notification": "com.miui.notification",
            "com.miui.securitycore": "Security",
            "com.android.vending": "Play Store",
            "com.google.android.gms": "com.google.android.gms",
        ]
    }

    static var records: [AndroidNotificationRecord] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return [
            // Four mirrored companion notifications → "4 notifications mirrored".
            AndroidNotificationRecord(
                packageName: "com.senpai.androlaunch.companion",
                key: "preview|companion|1",
                postTime: now - 1_000,
                title: "AndroLaunch Comp",
                text: "Synced just now",
                flags: 0,
                isMedia: false),
            AndroidNotificationRecord(
                packageName: "com.senpai.androlaunch.companion",
                key: "preview|companion|2",
                postTime: now - 12_000,
                title: "AndroLaunch Comp",
                text: "Clipboard sent to Pixel 9 Pro",
                flags: 0,
                isMedia: false),
            AndroidNotificationRecord(
                packageName: "com.senpai.androlaunch.companion",
                key: "preview|companion|3",
                postTime: now - 25_000,
                title: "AndroLaunch Comp",
                text: "Screen mirror stopped",
                flags: 0,
                isMedia: false),
            AndroidNotificationRecord(
                packageName: "com.senpai.androlaunch.companion",
                key: "preview|companion|4",
                postTime: now - 40_000,
                title: "AndroLaunch Comp",
                text: "Wireless debugging authorised",
                flags: 0,
                isMedia: false),

            // Gmail-style record: sender in title, "Subject — snippet" in text,
            // with real Mark-as-read and direct-reply actions.
            AndroidNotificationRecord(
                packageName: "com.google.android.gm",
                key: "preview|gmail|1",
                postTime: now - 55 * 60_000,
                title: "amanraj.hello@gmail.com",
                text: "Axis Bank Cards — Elevate your festive celebration!",
                flags: 0,
                isMedia: false,
                actions: [
                    AndroidNotificationAction(
                        index: 0, title: "Mark as read", hasReply: false),
                    AndroidNotificationAction(
                        index: 1, title: "Reply", hasReply: true),
                ]),

            // android / wireless debugging.
            AndroidNotificationRecord(
                packageName: "com.android.systemui",
                key: "preview|systemui|1",
                postTime: now - 60 * 60_000,
                title: "Wireless debugging connected",
                text: "Tap to turn off wireless debugging",
                // FLAG_ONGOING_EVENT: the phone cannot dismiss this one, so the
                // card honestly omits Delete.
                flags: 0x0000_0002,
                isMedia: false),

            // Hidden section: the phone exposed no readable content.
            AndroidNotificationRecord(
                packageName: "com.miui.notification",
                key: "preview|miui|1",
                postTime: now - 2 * 86_400_000,
                title: nil,
                text: nil,
                flags: 0,
                isMedia: false),
            AndroidNotificationRecord(
                packageName: "com.miui.securitycore",
                key: "preview|security|1",
                postTime: now - 3 * 86_400_000,
                title: nil,
                text: nil,
                flags: 0,
                isMedia: false),
            AndroidNotificationRecord(
                packageName: "com.android.vending",
                key: "preview|vending|1",
                postTime: now - 4 * 86_400_000,
                title: nil,
                text: nil,
                flags: 0,
                isMedia: false),
        ]
    }
}
