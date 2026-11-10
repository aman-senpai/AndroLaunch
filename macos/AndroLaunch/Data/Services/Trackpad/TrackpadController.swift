//
//  TrackpadController.swift
//  AndroLaunch
//
//  Android gestures from the Mac trackpad: back, home, recents, notifications
//  and scrolling. Owned by the platform-extras feature.
//
//  The controller owns the floating panel, resolves the target device from the
//  Hub, and forwards real input through ADB (`input keyevent`, `input swipe`,
//  `cmd statusbar expand-notifications`). Gesture math and persistence live in
//  `TrackpadModels.swift` so they can be tested without a device.
//

import AppKit
import Combine
import Foundation

final class TrackpadController: ObservableObject {
    static let shared = TrackpadController()

    // MARK: - Published state

    @Published private(set) var isPresented = false
    @Published private(set) var deviceID: String?
    @Published private(set) var deviceName: String?
    @Published private(set) var isDeviceConnected = false
    /// 0.1…1.0. Higher values move further per gesture and need less travel.
    @Published var sensitivity: Double {
        didSet {
            guard oldValue != sensitivity else { return }
            TrackpadPreferences(sensitivity: sensitivity, naturalScrolling: naturalScrolling)
                .save()
            syncModel()
        }
    }
    @Published var naturalScrolling: Bool {
        didSet {
            guard oldValue != naturalScrolling else { return }
            TrackpadPreferences(sensitivity: sensitivity, naturalScrolling: naturalScrolling)
                .save()
            syncModel()
        }
    }

    // MARK: - Internal state

    private var screen: TrackpadScreenSize = .fallback
    private var lastAction: String?
    private var isSending = false
    private var accumulator = TrackpadScrollAccumulator()
    private var lastGestureAt = Date.distantPast
    private var lastActionClearWork: DispatchWorkItem?
    private var probedScreenDeviceID: String?

    private var panel: TrackpadPanelWindowController?
    private var model: TrackpadPanelModel?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        let preferences = TrackpadPreferences.load()
        self.sensitivity = preferences.sensitivity
        self.naturalScrolling = preferences.naturalScrolling
        observeDevices()
    }

    // MARK: - Panel lifecycle

    /// Shows the floating panel, optionally pinned to one device. With no explicit
    /// device the Hub's selected device is used.
    func show(deviceID: String? = nil) {
        resolveDevice(deviceID)
        ensurePanel()
        panel?.show()
        isPresented = true
        syncModel()
        refreshScreenSizeIfNeeded()
    }

    func hide() {
        panel?.hide()
        isPresented = false
        syncModel()
    }

    func toggle(deviceID: String? = nil) {
        if isPresented {
            hide()
        } else {
            show(deviceID: deviceID)
        }
    }

    // MARK: - Input

    /// Sends one semantic gesture. Rapid repeats are debounced so a held gesture
    /// cannot flood ADB.
    func handle(_ gesture: TrackpadGesture) {
        guard let deviceID, isDeviceConnected else {
            toast("No device connected")
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastGestureAt) >= 0.22 else { return }
        lastGestureAt = now

        let commands = TrackpadGestureMapping.commands(for: gesture, screen: screen)
        send(commands, deviceID: deviceID, confirmation: gesture.confirmation)
    }

    /// Feeds a two-finger scroll delta into the accumulator and sends a swipe when
    /// enough travel has built up.
    func scroll(deltaY: Double) {
        guard let deviceID, isDeviceConnected else { return }
        guard
            let swipe = accumulator.add(
                deltaY: deltaY,
                naturalScrolling: naturalScrolling,
                sensitivity: sensitivity)
        else { return }
        let arguments = TrackpadScrollAccumulator.swipeArguments(
            direction: swipe.direction, distance: swipe.distance, screen: screen)
        send(
            [.shell(arguments.joined(separator: " "))],
            deviceID: deviceID,
            confirmation: nil)
    }

    // MARK: - State exposed to the panel

    var panelState: TrackpadPanelState {
        TrackpadPanelState(
            deviceID: deviceID,
            deviceName: deviceName,
            isDeviceConnected: isDeviceConnected,
            sensitivity: sensitivity,
            naturalScrolling: naturalScrolling,
            lastAction: lastAction,
            isSending: isSending,
            screen: screen)
    }

    var panelActions: TrackpadPanelActions {
        TrackpadPanelActions(
            gesture: { [weak self] in self?.handle($0) },
            scroll: { [weak self] in self?.scroll(deltaY: $0) },
            setSensitivity: { [weak self] in self?.sensitivity = $0 },
            setNaturalScrolling: { [weak self] in self?.naturalScrolling = $0 },
            close: { [weak self] in self?.hide() },
            openHub: { PanelRouter.openDashboard() }
        )
    }

    // MARK: - Device resolution

    private func resolveDevice(_ explicitID: String?) {
        let store = HubStore.shared
        let device: AndroidDevice?
        if let explicitID {
            device = store.devices.first(where: { $0.id == explicitID }) ?? store.selectedDevice
        } else {
            device = store.selectedDevice
        }
        deviceID = device?.id
        deviceName = device?.name
        isDeviceConnected = device?.isConnected ?? false
        accumulator.reset()
    }

    private func observeDevices() {
        HubStore.shared.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                guard let self else { return }
                if let currentID = self.deviceID,
                    let device = devices.first(where: { $0.id == currentID })
                {
                    self.deviceName = device.name
                    self.isDeviceConnected = device.isConnected
                } else if self.deviceID != nil {
                    self.isDeviceConnected = false
                } else if let selected = HubStore.shared.selectedDevice {
                    // The panel was opened before a device appeared; adopt it.
                    self.deviceID = selected.id
                    self.deviceName = selected.name
                    self.isDeviceConnected = selected.isConnected
                    self.refreshScreenSizeIfNeeded()
                }
                self.syncModel()
            }
            .store(in: &cancellables)
    }

    // MARK: - Screen size

    private func refreshScreenSizeIfNeeded() {
        guard let deviceID, isDeviceConnected else { return }
        guard probedScreenDeviceID != deviceID else { return }
        probedScreenDeviceID = deviceID
        let adb = DependencyContainer.shared.adb
        adb.executeADBCommand(arguments: ["-s", deviceID, "shell", "wm", "size"]) {
            [weak self] success, output, _ in
            guard success, let output, let parsed = TrackpadScreenSize.parse(wmSize: output)
            else { return }
            self?.screen = parsed
            self?.syncModel()
        }
    }

    // MARK: - Sending

    private func send(
        _ commands: [TrackpadCommand], deviceID: String, confirmation: String?
    ) {
        guard !commands.isEmpty else { return }
        isSending = true
        syncModel()

        let adb = DependencyContainer.shared.adb
        let group = DispatchGroup()
        var failure: String?
        for command in commands {
            group.enter()
            adb.executeADBCommand(
                arguments: ["-s", deviceID, "shell"] + command.arguments
            ) { success, _, error in
                if !success, failure == nil { failure = error }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isSending = false
            if let failure, !failure.isEmpty {
                self.toast("Gesture failed — check the connection")
                _ = failure
            } else if let confirmation {
                self.toast(confirmation)
            }
            self.syncModel()
        }
    }

    private func toast(_ text: String) {
        lastAction = text
        syncModel()
        lastActionClearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lastAction = nil
            self.syncModel()
        }
        lastActionClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    // MARK: - Panel plumbing

    private func ensurePanel() {
        guard panel == nil else { return }
        let model = TrackpadPanelModel(state: panelState, actions: panelActions)
        self.model = model
        panel = TrackpadPanelWindowController(model: model) { [weak self] in
            self?.isPresented = false
            self?.syncModel()
        }
    }

    private func syncModel() {
        model?.state = panelState
    }
}
