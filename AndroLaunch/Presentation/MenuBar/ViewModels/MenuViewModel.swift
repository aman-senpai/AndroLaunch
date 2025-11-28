//
//  MenuViewModel.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//


import Combine
import SwiftUI

final class MenuViewModel: ObservableObject {
    @Published var devices: [AndroidDevice] = []
    @Published var deviceApps: [String: [AndroidApp]] = [:] // Apps per device ID
    @Published var error: String? = nil
    @Published var isLoading: Bool = false
    @Published var isLoadingApps: Bool = false
    @Published var currentDeviceID: String? = nil
    
    internal let repository: any DeviceRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()

    init(deviceRepository: any DeviceRepositoryProtocol) {
        self.repository = deviceRepository
        setupObservers()
    }

    private func setupObservers() {
        repository.devicesPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$devices)
        
        repository.appsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] apps in
                guard let self = self, let deviceID = self.currentDeviceID else { return }
                // Store apps for the current device
                self.deviceApps[deviceID] = apps
            }
            .store(in: &cancellables)
        
        repository.errorPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$error)
        
        repository.isLoadingPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)
        
        repository.isLoadingAppsPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoadingApps)
    }

    func refresh() { repository.refreshDevices() }
    func fetchApps(for deviceID: String) {
        currentDeviceID = deviceID
        repository.fetchApps(for: deviceID)
    }
    func forceRefreshApps(for deviceID: String) {
        currentDeviceID = deviceID
        repository.forceRefreshApps(for: deviceID)
    }
    func launchApp(packageID: String, deviceID: String, appName: String) { repository.launchApp(packageID: packageID, deviceID: deviceID, appName: appName) }
    func mirrorDevice(deviceID: String) { repository.mirrorDevice(deviceID: deviceID) }
    func launchCamera(deviceID: String, facing: CameraFacing) { repository.launchCamera(deviceID: deviceID, facing: facing) }
    func disconnectDevice(deviceID: String) { repository.disconnectDevice(deviceID: deviceID) }
    func installAPK(deviceID: String, apkPath: String) { repository.installAPK(deviceID: deviceID, apkPath: apkPath) }
    func uninstallApp(deviceID: String, packageID: String) { repository.uninstallApp(deviceID: deviceID, packageID: packageID) }
    
    func toggleAudio(for deviceID: String) {
        repository.toggleAudio(for: deviceID)
        objectWillChange.send() // Notify UI of change
    }
    
    func isAudioEnabled(for deviceID: String) -> Bool {
        return repository.isAudioEnabled(for: deviceID)
    }
    
    func toggleClipboard(for deviceID: String) {
        repository.toggleClipboard(for: deviceID)
        objectWillChange.send()
    }
    
    func isClipboardEnabled(for deviceID: String) -> Bool {
        return repository.isClipboardEnabled(for: deviceID)
    }
    
    func setResolution(for deviceID: String, resolution: Int) {
        repository.setResolution(for: deviceID, resolution: resolution)
        objectWillChange.send()
    }
    
    func getResolution(for deviceID: String) -> Int {
        return repository.getResolution(for: deviceID)
    }
    
    func setMaxSize(for deviceID: String, size: Int) {
        repository.setMaxSize(for: deviceID, size: size)
        objectWillChange.send()
    }
    
    func getMaxSize(for deviceID: String) -> Int {
        return repository.getMaxSize(for: deviceID)
    }
    
    // FPS
    func setMaxFPS(for deviceID: String, fps: Int) {
        repository.setMaxFPS(for: deviceID, fps: fps)
        objectWillChange.send()
    }
    
    func getMaxFPS(for deviceID: String) -> Int {
        return repository.getMaxFPS(for: deviceID)
    }
    
    // Bit Rate
    func setBitRate(for deviceID: String, bitRate: Int) {
        repository.setBitRate(for: deviceID, bitRate: bitRate)
        objectWillChange.send()
    }
    
    func getBitRate(for deviceID: String) -> Int {
        return repository.getBitRate(for: deviceID)
    }
    
    // Orientation
    func setOrientation(for deviceID: String, orientation: String) {
        repository.setOrientation(for: deviceID, orientation: orientation)
        objectWillChange.send()
    }
    
    func getOrientation(for deviceID: String) -> String {
        return repository.getOrientation(for: deviceID)
    }
    
    func isCaptureOrientationEnabled(for deviceID: String) -> Bool {
        return repository.isCaptureOrientationEnabled(for: deviceID)
    }
    
    func toggleCaptureOrientation(for deviceID: String) {
        repository.toggleCaptureOrientation(for: deviceID)
        objectWillChange.send()
    }
    
    // MARK: - Camera
    func setCameraFacing(for deviceID: String, facing: String) {
        repository.setCameraFacing(for: deviceID, facing: facing)
        objectWillChange.send()
    }
    
    func getCameraFacing(for deviceID: String) -> String {
        return repository.getCameraFacing(for: deviceID)
    }
    
    func setCameraFPS(for deviceID: String, fps: Int) {
        repository.setCameraFPS(for: deviceID, fps: fps)
        objectWillChange.send()
    }
    
    func getCameraFPS(for deviceID: String) -> Int {
        return repository.getCameraFPS(for: deviceID)
    }
    
    func setCameraSize(for deviceID: String, size: Int) {
        repository.setCameraSize(for: deviceID, size: size)
        objectWillChange.send()
    }
    
    func getCameraSize(for deviceID: String) -> Int {
        return repository.getCameraSize(for: deviceID)
    }
    
    func setCameraAR(for deviceID: String, ar: String) {
        repository.setCameraAR(for: deviceID, ar: ar)
        objectWillChange.send()
    }
    
    func getCameraAR(for deviceID: String) -> String {
        return repository.getCameraAR(for: deviceID)
    }
    
    func mirrorCamera(deviceID: String) {
        repository.mirrorCamera(deviceID: deviceID)
    }
    
    var adbPath: String? { repository.adbPath }

    // MARK: - Quick Actions
    @Published var quickActionsStates: [String: QuickActionsState] = [:]
    
    func fetchQuickActionsState(for deviceID: String) {
        repository.fetchQuickActionsState(deviceID: deviceID) { [weak self] state in
            DispatchQueue.main.async {
                self?.quickActionsStates[deviceID] = state
            }
        }
    }
    
    func reboot(deviceID: String, mode: RebootMode) {
        repository.reboot(deviceID: deviceID, mode: mode)
    }
    
    func toggleWifi(for deviceID: String) {
        let currentState = quickActionsStates[deviceID]?.isWifiEnabled ?? false
        repository.toggleWiFi(deviceID: deviceID, enable: !currentState)
        if var state = quickActionsStates[deviceID] {
            state.isWifiEnabled.toggle()
            quickActionsStates[deviceID] = state
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.fetchQuickActionsState(for: deviceID)
        }
    }
    
    func toggleBluetooth(for deviceID: String) {
        let currentState = quickActionsStates[deviceID]?.isBluetoothEnabled ?? false
        repository.toggleBluetooth(deviceID: deviceID, enable: !currentState)
        if var state = quickActionsStates[deviceID] {
            state.isBluetoothEnabled.toggle()
            quickActionsStates[deviceID] = state
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.fetchQuickActionsState(for: deviceID)
        }
    }
    
    func toggleDarkMode(for deviceID: String) {
        let currentState = quickActionsStates[deviceID]?.isDarkModeEnabled ?? false
        repository.toggleDarkMode(deviceID: deviceID, enable: !currentState)
        if var state = quickActionsStates[deviceID] {
            state.isDarkModeEnabled.toggle()
            quickActionsStates[deviceID] = state
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.fetchQuickActionsState(for: deviceID)
        }
    }
    
    func toggleAirplaneMode(for deviceID: String) {
        let currentState = quickActionsStates[deviceID]?.isAirplaneModeEnabled ?? false
        repository.toggleAirplaneMode(deviceID: deviceID, enable: !currentState)
        if var state = quickActionsStates[deviceID] {
            state.isAirplaneModeEnabled.toggle()
            quickActionsStates[deviceID] = state
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.fetchQuickActionsState(for: deviceID)
        }
    }
    
    func toggleMobileData(for deviceID: String) {
        let currentState = quickActionsStates[deviceID]?.isMobileDataEnabled ?? false
        repository.toggleMobileData(deviceID: deviceID, enable: !currentState)
        if var state = quickActionsStates[deviceID] {
            state.isMobileDataEnabled.toggle()
            quickActionsStates[deviceID] = state
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.fetchQuickActionsState(for: deviceID)
        }
    }
    
    func toggleLocation(for deviceID: String) {
        let currentState = quickActionsStates[deviceID]?.isLocationEnabled ?? false
        repository.toggleLocation(deviceID: deviceID, enable: !currentState)
        if var state = quickActionsStates[deviceID] {
            state.isLocationEnabled.toggle()
            quickActionsStates[deviceID] = state
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.fetchQuickActionsState(for: deviceID)
        }
    }
    
    func toggleDoNotDisturb(for deviceID: String) {
        let currentState = quickActionsStates[deviceID]?.isDoNotDisturbEnabled ?? false
        repository.toggleDoNotDisturb(deviceID: deviceID, enable: !currentState)
        if var state = quickActionsStates[deviceID] {
            state.isDoNotDisturbEnabled.toggle()
            quickActionsStates[deviceID] = state
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.fetchQuickActionsState(for: deviceID)
        }
    }
    
    func toggleAutoRotate(for deviceID: String) {
        let currentState = quickActionsStates[deviceID]?.isAutoRotateEnabled ?? false
        repository.toggleAutoRotate(deviceID: deviceID, enable: !currentState)
        if var state = quickActionsStates[deviceID] {
            state.isAutoRotateEnabled.toggle()
            quickActionsStates[deviceID] = state
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.fetchQuickActionsState(for: deviceID)
        }
    }
    
    func toggleAdaptiveBrightness(for deviceID: String) {
        let currentState = quickActionsStates[deviceID]?.isAdaptiveBrightnessEnabled ?? false
        repository.toggleAdaptiveBrightness(deviceID: deviceID, enable: !currentState)
        if var state = quickActionsStates[deviceID] {
            state.isAdaptiveBrightnessEnabled.toggle()
            quickActionsStates[deviceID] = state
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.fetchQuickActionsState(for: deviceID)
        }
    }
}
