//
//  DeviceComponents.swift
//  AndroLaunch
//
//  Small building blocks shared by the Devices surface and the four
//  wireless tabs. Everything composes from the Hub design system; no bespoke
//  colours, fonts or shadows live here.
//

import AppKit
import CoreImage
import SwiftUI

// MARK: - Collapsible card

/// A card whose whole header row expands its content. The header keeps the
/// reference hierarchy: 34 pt tinted icon tile, 15 pt title, 11.5 pt status
/// subtitle, one trailing status signal, rotating chevron.
struct DeviceCollapsibleCard<Content: View>: View {
    let icon: String
    var tint: Color = HubColor.accent
    let title: String
    let subtitle: String
    var badge: String? = nil
    var badgeTint: Color = HubColor.success
    var showsStatusDot: Bool = false
    @Binding var expanded: Bool
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HubCard(padding: 0) {
            VStack(spacing: 0) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        expanded.toggle()
                    }
                } label: {
                    HStack(spacing: 11) {
                        HubIconTile(systemName: icon, tint: tint, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.hubCardTitle)
                                .foregroundStyle(HubColor.textPrimary)
                            Text(subtitle)
                                .font(.hubCardSubtitle)
                                .foregroundStyle(HubColor.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 8)
                        if let badge {
                            HubPill(text: badge, tint: badgeTint)
                        } else if showsStatusDot {
                            HubStatusDot(color: HubColor.success, size: 6)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(HubColor.textTertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityValue(expanded ? "Expanded. \(subtitle)" : "Collapsed. \(subtitle)")
                .accessibilityHint(expanded ? "Collapse" : "Expand")

                if expanded {
                    DeviceCardDivider()
                    content()
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 14)
                        .transition(.opacity)
                }
            }
        }
    }
}

struct DeviceCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(HubColor.stroke)
            .frame(height: 1)
    }
}

// MARK: - Labels & steps

struct DeviceCardLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.hubSectionLabel)
            .tracking(0.8)
            .foregroundStyle(HubColor.textTertiary)
            .padding(.leading, 1)
    }
}

/// Numbered instructions. Used by the USB empty state and every Wi-Fi tab so
/// the four connection paths read with one rhythm.
struct DeviceSteps: View {
    let steps: [String]
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 9) {
                    Text("\(index + 1)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(HubColor.textSecondary)
                        .frame(width: 17, height: 17)
                        .background(Circle().fill(HubColor.cardElevated))
                        .overlay(Circle().strokeBorder(HubColor.stroke, lineWidth: 1))
                    Text(step)
                        .font(.hubRowSubtitle)
                        .foregroundStyle(HubColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Fields

/// A SwiftUI-drawn spinner. `ProgressView` is AppKit-backed and renders as a
/// placeholder glyph inside `ImageRenderer`, so the snapshot renderer needs a
/// pure-SwiftUI arc that stays faithful.
struct DeviceSpinner: View {
    var size: CGFloat = 12
    var tint: Color = HubColor.accent
    var lineWidth: CGFloat = 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false

    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.82)
            .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .animation(
                reduceMotion ? nil : .linear(duration: 0.85).repeatForever(autoreverses: false),
                value: rotating)
            .onAppear { rotating = true }
            .accessibilityHidden(true)
    }
}

struct DeviceTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var monospaced: Bool = false
    var invalid: Bool = false
    var onSubmit: (() -> Void)? = nil

    @Environment(\.hubSnapshotMode) private var snapshotMode

    var body: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HubColor.textTertiary)
            }
            // ImageRenderer cannot draw AppKit text fields; snapshot mode shows
            // the exact same layout with static text so design review is faithful.
            if snapshotMode {
                Text(text.isEmpty ? placeholder : text)
                    .font(monospaced ? .hubMono : .hubBody)
                    .foregroundStyle(text.isEmpty ? HubColor.textTertiary : HubColor.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(monospaced ? .hubMono : .hubBody)
                    .foregroundStyle(HubColor.textPrimary)
                    .onSubmit { onSubmit?() }
                    .accessibilityLabel(placeholder)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(HubColor.cardElevated))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    invalid ? HubColor.danger.opacity(0.65) : HubColor.stroke,
                    lineWidth: 1))
    }
}

// MARK: - Device rows

struct DeviceLinkRow: View {
    let device: AndroidDevice?
    let entry: ADBLinkEntry?
    var isSelected: Bool = false
    var action: (() -> Void)? = nil

    private var name: String {
        if let device, !device.name.isEmpty { return device.name }
        if let entry { return entry.displayName }
        return "Android device"
    }

    private var state: ADBLinkEntry.State {
        if let entry { return entry.state }
        return device?.isConnected == true ? .connected : .offline
    }

    private var transport: TransportKind {
        if let device { return device.transportKind }
        if let entry { return TransportKind.classify(entry.id) }
        return .usb
    }

    private var transportID: String? { device?.id ?? entry?.id }

    private var isEmulator: Bool { transportID?.hasPrefix("emulator-") == true }

    private var transportLabel: String { isEmulator ? "Emulator" : transport.displayName }

    private var transportSymbol: String { isEmulator ? "display" : transport.symbolName }

    private var detail: String {
        var parts: [String] = []
        if let model = device?.model, !model.isEmpty,
            model.replacingOccurrences(of: "_", with: " ") != name
        {
            parts.append(model.replacingOccurrences(of: "_", with: " "))
        }
        if let version = device?.androidVersion, !version.isEmpty {
            parts.append("Android \(version)")
        }
        if parts.isEmpty, let entry {
            parts.append(entry.id)
        }
        return parts.joined(separator: " · ")
    }

    private var stateHint: String? {
        switch state {
        case .unauthorized:
            return "Unlock the phone and tap Allow for USB debugging."
        case .noPermissions:
            return "Check USB permissions on this Mac, then reconnect."
        case .offline:
            return "Reconnect the cable or Wireless debugging, then refresh."
        case .bootloader, .recovery, .sideload:
            return "Restart the device into normal Android mode."
        case .authorizing, .connecting:
            return "Waiting for the phone to finish authorizing."
        default:
            return nil
        }
    }

    private var stateTint: Color {
        switch state {
        case .connected: return HubColor.success
        case .unauthorized, .noPermissions: return HubColor.warning
        case .offline: return HubColor.textSecondary
        case .bootloader, .recovery, .sideload, .unknown: return HubColor.warning
        case .authorizing, .connecting: return HubColor.accent
        case .host: return HubColor.textSecondary
        }
    }

    var body: some View {
        HubRowButton(action: action) {
            HStack(spacing: 10) {
                HubIconTile(
                    systemName: transportSymbol,
                    tint: state == .connected ? stateTint : HubColor.textTertiary,
                    size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.hubRowTitle)
                        .foregroundStyle(HubColor.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        if !detail.isEmpty {
                            Text(detail)
                                .font(.hubRowSubtitle)
                                .foregroundStyle(HubColor.textSecondary)
                                .lineLimit(1)
                        }
                        if let battery = device?.batteryLevel {
                            BatteryLabel(level: battery, charging: device?.isCharging == true)
                        }
                    }
                    if let stateHint {
                        Text(stateHint)
                            .font(.hubCaption)
                            .foregroundStyle(stateTint.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    HubPill(text: state.displayName, tint: stateTint)
                    Text(transportLabel)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(HubColor.textTertiary)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: HubMetric.rowRadius, style: .continuous)
                .fill(isSelected ? HubColor.accentSoft : Color.clear))
        .overlay(
            RoundedRectangle(cornerRadius: HubMetric.rowRadius, style: .continuous)
                .strokeBorder(isSelected ? HubColor.accent.opacity(0.24) : Color.clear, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct BatteryLabel: View {
    let level: Int
    let charging: Bool

    private var symbol: String {
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    private var tint: Color {
        level <= 20 ? HubColor.danger : HubColor.textSecondary
    }

    var body: some View {
        HStack(spacing: 2.5) {
            Image(systemName: charging ? "bolt.fill" : symbol)
                .font(.system(size: 9.5, weight: .medium))
            Text("\(level)%")
                .font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(tint)
        .accessibilityLabel(charging ? "Battery \(level) percent, charging" : "Battery \(level) percent")
    }
}

// MARK: - Feedback

struct DeviceFeedbackRow: View {
    enum Kind {
        case working
        case success
        case failure
        case info
    }

    let kind: Kind
    let message: String

    private var tint: Color {
        switch kind {
        case .working: return HubColor.accent
        case .success: return HubColor.success
        case .failure: return HubColor.danger
        case .info: return HubColor.textSecondary
        }
    }

    private var icon: String {
        switch kind {
        case .working: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if kind == .working {
                DeviceSpinner(size: 11, tint: tint)
                    .padding(.top, 1)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.top, 0.5)
            }
            Text(message)
                .font(.hubRowSubtitle)
                .foregroundStyle(kind == .info ? HubColor.textSecondary : tint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(kind == .info ? 0.06 : 0.1)))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct DeviceStatusLine: View {
    let text: String
    var tint: Color = HubColor.success
    var busy: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if busy {
                DeviceSpinner(size: 9, tint: HubColor.textTertiary, lineWidth: 1.5)
            } else {
                HubStatusDot(color: tint, size: 6)
            }
            Text(text)
                .font(.hubCaption)
                .foregroundStyle(HubColor.textTertiary)
        }
    }
}

// MARK: - QR code

struct DeviceQRCode: View {
    let payload: String
    var size: CGFloat = 172

    private let image: NSImage?

    init(payload: String, size: CGFloat = 172) {
        self.payload = payload
        self.size = size
        self.image = QRCodeGenerator.image(for: payload)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let image {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: size, height: size)
                    .accessibilityLabel("Wireless pairing QR code")
                    .accessibilityHint("Scan this from the phone's Wireless debugging screen")
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.06))
                    .frame(width: size, height: size)
                    .overlay(
                        Text("QR code unavailable")
                            .font(.hubCaption)
                            .foregroundStyle(.black.opacity(0.55)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.07), lineWidth: 1))
    }
}

enum QRCodeGenerator {
    static func image(for payload: String) -> NSImage? {
        guard !payload.isEmpty, let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale: CGFloat = 12
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}

// MARK: - On this Mac

struct EmulatorInventory: Equatable {
    let avdNames: [String]

    var count: Int { avdNames.count }

    var summary: String {
        switch count {
        case 0: return "No virtual devices yet"
        case 1: return "1 virtual device"
        default: return "\(count) virtual devices"
        }
    }

    static func load() -> EmulatorInventory {
        let configured = UserDefaults.standard.string(forKey: "android_avd_path")
        let path =
            (configured?.isEmpty == false ? configured! : NSHomeDirectory() + "/.android/avd")
        let names =
            (try? FileManager.default.contentsOfDirectory(atPath: path))?
            .filter { $0.hasSuffix(".ini") && !$0.hasPrefix(".") }
            .map { String($0.dropLast(4)) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending } ?? []
        return EmulatorInventory(avdNames: names)
    }
}

/// Opens the existing Emulator Manager window from the Hub. The menu bar owns
/// its own window instance; this route intentionally reuses the same view model
/// so AVD state stays in one place.
@MainActor
enum DeviceWindowRouter {
    private static var emulatorWindow: NSWindow?

    static func openEmulatorManager() {
        if let window = emulatorWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let container = DependencyContainer.shared
        let root = EmulatorManagerView(viewModel: container.emulatorManagerViewModel)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Emulator Manager"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 980, height: 720))
        window.minSize = NSSize(width: 760, height: 520)
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        emulatorWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func openLocalNetworkSettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }
}
