//
//  TrackpadPanelView.swift
//  AndroLaunch
//
//  The floating trackpad surface. A pure renderer of `TrackpadPanelState` plus a
//  small AppKit gesture view: two-finger scroll is forwarded as deltas and a
//  click-drag is classified into back / recents / notifications.
//
//  Owned by platform-extras. The window shell lives in
//  Presentation/Overlays/TrackpadPanel.swift.
//

import AppKit
import SwiftUI

// MARK: - Model

/// Observable wrapper so the panel keeps the same SwiftUI view identity while the
/// controller pushes new state (a re-created root view would interrupt a drag).
final class TrackpadPanelModel: ObservableObject {
    @Published var state: TrackpadPanelState
    let actions: TrackpadPanelActions

    init(state: TrackpadPanelState, actions: TrackpadPanelActions) {
        self.state = state
        self.actions = actions
    }
}

// MARK: - View

struct TrackpadPanelView: View {
    @ObservedObject var model: TrackpadPanelModel

    /// `ImageRenderer` cannot draw an `NSViewRepresentable`; snapshots show the
    /// hint overlay instead of the yellow unsupported-view placeholder.
    @Environment(\.hubSnapshotMode) private var snapshotMode

    private var state: TrackpadPanelState { model.state }

    var body: some View {
        VStack(spacing: 9) {
            header
            gestureSurface
            buttons
            footer
        }
        .padding(12)
        .frame(width: 320)
        .background(HubColor.background)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            HubIconTile(
                systemName: "hand.draw.fill",
                tint: state.isAvailable ? HubColor.accent : HubColor.textTertiary,
                size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text("Trackpad")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HubColor.textPrimary)
                Text(state.deviceLine)
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let screen = state.screenLabel {
                HubPill(text: screen, tint: HubColor.textTertiary)
            }
            Button(action: model.actions.close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(HubColor.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close trackpad panel")
            .accessibilityLabel("Close trackpad panel")
        }
    }

    // MARK: Gesture surface

    private var gestureSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(HubColor.card)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(HubColor.stroke, lineWidth: 1)

            if state.isAvailable {
                VStack(spacing: 4) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(HubColor.textTertiary)
                    Text(state.surfaceHint)
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 14)

                if !snapshotMode {
                    TrackpadGestureSurface(
                        onSwipe: model.actions.gesture,
                        onScroll: model.actions.scroll)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(HubColor.textTertiary)
                    Text("No device connected")
                        .font(.hubRowTitle)
                        .foregroundStyle(HubColor.textSecondary)
                    HubActionButton(title: "Open Dashboard", icon: "macwindow", style: .quiet) {
                        model.actions.openHub()
                    }
                }
            }

            if let lastAction = state.lastAction {
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        Text(lastAction)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(HubColor.textPrimary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(HubColor.cardElevated))
                            .overlay(
                                Capsule().strokeBorder(HubColor.strokeStrong, lineWidth: 1))
                        Spacer(minLength: 0)
                    }
                }
                .padding(.bottom, 7)
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            if state.isSending {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 100)
        .animation(.easeOut(duration: 0.14), value: state.lastAction)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trackpad gesture area")
        .accessibilityHint("Click and drag to send a gesture, or scroll with two fingers.")
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack(spacing: 6) {
            ForEach(TrackpadGesture.buttonGestures) { gesture in
                TrackpadFallbackButton(
                    gesture: gesture,
                    enabled: state.isAvailable,
                    action: { model.actions.gesture(gesture) })
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Sensitivity")
                .font(.hubCaption)
                .foregroundStyle(HubColor.textSecondary)
            Slider(
                value: Binding(
                    get: { state.sensitivity },
                    set: { model.actions.setSensitivity($0) }),
                in: 0.1...1.0
            )
            .controlSize(.small)
            .tint(HubColor.accent)
            .frame(width: 86)
            .accessibilityLabel("Gesture sensitivity")
            .accessibilityValue("\(Int(state.sensitivity * 100)) percent")

            Spacer(minLength: 4)

            Text("Natural")
                .font(.hubCaption)
                .foregroundStyle(HubColor.textSecondary)
            if snapshotMode {
                SnapshotSwitch(isOn: state.naturalScrolling)
            } else {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { state.naturalScrolling },
                        set: { model.actions.setNaturalScrolling($0) })
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(HubColor.accent)
                .accessibilityLabel("Natural scrolling")
            }
        }
    }
}

// MARK: - Fallback button

private struct TrackpadFallbackButton: View {
    let gesture: TrackpadGesture
    let enabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: gesture.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(gesture.title)
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(enabled ? HubColor.textPrimary : HubColor.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering && enabled ? HubColor.cardHover : HubColor.cardElevated))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(HubColor.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.6)
        .onHover { hovering = $0 }
        .help(gesture.title)
        .accessibilityLabel(gesture.title)
    }
}

// MARK: - Snapshot switch

/// `ImageRenderer` renders AppKit-backed switches as unsupported placeholders.
/// Snapshots draw the same shape statically; the real app always uses `Toggle`.
private struct SnapshotSwitch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? HubColor.accent : HubColor.controlTrack)
            .frame(width: 30, height: 18)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .padding(2)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Gesture capture

/// AppKit view that captures the two input styles the panel needs:
/// `scrollWheel` (two-finger scroll) and a click-drag that is classified into an
/// Android navigation gesture.
struct TrackpadGestureSurface: NSViewRepresentable {
    var onSwipe: (TrackpadGesture) -> Void
    var onScroll: (Double) -> Void

    func makeNSView(context: Context) -> TrackpadGestureNSView {
        let view = TrackpadGestureNSView()
        view.onSwipe = onSwipe
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: TrackpadGestureNSView, context: Context) {
        nsView.onSwipe = onSwipe
        nsView.onScroll = onScroll
    }
}

final class TrackpadGestureNSView: NSView {
    var onSwipe: ((TrackpadGesture) -> Void)?
    var onScroll: ((Double) -> Void)?

    private var dragStart: CGPoint?
    private let classifier = TrackpadGestureClassifier()

    /// Match SwiftUI/phone coordinates: y grows downwards.
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart else { return }
        dragStart = nil
        let end = convert(event.locationInWindow, from: nil)
        guard
            let gesture = classifier.classify(
                start: TrackpadPoint(x: start.x, y: start.y),
                end: TrackpadPoint(x: end.x, y: end.y),
                size: TrackpadSize(width: bounds.width, height: bounds.height))
        else { return }
        onSwipe?(gesture)
    }

    override func scrollWheel(with event: NSEvent) {
        // Precise deltas arrive in points; classic wheel events are much coarser.
        let delta =
            event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY
            : event.scrollingDeltaY * 8
        guard delta.isFinite, delta != 0 else { return }
        onScroll?(Double(delta))
    }
}

// MARK: - Preview

#if DEBUG
    /// Headless render used by the platform-extras snapshot harness.
    enum TrackpadPanelSnapshot {
        @MainActor
        static func render(to directory: URL) {
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)

            var connected = TrackpadPanelState(
                deviceID: "R58M12ABCDE",
                deviceName: "Pixel 9 Pro",
                isDeviceConnected: true,
                screen: TrackpadScreenSize(width: 1080, height: 2400))
            connected.lastAction = "Back sent"
            render(state: connected, name: "trackpad-panel.png", in: directory)

            var disconnected = TrackpadPanelState()
            disconnected.lastAction = nil
            render(state: disconnected, name: "trackpad-panel-empty.png", in: directory)
        }

        @MainActor
        private static func render(
            state: TrackpadPanelState, name: String, in directory: URL
        ) {
            let model = TrackpadPanelModel(state: state, actions: TrackpadPanelActions())
            let renderer = ImageRenderer(
                content: TrackpadPanelView(model: model)
                    .environment(\.colorScheme, .dark)
                    .environment(\.hubSnapshotMode, true)
            )
            renderer.scale = 2
            guard let cgImage = renderer.cgImage else { return }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: directory.appendingPathComponent(name))
        }
    }
#endif
