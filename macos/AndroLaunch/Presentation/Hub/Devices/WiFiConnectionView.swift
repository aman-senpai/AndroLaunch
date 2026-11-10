//
//  WiFiConnectionView.swift
//  AndroLaunch
//
//  The four real wireless connection paths, shared by the Devices card and the
//  standalone snapshot renderer: QR pairing, pairing code, IP address and the
//  phone companion. Every action talks to adb/Bonjour; failures are shown as
//  the actual reason adb returned.
//

import AppKit
import SwiftUI

enum WiFiConnectionTab: String, CaseIterable, Identifiable {
    case qr
    case pairingCode
    case ipAddress
    case companion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qr: return "QR code"
        case .pairingCode: return "Pairing code"
        case .ipAddress: return "IP address"
        case .companion: return "Mobile app"
        }
    }

    var icon: String {
        switch self {
        case .qr: return "qrcode"
        case .pairingCode: return "number"
        case .ipAddress: return "network"
        case .companion: return "iphone.gen3"
        }
    }
}

struct WiFiConnectionView: View {
    @ObservedObject var store: HubStore
    @StateObject private var service: WirelessPairingService
    @State private var tab: WiFiConnectionTab
    @State private var pairingCode = ""
    @State private var manualAddress = ""
    @State private var manualAddressExpanded = false
    @State private var ipAddress = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: HubStore, initialTab: WiFiConnectionTab = .qr) {
        self.store = store
        _tab = State(initialValue: initialTab)
        _service = StateObject(wrappedValue: WirelessPairingService(preview: store.isPreview))
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HubSegmentedTabs(
                items: WiFiConnectionTab.allCases.map {
                    .init(value: $0, title: $0.title, icon: $0.icon)
                },
                selection: $tab,
                compact: true)

            HubCard(padding: 13, elevated: true) {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case .qr: qrContent
                    case .pairingCode: pairingCodeContent
                    case .ipAddress: ipContent
                    case .companion: companionContent
                    }
                }
            }
        }
        .onAppear { activate(tab) }
        .onDisappear { service.stop() }
        .onChange(of: tab) { _, newTab in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                activate(newTab)
            }
        }
        .onChange(of: service.connectionGeneration) { _, _ in
            store.refresh()
        }
        .onChange(of: pairingCode) { _, value in
            let digits = String(value.filter { $0.isNumber }.prefix(6))
            if digits != value { pairingCode = digits }
        }
        .onChange(of: service.discoveredDevices) { _, devices in
            // Preselect the first pairing window so the code field is immediately
            // usable; the user can still pick another phone from the list.
            if selectedPairEndpoint == nil, let first = devices.first {
                selectedPairEndpoint = first.endpoint
            }
        }
    }

    private func activate(_ tab: WiFiConnectionTab) {
        guard !store.isPreview else { return }
        switch tab {
        case .qr:
            service.startQRPairing()
        case .pairingCode:
            selectedPairEndpoint = nil
            service.startPairingCodeDiscovery()
        case .ipAddress, .companion:
            service.stop()
        }
    }

    // MARK: - QR

    private static let qrSteps = [
        "Keep the phone and this Mac on the same Wi-Fi network.",
        "On the phone, open Developer options › Wireless debugging › Pair device with QR code.",
        "Scan this code and keep this page open until it connects.",
    ]

    private var qrContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            DeviceSteps(steps: Self.qrSteps, compact: true)

            DeviceQRCode(payload: service.qrPayload, size: 176)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 7) {
                if qrStatus.busy {
                    DeviceSpinner(size: 10, tint: qrStatus.tint)
                } else {
                    HubStatusDot(color: qrStatus.tint, size: 6)
                }
                Text(qrStatus.text)
                    .font(.hubRowSubtitle)
                    .foregroundStyle(qrStatus.tint)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if case .failed(let message) = service.qrPhase {
                DeviceFeedbackRow(kind: .failure, message: message)
                HStack(spacing: 8) {
                    HubActionButton(
                        title: "Reset ADB & retry",
                        icon: "arrow.triangle.2.circlepath",
                        style: .secondary
                    ) {
                        service.resetADBAndRegenerateQR()
                    }
                    HubActionButton(
                        title: "Use pairing code",
                        icon: "number",
                        style: .quiet
                    ) {
                        tab = .pairingCode
                    }
                }
            }

            HStack(spacing: 10) {
                HubActionButton(
                    title: "Regenerate QR",
                    icon: "arrow.clockwise",
                    style: .secondary,
                    enabled: !qrIsPairing
                ) {
                    service.regenerateQR()
                }
                Spacer(minLength: 8)
                Text("New code each time")
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textTertiary)
            }

            HubNote(
                text:
                    "Use the phone's Wireless debugging scanner. The QR is read by Android itself — no companion app is needed to pair.",
                icon: "qrcode.viewfinder")
        }
    }

    private var qrIsPairing: Bool {
        switch service.qrPhase {
        case .pairing, .pairedWaiting: return true
        default: return false
        }
    }

    private var qrStatus: (text: String, tint: Color, busy: Bool) {
        switch service.qrPhase {
        case .idle:
            return ("Preparing pairing…", HubColor.textSecondary, false)
        case .waitingForScan:
            return ("Waiting for scan", HubColor.warning, false)
        case .pairing(let endpoint):
            return ("Pairing with \(endpoint)…", HubColor.accent, true)
        case .pairedWaiting:
            return ("Paired. Waiting for the device to come online…", HubColor.accent, false)
        case .connected(let endpoint):
            return ("Connected to \(endpoint)", HubColor.success, false)
        case .failed:
            return ("Pairing failed", HubColor.danger, false)
        }
    }

    // MARK: - Pairing code

    private static let pairingCodeSteps = [
        "Keep the phone and this Mac on the same Wi-Fi network.",
        "On the phone, open Developer options › Wireless debugging › Pair device with pairing code.",
    ]

    private var pairingCodeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeviceSteps(steps: Self.pairingCodeSteps, compact: true)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                DeviceCardLabel(text: "Available Wi-Fi devices")
                Spacer(minLength: 8)
                Text(discoverySummary)
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textTertiary)
            }

            discoveryList

            HStack(spacing: 8) {
                DeviceTextField(
                    placeholder: "Pairing code",
                    text: $pairingCode,
                    icon: "number",
                    monospaced: true,
                    invalid: !pairingCode.isEmpty && !WirelessPairingCode.isValid(pairingCode)
                )
                HubActionButton(
                    title: pairButtonBusy ? "Pairing…" : "Pair and Connect",
                    icon: nil,
                    style: .primary,
                    enabled: canPair && !pairButtonBusy
                ) {
                    if let endpoint = pairEndpoint {
                        service.pair(endpoint: endpoint, code: pairingCode)
                    }
                }
            }

            if !pairingCode.isEmpty && !WirelessPairingCode.isValid(pairingCode) {
                Text("Enter the 6-digit pairing code shown on the phone.")
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.danger)
                    .padding(.leading, 2)
            }

            Button {
                manualAddressExpanded.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: manualAddressExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Enter pairing address manually")
                        .font(.hubButton)
                }
                .foregroundStyle(HubColor.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Enter pairing address manually")

            if manualAddressExpanded {
                DeviceTextField(
                    placeholder: "192.168.1.23:37123",
                    text: $manualAddress,
                    icon: "network",
                    monospaced: true,
                    invalid: manualAddressInvalid
                )
                if let message = manualAddressError {
                    Text(message)
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.danger)
                        .padding(.leading, 2)
                }
            }

            feedback(for: service.pairPhase)

            HubNote(
                text:
                    "Keep the pairing dialog open on the phone. The code is single-use and expires when the dialog closes.",
                icon: "number")
        }
    }

    @ViewBuilder
    private var discoveryList: some View {
        if !service.discoveredDevices.isEmpty {
            VStack(spacing: 4) {
                ForEach(service.discoveredDevices) { device in
                    Button {
                        selectedPairEndpoint = device.endpoint
                    } label: {
                        HStack(spacing: 10) {
                            HubIconTile(systemName: "wifi", tint: HubColor.accent, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.title)
                                    .font(.hubRowTitle)
                                    .foregroundStyle(HubColor.textPrimary)
                                    .lineLimit(1)
                                Text(device.name)
                                    .font(.hubCaption)
                                    .foregroundStyle(HubColor.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            if selectedPairEndpoint == device.endpoint {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(HubColor.accent)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(
                                    selectedPairEndpoint == device.endpoint
                                        ? HubColor.accentSoft : HubColor.card))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(
                                    selectedPairEndpoint == device.endpoint
                                        ? HubColor.accent.opacity(0.3) : HubColor.stroke,
                                    lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if case .failed(let message) = service.discoveryPhase {
            VStack(alignment: .leading, spacing: 9) {
                DeviceFeedbackRow(kind: .failure, message: message)
                HStack(spacing: 8) {
                    HubActionButton(title: "Try Again", icon: "arrow.clockwise", style: .secondary) {
                        selectedPairEndpoint = nil
                        service.retryDiscovery()
                    }
                    HubActionButton(
                        title: "Local Network Settings", icon: "gearshape", style: .quiet
                    ) {
                        DeviceWindowRouter.openLocalNetworkSettings()
                    }
                }
            }
        } else {
            HStack(spacing: 9) {
                DeviceSpinner(size: 14, tint: HubColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Searching for devices…")
                        .font(.hubRowTitle)
                        .foregroundStyle(HubColor.textPrimary)
                    Text("Keep the phone on the pairing dialog, on the same Wi-Fi as this Mac.")
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(HubColor.card))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(HubColor.stroke, lineWidth: 1))
        }
    }

    @State private var selectedPairEndpoint: String?

    private var discoverySummary: String {
        switch service.discoveryPhase {
        case .searching: return "Searching…"
        case .found:
            return service.discoveredDevices.count == 1
                ? "1 available" : "\(service.discoveredDevices.count) available"
        case .failed: return "Search failed"
        case .idle: return ""
        }
    }

    private var pairEndpoint: String? {
        if manualAddressExpanded, !manualAddress.trimmingCharacters(in: .whitespaces).isEmpty {
            return manualAddress.trimmingCharacters(in: .whitespaces)
        }
        return selectedPairEndpoint
    }

    private var canPair: Bool {
        guard WirelessPairingCode.isValid(pairingCode), let endpoint = pairEndpoint else {
            return false
        }
        if manualAddressExpanded, !manualAddress.trimmingCharacters(in: .whitespaces).isEmpty {
            if case .success = WirelessEndpoint.parse(endpoint) { return true }
            return false
        }
        return true
    }

    private var pairButtonBusy: Bool {
        if case .working = service.pairPhase { return true }
        return false
    }

    private var manualAddressInvalid: Bool {
        guard !manualAddress.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if case .failure = WirelessEndpoint.parse(manualAddress) { return true }
        return false
    }

    private var manualAddressError: String? {
        guard manualAddressInvalid else { return nil }
        if case .failure(let error) = WirelessEndpoint.parse(manualAddress) {
            return [error.message, error.guidance].compactMap { $0 }.joined(separator: " ")
        }
        return nil
    }

    // MARK: - IP address

    private static let ipSteps = [
        "Use this for a phone already enabled for TCP/IP debugging (adb tcpip 5555).",
        "Enter the phone's IP address and port. IPv4 and bracketed IPv6 are supported.",
    ]

    private var ipValidation: Result<WirelessEndpoint, WirelessEndpoint.AddressError>? {
        let trimmed = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return WirelessEndpoint.parse(trimmed)
    }

    private var ipInputValid: Bool {
        guard let validation = ipValidation else { return false }
        if case .success = validation { return true }
        return false
    }

    private var ipContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeviceSteps(steps: Self.ipSteps, compact: true)

            HStack(spacing: 8) {
                DeviceTextField(
                    placeholder: "192.168.1.23:5555",
                    text: $ipAddress,
                    icon: "network",
                    monospaced: true,
                    invalid: ipValidation != nil && !ipInputValid,
                    onSubmit: {
                        if ipInputValid { service.connect(address: ipAddress) }
                    }
                )
                HubActionButton(
                    title: ipBusy ? "Connecting…" : "Connect",
                    icon: nil,
                    style: .primary,
                    enabled: ipInputValid && !ipBusy
                ) {
                    service.connect(address: ipAddress)
                }
            }

            if let validation = ipValidation, case .failure(let error) = validation {
                VStack(alignment: .leading, spacing: 2) {
                    Text(error.message)
                        .font(.hubRowSubtitle)
                        .foregroundStyle(HubColor.danger)
                    if let guidance = error.guidance {
                        Text(guidance)
                            .font(.hubCaption)
                            .foregroundStyle(HubColor.textTertiary)
                    }
                }
                .padding(.leading, 2)
            }

            feedback(for: service.connectPhase)

            if !wirelessDevices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    DeviceCardLabel(text: "Connected over Wi-Fi")
                    VStack(spacing: 4) {
                        ForEach(wirelessDevices) { device in
                            HStack(spacing: 10) {
                                HubIconTile(systemName: "wifi", tint: HubColor.success, size: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.hubRowTitle)
                                        .foregroundStyle(HubColor.textPrimary)
                                    Text(device.id)
                                        .font(.hubMono)
                                        .foregroundStyle(HubColor.textTertiary)
                                }
                                Spacer(minLength: 8)
                                HubActionButton(
                                    title: "Disconnect", style: .destructive
                                ) {
                                    service.disconnect(deviceID: device.id)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(HubColor.card))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(HubColor.stroke, lineWidth: 1))
                        }
                    }
                }
            }

            if wirelessDevices.isEmpty {
                HubNote(
                    text:
                        "Wireless debugging must be on. If the port changes after a reboot, check it again on the phone.",
                    icon: "info.circle")
            } else {
                HubNote(
                    text:
                        "Disconnect drops this wireless transport only. The phone stays remembered for automatic reconnects.",
                    icon: "info.circle")
            }

            Text("Equivalent to adb connect <address>")
                .font(.hubMono)
                .foregroundStyle(HubColor.textTertiary)
                .padding(.leading, 2)
        }
    }

    private var ipBusy: Bool {
        if case .working = service.connectPhase { return true }
        return false
    }

    private var wirelessDevices: [AndroidDevice] {
        store.devices.filter(\.isWirelessTransport)
    }

    // MARK: - Companion

    @ViewBuilder
    private var companionContent: some View {
        if store.isPreview {
            CompanionPanel(
                deviceName: store.selectedDevice?.name,
                state: .notInstalled,
                installPhase: .idle,
                onInstall: {},
                onCheck: {},
                onOpenProject: {})
        } else {
            CompanionLivePanel(store: store)
        }
    }

    // MARK: - Feedback

    @ViewBuilder
    private func feedback(for phase: WirelessPairingService.ActionPhase) -> some View {
        switch phase {
        case .idle:
            EmptyView()
        case .working(let message):
            DeviceFeedbackRow(kind: .working, message: message)
        case .success(let message):
            DeviceFeedbackRow(kind: .success, message: message)
        case .failure(let message):
            DeviceFeedbackRow(kind: .failure, message: message)
        }
    }
}

// MARK: - Companion panel

private struct CompanionPanel: View {
    enum InstallPhase: Equatable {
        case idle
        case installing
        case success
        case failure(String)
    }

    let deviceName: String?
    let state: CompanionClient.State
    let installPhase: InstallPhase
    let onInstall: () -> Void
    let onCheck: () -> Void
    let onOpenProject: () -> Void

    private static let projectURL = "https://github.com/aman-senpai/AndroLaunch"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HubIconTile(systemName: "checkmark.seal.fill", tint: HubColor.accent, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AndroLaunch Comp")
                        .font(.hubCardTitle)
                        .foregroundStyle(HubColor.textPrimary)
                    Text(deviceName.map { "Phone bridge for \($0)" } ?? "Phone-side bridge")
                        .font(.hubCardSubtitle)
                        .foregroundStyle(HubColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                HubPill(text: stateBadge.text, tint: stateBadge.tint)
            }

            Text(
                "Adds the phone-side channel AndroLaunch uses for calls, notifications, clipboard and storage. It is bundled with this Mac app and installed over ADB — no account, no cloud."
            )
            .font(.hubRowSubtitle)
            .foregroundStyle(HubColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            DeviceSteps(
                steps: [
                    "Connect and authorize the phone over USB or Wi-Fi.",
                    "Install AndroLaunch Comp — the APK is inside this app, nothing is downloaded.",
                    "Leave the companion running; phone features use it automatically.",
                ],
                compact: true)

            HStack(alignment: .top, spacing: 12) {
                DeviceQRCode(payload: Self.projectURL, size: 104)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Project page")
                        .font(.hubRowTitle)
                        .foregroundStyle(HubColor.textPrimary)
                    Text("Scan to open the AndroLaunch project page on your phone.")
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("There is no App Store listing; the companion APK ships inside the Mac app.")
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open on this Mac") { onOpenProject() }
                        .buttonStyle(.plain)
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.accent)
                        .padding(.top, 1)
                }
                Spacer(minLength: 0)
            }

            if let detail = stateDetail {
                DeviceFeedbackRow(kind: stateKind, message: detail)
            }

            switch installPhase {
            case .idle:
                EmptyView()
            case .installing:
                DeviceFeedbackRow(kind: .working, message: "Installing AndroLaunch Comp over ADB…")
            case .success:
                DeviceFeedbackRow(
                    kind: .success, message: "Installed. The companion is ready on the phone.")
            case .failure(let message):
                DeviceFeedbackRow(kind: .failure, message: message)
            }

            HStack(spacing: 8) {
                HubActionButton(
                    title: installTitle,
                    icon: "square.and.arrow.down",
                    style: .primary,
                    enabled: deviceName != nil && installPhase != .installing
                ) {
                    onInstall()
                }
                HubActionButton(
                    title: "Check Status",
                    icon: "arrow.clockwise",
                    style: .secondary,
                    enabled: deviceName != nil && installPhase != .installing
                ) {
                    onCheck()
                }
            }

            HubNote(
                text:
                    "Needs an authorized device. Install runs adb install -r with the APK bundled in this build; phone permissions stay opt-in in the companion.",
                icon: "info.circle")
        }
    }

    private var installTitle: String {
        switch state {
        case .notInstalled: return "Install AndroLaunch Comp"
        case .ready, .stopped: return "Reinstall Companion"
        default: return "Install AndroLaunch Comp"
        }
    }

    private var stateBadge: (text: String, tint: Color) {
        switch state {
        case .unknown:
            return ("Not checked", HubColor.textSecondary)
        case .notInstalled:
            return ("Not installed", HubColor.warning)
        case .stopped:
            return ("Not running", HubColor.warning)
        case .ready(let version):
            return ("Ready · \(version)", HubColor.success)
        case .failed:
            return ("Unavailable", HubColor.danger)
        }
    }

    private var stateDetail: String? {
        switch state {
        case .unknown:
            return deviceName == nil
                ? "Connect a device first, then check its companion status."
                : "Check status to see whether AndroLaunch Comp is installed and running."
        case .notInstalled:
            return "AndroLaunch Comp isn't installed on this phone yet."
        case .stopped:
            return "Installed, but the foreground service isn't running. Check status to start it."
        case .ready:
            return nil
        case .failed(let message):
            return message
        }
    }

    private var stateKind: DeviceFeedbackRow.Kind {
        switch state {
        case .ready: return .success
        case .unknown: return .info
        case .notInstalled, .stopped: return .info
        case .failed: return .failure
        }
    }
}

/// Live companion state; only constructed for a non-preview Hub, so the shared
/// service graph stays untouched while rendering snapshots.
private struct CompanionLivePanel: View {
    @ObservedObject var store: HubStore
    @ObservedObject private var companion = CompanionClient.shared
    @State private var installPhase: CompanionPanel.InstallPhase = .idle

    private var device: AndroidDevice? { store.selectedDevice }

    private var state: CompanionClient.State {
        guard let device else { return .unknown }
        return companion.state(for: device.id)
    }

    var body: some View {
        CompanionPanel(
            deviceName: device?.name,
            state: state,
            installPhase: installPhase,
            onInstall: install,
            onCheck: checkStatus,
            onOpenProject: openProject
        )
        .onAppear {
            if let device, case .unknown = companion.state(for: device.id) {
                companion.prepare(deviceID: device.id)
            }
        }
    }

    private func install() {
        guard let device else { return }
        installPhase = .installing
        companion.install(deviceID: device.id) { result in
            switch result {
            case .success:
                installPhase = .success
                store.refresh()
            case .failure(let error):
                installPhase = .failure(error.localizedDescription)
            }
        }
    }

    private func checkStatus() {
        guard let device else { return }
        installPhase = .idle
        companion.invalidate(device.id)
        companion.prepare(deviceID: device.id)
    }

    private func openProject() {
        guard let url = URL(string: "https://github.com/aman-senpai/AndroLaunch") else { return }
        NSWorkspace.shared.open(url)
    }
}
