//
//  GlanceBoardController.swift
//  AndroLaunch
//
//  A floating desktop board with phone status and quick app shortcuts.
//
//  WidgetKit extension support is documented as future work (it needs a separate
//  signed extension target); this is a real, useful desktop surface instead. Data
//  is live: device/battery from the Hub feed, storage from `StorageService` with a
//  `df /data` fallback, and quick apps from the selected device's catalog.
//

import AppKit
import Combine
import Foundation

final class GlanceBoardController: ObservableObject {
    static let shared = GlanceBoardController()

    enum Keys {
        static let hideUntilConnected = "platform.glance.hideUntilConnected"
        static let enabled = "platform.glance.enabled"
    }

    // MARK: - Published state

    @Published private(set) var isVisible = false
    /// When on, the board stays hidden while no device is connected and returns
    /// when one reconnects.
    @Published var hideUntilConnected: Bool {
        didSet {
            guard oldValue != hideUntilConnected else { return }
            UserDefaults.standard.set(hideUntilConnected, forKey: Keys.hideUntilConnected)
            syncModel()
        }
    }

    // MARK: - Internal state

    private var state = GlanceBoardState()
    private var panel: GlanceBoardPanelWindowController?
    private var model: GlanceBoardModel?
    private let shortcutStore = GlanceShortcutStore()

    private var fallbackStorage: [String: GlanceStorageUsage] = [:]
    private var probedStorageDevices = Set<String>()
    private var requestedStorageLoad = Set<String>()

    private var hiddenDeviceID: String?
    private var hiddenTargetWasConnected = false

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        hideUntilConnected = UserDefaults.standard.bool(forKey: Keys.hideUntilConnected)
        observeHub()
        observeStorage()
        rebuildState()
    }

    // MARK: - Visibility

    func show() {
        ensurePanel()
        isVisible = true
        panel?.show()
        rebuildState()
        syncModel()
        refresh()
    }

    func hide() {
        isVisible = false
        panel?.hide()
        syncModel()
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Restores the board on launch when the user had it enabled. Called by the
    /// app lifecycle (Lead-owned) so Glance never opens a window on its own.
    func restoreIfEnabled() {
        if UserDefaults.standard.bool(forKey: Keys.enabled) {
            show()
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Keys.enabled)
        if enabled {
            show()
        } else {
            hide()
        }
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Keys.enabled)
    }

    // MARK: - Refresh

    func refresh() {
        HubStore.shared.refresh()
        if let deviceID = state.deviceID {
            HubStore.shared.loadApps(for: deviceID)
            if !requestedStorageLoad.contains(deviceID) {
                requestedStorageLoad.insert(deviceID)
                StorageService.shared.load(deviceID: deviceID)
            }
        }
        rebuildState()
        syncModel()
    }

    // MARK: - Actions exposed to the board

    var boardActions: GlanceBoardActions {
        GlanceBoardActions(
            openApp: { [weak self] app in self?.open(app) },
            openHub: { PanelRouter.openDashboard() },
            close: { [weak self] in self?.hide() },
            setHideUntilConnected: { [weak self] in self?.setHideUntilConnected($0) },
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func setHideUntilConnected(_ enabled: Bool) {
        hideUntilConnected = enabled
        if enabled {
            hiddenDeviceID = state.deviceID
            hiddenTargetWasConnected = state.isConnected
            hide()
        } else {
            hiddenDeviceID = nil
            show()
        }
    }

    private func open(_ app: GlanceAppShortcut) {
        guard let device = HubStore.shared.selectedDevice else { return }
        shortcutStore.recordUse(app.packageName)
        // Frame Mode opens a virtual display on Android 14+; older releases use the
        // mirror fallback so the gesture never locks the phone's UI.
        let mode: AppLaunchMode = device.virtualDisplayIsUnsafe ? .mirror : .meldWindow
        AppWindowController.shared.openApp(
            packageID: app.packageName,
            appName: app.name,
            deviceID: device.id,
            mode: mode)
        rebuildState()
        syncModel()
    }

    // MARK: - Observation

    private func observeHub() {
        HubStore.shared.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                guard let self else { return }
                self.rebuildState()
                self.handleDeviceUpdate(devices)
                self.syncModel()
            }
            .store(in: &cancellables)

        HubStore.shared.$apps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.rebuildState()
                self.syncModel()
            }
            .store(in: &cancellables)

        HubStore.shared.$selectedDeviceID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] deviceID in
                guard let self else { return }
                if let deviceID, self.state.deviceID != deviceID {
                    // A different phone is selected: re-read storage for it.
                    if !self.requestedStorageLoad.contains(deviceID) {
                        self.requestedStorageLoad.insert(deviceID)
                        StorageService.shared.load(deviceID: deviceID)
                    }
                }
                self.rebuildState()
                self.syncModel()
            }
            .store(in: &cancellables)
    }

    private func observeStorage() {
        StorageService.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.rebuildState()
                self.syncModel()
            }
            .store(in: &cancellables)
    }

    private func handleDeviceUpdate(_ devices: [AndroidDevice]) {
        if hideUntilConnected {
            if let target = hiddenDeviceID, !isVisible {
                let connected = devices.contains { $0.id == target && $0.isConnected }
                if connected && !hiddenTargetWasConnected {
                    hiddenDeviceID = nil
                    show()
                }
                hiddenTargetWasConnected = connected
            } else if isVisible, !state.isConnected, state.deviceID != nil {
                // The phone went away: hide until it comes back.
                hiddenDeviceID = state.deviceID
                hiddenTargetWasConnected = false
                hide()
            }
        } else {
            hiddenDeviceID = nil
        }
    }

    // MARK: - State building

    private func rebuildState() {
        let store = HubStore.shared
        let device = store.selectedDevice

        var next = GlanceBoardState()
        next.hideUntilConnected = hideUntilConnected
        next.deviceID = device?.id
        next.deviceName = device?.name ?? "Glance"
        next.isConnected = device?.isConnected ?? false
        next.transport = device.map { GlanceTransport.classify(deviceID: $0.id) }
        next.batteryLevel = device?.batteryLevel
        next.isCharging = device?.isCharging

        if device != nil {
            let shortcuts = store.apps.map {
                GlanceAppShortcut(
                    packageName: $0.packageName, name: $0.name, iconName: $0.iconName)
            }
            next.apps = GlanceQuickApps.ordered(apps: shortcuts, pinned: shortcutStore.pinned)
        }

        if let device {
            if let snapshot = StorageService.shared.snapshot,
                snapshot.deviceID == device.id, snapshot.totalBytes > 0
            {
                next.storageFraction = snapshot.usedFraction
                next.storageSummary =
                    "\(GlanceStorageProbe.formatBytes(snapshot.usedBytes)) of \(GlanceStorageProbe.formatBytes(snapshot.totalBytes)) used"
            } else if let usage = fallbackStorage[device.id] {
                next.storageFraction = usage.usedFraction
                next.storageSummary = usage.summary
            } else if probedStorageDevices.contains(device.id) {
                next.isLoadingStorage = false
            } else {
                next.isLoadingStorage = true
                probeStorageIfNeeded(deviceID: device.id)
            }
        }

        state = next
    }

    /// `StorageService` owns the storage scan. This board only needs the
    /// used fraction, so when the service hasn't produced a snapshot yet it asks
    /// `df -k /data` directly instead of showing an empty row forever.
    private func probeStorageIfNeeded(deviceID: String) {
        guard !probedStorageDevices.contains(deviceID) else { return }
        probedStorageDevices.insert(deviceID)

        let adb = DependencyContainer.shared.adb
        adb.executeADBCommand(arguments: ["-s", deviceID, "shell", "df", "-k", "/data"]) {
            [weak self] success, output, _ in
            guard let self else { return }
            guard success, let output,
                let usage = GlanceStorageProbe.parseDataPartition(dfOutput: output)
            else {
                self.rebuildState()
                self.syncModel()
                return
            }
            self.fallbackStorage[deviceID] = usage
            self.rebuildState()
            self.syncModel()
        }
    }

    // MARK: - Panel plumbing

    private func ensurePanel() {
        guard panel == nil else { return }
        ensureModel()
        guard let model else { return }
        panel = GlanceBoardPanelWindowController(model: model) { [weak self] in
            self?.isVisible = false
            self?.syncModel()
        }
    }

    private func ensureModel() {
        guard model == nil else { return }
        model = GlanceBoardModel(state: state, actions: boardActions)
    }

    private func syncModel() {
        ensureModel()
        model?.state = state
    }
}
