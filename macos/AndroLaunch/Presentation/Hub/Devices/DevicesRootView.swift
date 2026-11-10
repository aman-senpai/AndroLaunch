//
//  DevicesRootView.swift
//  AndroLaunch
//
//  The Devices surface: every way to reach a phone in one scroll.
//  USB connection (with live links and real ADB state), Wi-Fi pairing (QR,
//  pairing code, IP, companion) and "On this Mac" for the Android emulator.
//  Owned by connection-ui; shared state comes from HubStore.
//

import SwiftUI

struct DevicesRootView: View {
    @ObservedObject var store: HubStore

    @Environment(\.hubPreviewScenario) private var scenario
    @StateObject private var links: DeviceLinkMonitor
    @State private var usbExpanded = true
    @State private var wifiExpanded = false
    @State private var macExpanded = false
    @State private var inventory = EmulatorInventory.load()

    init(store: HubStore) {
        self.store = store
        _links = StateObject(wrappedValue: DeviceLinkMonitor(preview: store.isPreview))
    }

    // MARK: - Body

    var body: some View {
        HubPage {
            HubSectionHeader("Connection") {
                connectionSummary
            }
            usbCard
            wifiCard
            macCard
            footer
        }
        .onAppear {
            guard !store.isPreview else { return }
            links.refresh()
        }
        .onChange(of: store.isRefreshing) { _, refreshing in
            guard !refreshing else { return }
            refreshLinks()
        }
    }

    // MARK: - Scenario / expansion

    /// The snapshot renderer drives these strings so every expanded state can be
    /// reviewed. Normal use falls through to the interactive `@State` bindings.
    private var effectiveUSBExpanded: Bool {
        switch scenario {
        case "devices-expanded": return true
        case "wifi-expanded": return false
        default: return usbExpanded
        }
    }

    private var effectiveWiFiExpanded: Bool {
        switch scenario {
        case "wifi-expanded": return true
        case "devices-expanded": return false
        default: return wifiExpanded
        }
    }

    private var effectiveMacExpanded: Bool {
        switch scenario {
        case "devices-expanded": return true
        case "wifi-expanded": return false
        default: return macExpanded
        }
    }

    private var usbBinding: Binding<Bool> {
        Binding(get: { effectiveUSBExpanded }, set: { usbExpanded = $0 })
    }

    private var wifiBinding: Binding<Bool> {
        Binding(get: { effectiveWiFiExpanded }, set: { wifiExpanded = $0 })
    }

    private var macBinding: Binding<Bool> {
        Binding(get: { effectiveMacExpanded }, set: { macExpanded = $0 })
    }

    // MARK: - Header summary

    @ViewBuilder
    private var connectionSummary: some View {
        let count = store.connectedDevices.count
        if count > 0 {
            HStack(spacing: 5) {
                HubStatusDot(color: HubColor.success, size: 6)
                Text("\(count) connected")
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textTertiary)
            }
        } else if !store.isPreview {
            Text(links.isRefreshing ? "Checking…" : "No devices")
                .font(.hubCaption)
                .foregroundStyle(HubColor.textTertiary)
        }
    }

    // MARK: - USB

    private var usbCard: some View {
        DeviceCollapsibleCard(
            icon: "cable.connector",
            tint: HubColor.success,
            title: "USB Connection",
            subtitle: usbSubtitle,
            showsStatusDot: usbConnectedCount,
            expanded: usbBinding
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if deviceRows.isEmpty {
                    HubEmptyState(
                        icon: "cable.connector",
                        title: "No devices connected",
                        subtitle:
                            "Use a data-capable USB cable and allow debugging when the phone asks."
                    )
                    DeviceCardLabel(text: "How to connect")
                    DeviceSteps(steps: Self.usbSteps, compact: true)
                } else {
                    VStack(spacing: 2) {
                        ForEach(deviceRows) { row in
                            DeviceLinkRow(
                                device: row.device,
                                entry: row.entry,
                                isSelected: row.device.map { $0.id == store.selectedDeviceID } ?? false,
                                action: row.device.map { device -> () -> Void in
                                    { store.select(device) }
                                }
                            )
                        }
                    }
                    DeviceCardLabel(text: "Add another device")
                    DeviceSteps(steps: Self.usbSteps, compact: true)
                }

                HStack(spacing: 10) {
                    if store.connectedDevices.isEmpty {
                        Text("No connections yet")
                            .font(.hubCaption)
                            .foregroundStyle(HubColor.textTertiary)
                    } else {
                        Text(
                            store.connectedDevices.count == 1
                                ? "1 of 5 connections"
                                : "\(store.connectedDevices.count) of 5 connections"
                        )
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textTertiary)
                    }
                    Spacer(minLength: 8)
                    HubActionButton(
                        title: store.isRefreshing || links.isRefreshing ? "Refreshing…" : "Refresh",
                        icon: "arrow.clockwise",
                        style: .secondary,
                        enabled: !store.isRefreshing && !links.isRefreshing
                    ) {
                        refresh()
                    }
                    .accessibilityLabel("Refresh device list")
                }
            }
        }
    }

    private static let usbSteps = [
        "Connect a data-capable USB cable, then unlock the phone.",
        "Turn on Developer options › USB debugging on the phone.",
        "Tap Allow when the phone asks to authorize this Mac.",
    ]

    private var usbConnectedCount: Bool {
        deviceRows.contains {
            $0.device?.isConnected == true || $0.entry?.state == .connected
        }
    }

    private var usbSubtitle: String {
        if deviceRows.isEmpty {
            if !store.isPreview, case .failed = links.probeState {
                return "ADB unavailable — check Android platform-tools."
            }
            return "Connect via USB cable and allow debugging."
        }
        if deviceRows.count == 1, let name = deviceRows.first?.device?.name {
            return "\(name) connected over USB"
        }
        return deviceRows.count == 1
            ? "1 device connected over USB" : "\(deviceRows.count) devices connected over USB"
    }

    private struct DeviceRowModel: Identifiable {
        let id: String
        let device: AndroidDevice?
        let entry: ADBLinkEntry?
    }

    /// Authorized devices come from `HubStore` (they carry battery/model); the
    /// raw ADB probe contributes unauthorized and offline links so those states
    /// are visible rather than silently missing. Only wired transports belong
    /// under "USB Connection" — the Wi-Fi card owns its own device list.
    private var deviceRows: [DeviceRowModel] {
        if store.isPreview {
            return store.devices
                .filter { !$0.isWirelessTransport }
                .map { DeviceRowModel(id: $0.id, device: $0, entry: nil) }
        }
        var rows: [DeviceRowModel] = []
        var seen = Set<String>()
        for device in store.devices where !device.isWirelessTransport {
            seen.insert(device.id)
            rows.append(
                DeviceRowModel(
                    id: device.id,
                    device: device,
                    entry: links.entries.first { $0.id == device.id }))
        }
        for entry in links.entries
        where !seen.contains(entry.id) && TransportKind.classify(entry.id) == .usb {
            rows.append(DeviceRowModel(id: entry.id, device: nil, entry: entry))
        }
        return rows
    }

    private var wifiRows: [DeviceRowModel] {
        guard !store.isPreview else {
            return store.devices
                .filter(\.isWirelessTransport)
                .map { DeviceRowModel(id: $0.id, device: $0, entry: nil) }
        }
        return store.devices
            .filter(\.isWirelessTransport)
            .map { device in
                DeviceRowModel(
                    id: device.id,
                    device: device,
                    entry: links.entries.first { $0.id == device.id })
            }
    }

    // MARK: - Wi-Fi

    private var wifiCard: some View {
        DeviceCollapsibleCard(
            icon: "wifi",
            tint: HubColor.accent,
            title: "Wi-Fi Connection",
            subtitle: wifiSubtitle,
            badge: wifiDevices.isEmpty ? nil : "Connected",
            badgeTint: HubColor.success,
            expanded: wifiBinding
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if !wifiRows.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        DeviceCardLabel(text: "Connected over Wi-Fi")
                        VStack(spacing: 2) {
                            ForEach(wifiRows) { row in
                                DeviceLinkRow(
                                    device: row.device,
                                    entry: row.entry,
                                    isSelected: row.device.map {
                                        $0.id == store.selectedDeviceID
                                    } ?? false,
                                    action: row.device.map { device -> () -> Void in
                                        { store.select(device) }
                                    }
                                )
                            }
                        }
                    }
                }
                WiFiConnectionView(store: store)
            }
        }
    }

    private var wifiDevices: [AndroidDevice] {
        store.devices.filter(\.isWirelessTransport)
    }

    private var wifiSubtitle: String {
        if wifiDevices.count == 1, let device = wifiDevices.first {
            return "Connected to \(device.name)"
        }
        if wifiDevices.count > 1 {
            return "\(wifiDevices.count) devices connected over Wi-Fi"
        }
        return "Pair with a QR code, pairing code or IP address."
    }

    // MARK: - On this Mac

    private var macCard: some View {
        DeviceCollapsibleCard(
            icon: "display",
            tint: HubColor.success,
            title: "On this Mac",
            subtitle: inventory.summary,
            expanded: macBinding
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "Create and run virtual Android devices with the Android emulator. AndroLaunch manages the emulator already on this Mac — it doesn't bundle an Android system image."
                )
                .font(.hubRowSubtitle)
                .foregroundStyle(HubColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                if inventory.avdNames.isEmpty {
                    HubNote(
                        text:
                            "No virtual devices yet. Open Emulator Manager to download a system image and create one.",
                        icon: "info.circle")
                } else {
                    VStack(spacing: 2) {
                        ForEach(inventory.avdNames.prefix(4), id: \.self) { name in
                            HStack(spacing: 10) {
                                HubIconTile(
                                    systemName: "ipad.landscape",
                                    tint: HubColor.textSecondary,
                                    size: 26)
                                Text(name)
                                    .font(.hubRowTitle)
                                    .foregroundStyle(HubColor.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("Virtual device")
                                    .font(.hubCaption)
                                    .foregroundStyle(HubColor.textTertiary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                        }
                        if inventory.avdNames.count > 4 {
                            Text("+\(inventory.avdNames.count - 4) more")
                                .font(.hubCaption)
                                .foregroundStyle(HubColor.textTertiary)
                                .padding(.leading, 10)
                        }
                    }
                }

                HubActionButton(
                    title: "Open Emulator Manager",
                    icon: "arrow.up.forward.app",
                    style: .secondary,
                    fullWidth: true
                ) {
                    guard !store.isPreview else { return }
                    DeviceWindowRouter.openEmulatorManager()
                }

                HubNote(
                    text:
                        "Emulators appear as devices here and in Apps once they finish booting.",
                    icon: "info.circle")
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 7) {
            Text("Supports up to 5 devices connected at the same time")
                .font(.hubCaption)
                .foregroundStyle(HubColor.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            DeviceStatusLine(
                text: adbStatusText,
                tint: adbStatusTint,
                busy: adbBusy)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 2)
    }

    // MARK: - ADB state

    private var adbStatusText: String {
        if store.isPreview { return "ADB running normally" }
        switch links.probeState {
        case .unknown:
            return links.isRefreshing ? "Checking ADB…" : "ADB status unknown"
        case .running:
            return "ADB running normally"
        case .failed(let message):
            let firstLine = message.components(separatedBy: .newlines).first ?? message
            return "ADB unavailable — \(firstLine)"
        }
    }

    private var adbStatusTint: Color {
        if store.isPreview { return HubColor.success }
        switch links.probeState {
        case .running: return HubColor.success
        case .unknown: return HubColor.textSecondary
        case .failed: return HubColor.danger
        }
    }

    private var adbBusy: Bool {
        !store.isPreview && links.isRefreshing && links.probeState == .unknown
    }

    // MARK: - Actions

    private func refresh() {
        guard !store.isPreview else { return }
        store.refresh()
        refreshLinks()
    }

    private func refreshLinks() {
        guard !store.isPreview else { return }
        links.refresh()
        inventory = EmulatorInventory.load()
    }
}
