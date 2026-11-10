//
//  MirrorControlsPanel.swift
//  AndroLaunch
//
//  The floating Mirror Controls panel. One SwiftUI view (`MirrorControlsView`)
//  draws the whole surface and is snapshot-safe (custom switches, no AppKit-
//  backed controls), so `HubSnapshotRenderer` can rasterise it. The AppKit shell
//  below is a non-activating NSPanel positioned next to the scrcpy mirror window
//  when it can be found, otherwise in the top-right of the screen.
//

import AppKit
import Combine
import SwiftUI

// MARK: - View

struct MirrorControlsView: View {
    @ObservedObject private var controller: MirrorControlsController
    private let preview: MirrorControlsPreview?

    /// Live panel content.
    init(controller: MirrorControlsController = .shared) {
        self.controller = controller
        self.preview = nil
    }

    /// Deterministic state for SwiftUI previews and the snapshot renderer.
    /// Exact wiring for the Lead:
    ///     MirrorControlsView(preview: MirrorControlsPreview.state)
    init(preview: MirrorControlsPreview) {
        self.controller = .shared
        self.preview = preview
    }

    // MARK: Derived state

    private var deviceName: String {
        preview?.deviceName ?? controller.deviceName
    }

    private var isConnected: Bool {
        preview?.isConnected ?? controller.isDeviceConnected
    }

    private var options: MirrorOptions {
        preview?.options ?? controller.options
    }

    private var isMirroring: Bool {
        preview?.isMirroring ?? controller.isMirroring
    }

    private var isApplying: Bool {
        preview == nil ? controller.isApplying : false
    }

    private var statusMessage: String? {
        preview?.statusMessage ?? controller.statusMessage
    }

    private var lastError: String? {
        preview == nil ? controller.lastError : nil
    }

    private var lastCapturePath: String? {
        preview?.lastCapturePath ?? controller.lastCapturePath
    }

    private var isRecording: Bool {
        preview?.recordingElapsedSeconds != nil || controller.recordingStartedAt != nil
    }

    private var isSavingRecording: Bool {
        preview == nil && controller.isSavingRecording
    }

    private var lastCaptureFileName: String? {
        guard let lastCapturePath else { return nil }
        return (lastCapturePath as NSString).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            optionsGrid
            captureCard
            keyboardCard
            navigationCard
            footer
        }
        .padding(12)
        .frame(width: 300)
        .background(
            HubColor.background
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(HubColor.strokeStrong, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mirror controls for \(deviceName)")
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 9) {
            HubIconTile(systemName: "iphone.gen3", tint: HubColor.accent, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mirror Controls")
                    .font(.hubCardTitle)
                    .foregroundStyle(HubColor.textPrimary)
                HStack(spacing: 5) {
                    Text(deviceName)
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textSecondary)
                        .lineLimit(1)
                    HubPill(
                        text: isMirroring ? "Mirroring" : "Not mirroring",
                        tint: isMirroring ? HubColor.success : HubColor.warning)
                    if !isConnected {
                        HubPill(text: "Offline", tint: HubColor.danger)
                    }
                }
            }
            Spacer(minLength: 4)
            iconButton(
                icon: "arrow.clockwise",
                label: isMirroring ? "Restart mirror" : "Start mirror"
            ) {
                controller.applyMirrorOptions()
            }
            iconButton(icon: "xmark", label: "Close mirror controls") {
                controller.hide()
            }
        }
    }

    private func performLive(_ action: () -> Void) {
        guard preview == nil else { return }
        action()
    }

    private func iconButton(
        icon: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button {
            performLive(action)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HubColor.textSecondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(HubColor.cardElevated))
                .overlay(Circle().strokeBorder(HubColor.stroke, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    // MARK: Options grid

    private var optionsGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                toggleChip(
                    icon: "speaker.wave.2.fill", title: "Audio",
                    isOn: options.audioForwarding,
                    accessibility: "Audio forwarding"
                ) { setAudio($0) }
                toggleChip(
                    icon: "pin.fill", title: "Pin",
                    isOn: options.alwaysOnTop,
                    accessibility: "Pin window always on top"
                ) { setAlwaysOnTop($0) }
            }
            HStack(spacing: 6) {
                toggleChip(
                    icon: "moon.fill", title: "Screen Off",
                    isOn: options.screenOff,
                    accessibility: "Use with screen off"
                ) { setScreenOff($0) }
                toggleChip(
                    icon: "doc.on.clipboard.fill", title: "Clipboard",
                    isOn: options.clipboard,
                    accessibility: "Clipboard sharing"
                ) { setClipboard($0) }
            }
        }
    }

    private func toggleChip(
        icon: String, title: String, isOn: Bool, accessibility: String,
        action: @escaping (Bool) -> Void
    ) -> some View {
        Button {
            action(!isOn)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isOn ? HubColor.accent : HubColor.textTertiary)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOn ? HubColor.textPrimary : HubColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 1)
                switchDot(isOn: isOn)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isOn ? HubColor.accentSoft : HubColor.card))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isOn ? HubColor.accent.opacity(0.26) : HubColor.stroke,
                        lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func switchDot(isOn: Bool) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? HubColor.accent : HubColor.strokeStrong)
                .frame(width: 24, height: 14)
            Circle()
                .fill(Color.white)
                .frame(width: 10, height: 10)
                .padding(2)
        }
        .frame(width: 24, height: 14)
    }

    // MARK: Capture

    private var captureCard: some View {
        VStack(spacing: 0) {
            actionRow(
                icon: "camera.fill",
                title: "Screenshot",
                subtitle: lastCaptureFileName ?? "Save to the Desktop and copy to the clipboard",
                tint: HubColor.accent,
                trailing: AnyView(
                    HubPill(text: "Save", tint: HubColor.accent)
                )
            ) {
                performLive { controller.screenshot() }
            }
            divider
            recordRow
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(HubColor.card))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(HubColor.stroke, lineWidth: 1))
    }

    private var recordRow: some View {
        Button {
            performLive { controller.startOrStopRecording() }
        } label: {
            HStack(spacing: 9) {
                HubIconTile(
                    systemName: isSavingRecording
                        ? "arrow.down.circle.fill"
                        : (isRecording ? "stop.circle.fill" : "record.circle"),
                    tint: isSavingRecording
                        ? HubColor.accent : (isRecording ? HubColor.danger : HubColor.accent),
                    size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        isSavingRecording
                            ? "Saving Recording…"
                            : (isRecording ? "Stop Recording" : "Record Screen")
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HubColor.textPrimary)
                    Text(
                        isSavingRecording
                            ? "Pulling the MP4 to ~/Movies"
                            : (isRecording ? "Auto-stops at 3 min" : "Up to 3 min · ~/Movies")
                    )
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textSecondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                if isSavingRecording {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(HubColor.accent)
                } else if isRecording {
                    recordingBadge
                } else {
                    HubPill(text: "Start", tint: HubColor.textSecondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop screen recording" : "Start screen recording")
    }

    private var recordingBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(HubColor.danger)
                .frame(width: 6, height: 6)
            if let preview, let seconds = preview.recordingElapsedSeconds {
                Text("REC \(Self.elapsedText(seconds))")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(HubColor.danger)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("REC \(Self.elapsedText(Self.elapsedSeconds(since: controller.recordingStartedAt, now: context.date)))")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(HubColor.danger)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(HubColor.dangerSoft))
        .accessibilityLabel("Recording")
    }

    private static func elapsedSeconds(since start: Date?, now: Date) -> Int {
        guard let start else { return 0 }
        return max(0, Int(now.timeIntervalSince(start)))
    }

    private static func elapsedText(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }

    private var divider: some View {
        Rectangle()
            .fill(HubColor.stroke)
            .frame(height: 1)
            .padding(.leading, 45)
    }

    private func actionRow(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color,
        trailing: AnyView,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                HubIconTile(systemName: icon, tint: tint, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HubColor.textPrimary)
                    Text(subtitle)
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                trailing
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    // MARK: Keyboard & frame

    private var keyboardCard: some View {
        VStack(spacing: 0) {
            Button {
                setMacKeyboard(!options.macKeyboard)
            } label: {
                HStack(spacing: 9) {
                    HubIconTile(systemName: "keyboard.fill", tint: HubColor.accent, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Use Mac Keyboard")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(HubColor.textPrimary)
                        Text(
                            options.macKeyboard
                                ? "Mac keys forwarded to Android"
                                : "Phone's on-screen keyboard only"
                        )
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textSecondary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    switchDot(isOn: options.macKeyboard)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use Mac keyboard")
            .accessibilityValue(options.macKeyboard ? "On" : "Off")

            divider

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    HubIconTile(
                        systemName: "rectangle.on.rectangle", tint: HubColor.accent, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Window Frame")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(HubColor.textPrimary)
                        Text("Borderless window or a normal frame")
                            .font(.hubCaption)
                            .foregroundStyle(HubColor.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                HubSegmentedTabs(
                    items: MirrorFrameChoice.allCases.map {
                        HubSegmentedTabs<MirrorFrameChoice>.Item(
                            value: $0, title: $0.title, icon: nil)
                    },
                    selection: Binding(
                        get: { options.frameChoice },
                        set: { setFrameChoice($0) }),
                    compact: true
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(HubColor.card))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(HubColor.stroke, lineWidth: 1))
    }

    // MARK: Navigation

    private var navigationCard: some View {
        HStack(spacing: 6) {
            ForEach(MirrorNavKey.allCases) { key in
                navigationButton(key)
            }
        }
    }

    private func navigationButton(_ key: MirrorNavKey) -> some View {
        Button {
            performLive { controller.press(key) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: key.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(key.title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(HubColor.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(HubColor.cardElevated))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(HubColor.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(key.title) button")
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let lastError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(HubColor.danger)
                        .padding(.top, 1)
                    Text(lastError)
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }
            } else if let statusMessage {
                HStack(alignment: .top, spacing: 6) {
                    if isApplying {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(HubColor.accent)
                    } else {
                        Image(systemName: isMirroring ? "checkmark.circle" : "info.circle")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(
                                isMirroring ? HubColor.success : HubColor.textTertiary)
                            .padding(.top, 1)
                    }
                    Text(statusMessage)
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }
            }
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 8.5, weight: .semibold))
                Text("Option changes restart the mirror. Pin is scrcpy's always-on-top.")
                    .font(.system(size: 9.5))
                    .lineLimit(2)
            }
            .foregroundStyle(HubColor.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions (live only; preview is read-only)

    private func setAudio(_ value: Bool) {
        guard preview == nil else { return }
        controller.setAudioForwarding(value)
    }

    private func setAlwaysOnTop(_ value: Bool) {
        guard preview == nil else { return }
        controller.setAlwaysOnTop(value)
    }

    private func setScreenOff(_ value: Bool) {
        guard preview == nil else { return }
        controller.setScreenOff(value)
    }

    private func setClipboard(_ value: Bool) {
        guard preview == nil else { return }
        controller.setClipboard(value)
    }

    private func setMacKeyboard(_ value: Bool) {
        guard preview == nil else { return }
        controller.setMacKeyboard(value)
    }

    private func setFrameChoice(_ choice: MirrorFrameChoice) {
        guard preview == nil else { return }
        controller.setFrameChoice(choice)
    }
}

// MARK: - Panel window

final class MirrorControlsPanelWindowController {
    private let panel: NSPanel
    private weak var controller: MirrorControlsController?
    private var hosting: NSHostingView<MirrorControlsView>?
    private var cancellable: AnyCancellable?

    init(controller: MirrorControlsController) {
        self.controller = controller
        let initialSize = NSSize(width: 300, height: 500)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.title = "Mirror Controls"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        self.panel = panel

        let hosting = NSHostingView(rootView: MirrorControlsView(controller: controller))
        hosting.frame = NSRect(origin: .zero, size: initialSize)
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        self.hosting = hosting
        // Fit the card to its content; a fixed height used to clip the footer on
        // larger accessibility sizes or when a multi-line error appears.
        fitToContent()
        // Live state changes (status text, errors, recording rows) can change the
        // height while the panel is visible.
        cancellable = controller.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.fitToContent() }
            }
    }

    private func fitToContent() {
        guard let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        guard fitting.height > 40 else { return }
        let target = NSSize(
            width: max(300, fitting.width), height: max(420, fitting.height))
        guard abs(panel.frame.width - target.width) > 1
            || abs(panel.frame.height - target.height) > 1
        else { return }
        panel.setContentSize(target)
    }

    func show() {
        fitToContent()
        position()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    // MARK: Placement

    private func position() {
        let size = panel.frame.size
        if let mirrorFrame = MirrorWindowLocator.frame(
            deviceID: controller?.deviceID,
            deviceName: controller?.deviceName
        ) {
            let screen =
                NSScreen.screens.first { $0.frame.intersects(mirrorFrame) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? .zero
            var origin = NSPoint(
                x: mirrorFrame.maxX + 12,
                y: mirrorFrame.maxY - size.height)
            if origin.x + size.width > visible.maxX {
                origin.x = mirrorFrame.minX - size.width - 12
            }
            if origin.y < visible.minY { origin.y = visible.minY + 12 }
            if origin.y + size.height > visible.maxY {
                origin.y = visible.maxY - size.height - 12
            }
            origin.x = min(max(origin.x, visible.minX + 12), visible.maxX - size.width - 12)
            panel.setFrameOrigin(origin)
            return
        }
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(
                x: visible.maxX - size.width - 20,
                y: visible.maxY - size.height - 20))
    }
}

// MARK: - Locating the scrcpy window

enum MirrorWindowLocator {
    /// Best-effort frame of the scrcpy window for a device, in AppKit screen
    /// coordinates. macOS may hide other apps' window titles without Screen
    /// Recording permission, so a lone scrcpy window is accepted even when the
    /// title cannot be read; when titles are unavailable and several scrcpy
    /// windows exist, the largest one is used.
    static func frame(deviceID: String?, deviceName: String?) -> NSRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }

        var matching: [NSRect] = []
        var allScrcpyWindows: [NSRect] = []
        for window in windowList {
            let owner = (window[kCGWindowOwnerName as String] as? String)?.lowercased() ?? ""
            guard owner.contains("scrcpy") else { continue }
            guard let boundsDictionary = window[kCGWindowBounds as String] as? [String: Any],
                let cgRect = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else { continue }
            let rect = appKitRect(from: cgRect)
            guard rect.width > 80, rect.height > 80 else { continue }
            allScrcpyWindows.append(rect)

            let title = (window[kCGWindowName as String] as? String) ?? ""
            guard !title.isEmpty else { continue }
            let matchesID = deviceID.map { title.contains($0) } ?? false
            let matchesName = deviceName.map { !$0.isEmpty && title.contains($0) } ?? false
            if matchesID || matchesName {
                matching.append(rect)
            }
        }

        if let best = matching.max(by: { $0.width * $0.height < $1.width * $1.height }) {
            return best
        }
        if allScrcpyWindows.count == 1 {
            return allScrcpyWindows[0]
        }
        return allScrcpyWindows.max { $0.width * $0.height < $1.width * $1.height }
    }

    /// CGWindow bounds use a top-left origin on the main display; AppKit uses a
    /// bottom-left origin.
    private static func appKitRect(from cgRect: CGRect) -> NSRect {
        guard let mainScreen = NSScreen.screens.first else {
            return NSRect(
                x: cgRect.origin.x, y: cgRect.origin.y,
                width: cgRect.width, height: cgRect.height)
        }
        return NSRect(
            x: cgRect.origin.x,
            y: mainScreen.frame.maxY - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height)
    }
}
