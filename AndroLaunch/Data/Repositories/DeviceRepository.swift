//
//  DeviceRepository.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import Foundation
import Combine
import SwiftUI

final class DeviceRepository: DeviceRepositoryProtocol { // Conform to the protocol defined in Domain

    @Published var devices: [AndroidDevice] = []
    @Published var apps: [AndroidApp] = [] // Assuming AndroidApp is also defined in Domain or a shared module
    @Published var error: String? = nil // Changed to String? as per your code
    @Published var isLoading: Bool = false
    @Published var isLoadingApps: Bool = false

    public var errorPublisher: AnyPublisher<String?, Never> { $error.eraseToAnyPublisher() }
    public var devicesPublisher: AnyPublisher<[AndroidDevice], Never> { $devices.eraseToAnyPublisher() }
    public var appsPublisher: AnyPublisher<[AndroidApp], Never> { $apps.eraseToAnyPublisher() } // Assuming AndroidApp is defined
    public var isLoadingPublisher: AnyPublisher<Bool, Never> { $isLoading.eraseToAnyPublisher() }
    public var isLoadingAppsPublisher: AnyPublisher<Bool, Never> { $isLoadingApps.eraseToAnyPublisher() }
    
    public var adbPath: String? { adbService.adbPath }


    // Dependencies (assuming these protocols are defined elsewhere, e.g., in a Service layer)
    private let adbService: ADBServiceProtocol // Assuming ADBServiceProtocol is defined elsewhere
    private let scrcpyService: ScrcpyServiceProtocol // Assuming ScrcpyServiceProtocol is defined elsewhere
    private var cancellables = Set<AnyCancellable>()
    
    // App cache storage: [serialNumber: [apps]]
    private var appCache: [String: [AndroidApp]] = [:]
    
    // Store the deviceID for which apps are currently being fetched.
    // This is used for UI updates (to display the correct app list), not for caching.
    private var currentFetchingDeviceID: String?

    // A mapping from ADB's reported deviceID to its actual serialNumber
    // This helps in looking up the serial number when an app list comes in for a deviceID.
    private var deviceIDToSerialNumberMap: [String: String] = [:]


    // Initialize with dependencies
    init(adbService: ADBServiceProtocol, scrcpyService: ScrcpyServiceProtocol) {
        self.adbService = adbService
        self.scrcpyService = scrcpyService
        setupBindings()
    }

    // Setup bindings to observe the ADBService
        private func setupBindings() {
            adbService.devices
                .receive(on: DispatchQueue.main)
                .sink { [weak self] devices in
                    guard let self = self else { return }
                    self.devices = devices
                    self.isLoading = false
                    
                    // Update the deviceID to serial number map
                    self.deviceIDToSerialNumberMap = devices.compactMap { device in
                        if let serial = device.serialNumber {
                            return (device.id, serial)
                        }
                        return nil
                    }
                    .reduce(into: [:]) { $0[$1.0] = $1.1 }
                }
                .store(in: &cancellables)

        // Observe apps from adbService
        // adbService.apps now publishes (deviceID, [AndroidApp])
        adbService.apps
            .receive(on: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (receivedDeviceID, apps: [AndroidApp]) in
                guard let self = self else { return }
                
                // Always reset loading state when we get a response
                self.isLoadingApps = false
                
                // Try to use the serial number as the cache key
                if let serialNumber = self.deviceIDToSerialNumberMap[receivedDeviceID] {
                    self.appCache[serialNumber] = apps
                    
                    // If the received apps are for the currently selected device, update the UI
                    if let currentDeviceID = self.currentFetchingDeviceID,
                       let currentDevice = self.devices.first(where: { $0.id == currentDeviceID }),
                       currentDevice.serialNumber == serialNumber {
                        self.apps = apps
                    }
                } else {
                    // Fallback if serial number not found
                    if receivedDeviceID == self.currentFetchingDeviceID {
                        self.apps = apps
                    }
                    if self.deviceIDToSerialNumberMap[receivedDeviceID] == nil {
                         // Only log if we really don't know this device
                         // self.error = "⚠️ Received apps for an untracked deviceID..." // Optional logging
                    }
                }
            }
            .store(in: &cancellables)

        adbService.error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (error: String?) in // Explicit type annotation
                self?.error = error
                if error != nil {
                    if self?.isLoading == true {
                        self?.isLoading = false
                    }
                    if self?.isLoadingApps == true {
                        self?.isLoadingApps = false
                    }
                }
            }
            .store(in: &cancellables)

    }

    // MARK: - DeviceRepositoryProtocol Methods

    func refreshDevices() {
        isLoading = true
        // Clear deviceID-to-serial map as IDs might change, but KEEP app cache (keyed by serial)
        // so we don't re-fetch apps unnecessarily when just refreshing device status.
        deviceIDToSerialNumberMap.removeAll()
        adbService.findADB()
    }

    func fetchApps(for deviceID: String) {
        // Find the AndroidDevice to get its serial number
        guard let device = devices.first(where: { $0.id == deviceID }) else {
            self.error = "Device with ID \(deviceID) not found to fetch apps." // Corrected
            self.apps = []
            return
        }
        
        guard let serialNumber = device.serialNumber else {
            self.error = "Serial number not available for device \(deviceID). Cannot cache apps." // Corrected
            self.apps = []
            // Proceed to fetch without caching if no serial, but log the issue.
            currentFetchingDeviceID = deviceID // Still track it for UI update
            adbService.fetchApps(for: deviceID)
            return
        }

        // Check if apps are already cached for this serial number
        if let cachedApps = appCache[serialNumber] {
            DispatchQueue.main.async {
                self.apps = cachedApps
            }
            // Update currentFetchingDeviceID to ensure subsequent UI updates or actions
            // are correctly attributed to this device, even if cached.
            currentFetchingDeviceID = deviceID
            return
        }
        
        // Not cached, fetch from ADB service
        currentFetchingDeviceID = deviceID // This is the ADB deviceID, used to trigger the ADBService call
        isLoadingApps = true
        adbService.fetchApps(for: deviceID)
        // Clear previous apps when fetching new ones for UI
        DispatchQueue.main.async {
            self.apps = []
        }
    }
    
    func forceRefreshApps(for deviceID: String) {
        guard let device = devices.first(where: { $0.id == deviceID }) else {
            self.error = "Device with ID \(deviceID) not found to force refresh apps." // Corrected
            self.apps = []
            return
        }
        
        // Clear cache for this device's serial number and force a fresh fetch
        if let serialNumber = device.serialNumber {
            appCache.removeValue(forKey: serialNumber)
        } else {
            // If no serial number, we can't clear by serial. Log an error or fallback.
            self.error = "Cannot force refresh apps by serial for device \(deviceID): no serial number." // Corrected
        }

        currentFetchingDeviceID = deviceID
        isLoadingApps = true
        adbService.fetchApps(for: deviceID)
        DispatchQueue.main.async {
            self.apps = []
        }
    }
    
    // Audio Preferences
    private var audioPreferences: [String: Bool] = [:] // Keyed by device ID (or serial if available)

    func toggleAudio(for deviceID: String) {
        let current = isAudioEnabled(for: deviceID)
        audioPreferences[deviceID] = !current
    }
    
    func isAudioEnabled(for deviceID: String) -> Bool {
        return audioPreferences[deviceID] ?? true // Default to true
    }
    
    // Clipboard Preferences
    private var clipboardPreferences: [String: Bool] = [:] // Keyed by device ID
    
    func toggleClipboard(for deviceID: String) {
        let current = isClipboardEnabled(for: deviceID)
        let newState = !current
        clipboardPreferences[deviceID] = newState
        
        if newState {
            adbService.startClipboardSync(deviceID: deviceID)
        } else {
            adbService.stopClipboardSync(deviceID: deviceID)
        }
    }
    
    func isClipboardEnabled(for deviceID: String) -> Bool {
        return clipboardPreferences[deviceID] ?? false // Default to false if we want explicit enable, or true? User said "toggle is on... automatically copied". Let's default to false so they have to turn it on to start the process.
    }
    
    // Resolution Preferences
    private var resolutionPreferences: [String: Int] = [:] // Keyed by device ID

    func setResolution(for deviceID: String, resolution: Int) {
        resolutionPreferences[deviceID] = resolution
    }

    func getResolution(for deviceID: String) -> Int {
        return resolutionPreferences[deviceID] ?? 900 // Default to 900p
    }
    
    func launchApp(packageID: String, deviceID: String, appName: String) {
        let audioEnabled = isAudioEnabled(for: deviceID)
        let clipboardEnabled = isClipboardEnabled(for: deviceID)
        let resolution = getResolution(for: deviceID)
        let deviceName = devices.first(where: { $0.id == deviceID })?.name
        adbService.launchApp(packageID: packageID, deviceID: deviceID, appName: appName, deviceName: deviceName, audioEnabled: audioEnabled, resolution: resolution, clipboardEnabled: clipboardEnabled)
    }

    func mirrorDevice(deviceID: String) {
        let audioEnabled = isAudioEnabled(for: deviceID)
        let clipboardEnabled = isClipboardEnabled(for: deviceID)
        let deviceName = devices.first(where: { $0.id == deviceID })?.name
        adbService.mirrorDevice(deviceID: deviceID, deviceName: deviceName, audioEnabled: audioEnabled, clipboardEnabled: clipboardEnabled)
    }
    
    func launchCamera(deviceID: String, facing: CameraFacing) {
        adbService.launchCamera(deviceID: deviceID, facing: facing)
    }
    
    func disconnectDevice(deviceID: String) {
        // Clear app cache for this device's serial number when disconnecting
        if let device = devices.first(where: { $0.id == deviceID }),
           let serialNumber = device.serialNumber {
            appCache.removeValue(forKey: serialNumber)
        } else {
            self.error = "Cannot clear app cache by serial for device \(deviceID) during disconnect: no serial number or device not found." // Corrected
        }
        adbService.disconnectDevice(deviceID: deviceID)
    }
    
    func installAPK(deviceID: String, apkPath: String) {
        adbService.installAPK(deviceID: deviceID, apkPath: apkPath)
    }

    func uninstallApp(deviceID: String, packageID: String) {
        adbService.uninstallApp(deviceID: deviceID, packageID: packageID)
    }

    func clearAppData(deviceID: String, packageID: String) {
        adbService.clearAppData(deviceID: deviceID, packageID: packageID)
    }

    // MARK: - Quick Actions
    func reboot(deviceID: String, mode: RebootMode) {
        adbService.reboot(deviceID: deviceID, mode: mode)
    }
    
    func toggleWiFi(deviceID: String, enable: Bool) {
        adbService.toggleWiFi(deviceID: deviceID, enable: enable)
    }
    
    func toggleBluetooth(deviceID: String, enable: Bool) {
        adbService.toggleBluetooth(deviceID: deviceID, enable: enable)
    }
    
    func toggleDarkMode(deviceID: String, enable: Bool) {
        adbService.toggleDarkMode(deviceID: deviceID, enable: enable)
    }
    
    func toggleAirplaneMode(deviceID: String, enable: Bool) {
        adbService.toggleAirplaneMode(deviceID: deviceID, enable: enable)
    }
    
    func toggleMobileData(deviceID: String, enable: Bool) {
        adbService.toggleMobileData(deviceID: deviceID, enable: enable)
    }
    
    func toggleLocation(deviceID: String, enable: Bool) {
        adbService.toggleLocation(deviceID: deviceID, enable: enable)
    }
    
    func toggleDoNotDisturb(deviceID: String, enable: Bool) {
        adbService.toggleDoNotDisturb(deviceID: deviceID, enable: enable)
    }
    
    func toggleAutoRotate(deviceID: String, enable: Bool) {
        adbService.toggleAutoRotate(deviceID: deviceID, enable: enable)
    }
    
    func setRingerMode(deviceID: String, mode: RingerMode) {
        adbService.setRingerMode(deviceID: deviceID, mode: mode)
    }
    
    func toggleAdaptiveBrightness(deviceID: String, enable: Bool) {
        adbService.toggleAdaptiveBrightness(deviceID: deviceID, enable: enable)
    }
    
    func fetchQuickActionsState(deviceID: String, completion: @escaping (QuickActionsState) -> Void) {
        adbService.fetchQuickActionsState(deviceID: deviceID, completion: completion)
    }

}
