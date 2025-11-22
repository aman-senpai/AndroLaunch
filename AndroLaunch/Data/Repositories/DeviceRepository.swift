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

    public var errorPublisher: AnyPublisher<String?, Never> { $error.eraseToAnyPublisher() }
    public var devicesPublisher: AnyPublisher<[AndroidDevice], Never> { $devices.eraseToAnyPublisher() }
    public var appsPublisher: AnyPublisher<[AndroidApp], Never> { $apps.eraseToAnyPublisher() } // Assuming AndroidApp is defined
    public var isLoadingPublisher: AnyPublisher<Bool, Never> { $isLoading.eraseToAnyPublisher() }


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
            .sink { [weak self] (receivedDeviceID, apps: [AndroidApp]) in // Explicit type annotation
                guard let self = self else { return }
                
                // Try to use the serial number as the cache key
                if let serialNumber = self.deviceIDToSerialNumberMap[receivedDeviceID] {
                    self.appCache[serialNumber] = apps
                    
                    // If the received apps are for the currently selected device, update the UI
                    // We need to compare based on the serial number of the device currently active in the UI
                    if let currentDeviceID = self.currentFetchingDeviceID,
                       let currentDevice = self.devices.first(where: { $0.id == currentDeviceID }),
                       currentDevice.serialNumber == serialNumber {
                        self.apps = apps
                    }
                } else {
                    // Fallback if serial number not found for the received deviceID.
                    // This could happen if a device disconnects/reconnects rapidly, or mDNS changes.
                    // In this case, we might still update `self.apps` if it's the currently requested one
                    if receivedDeviceID == self.currentFetchingDeviceID {
                        self.apps = apps
                    }
                    self.error = "⚠️ Received apps for an untracked deviceID (\(receivedDeviceID)). Not cached by serial." // Corrected
                }
            }
            .store(in: &cancellables)

        adbService.error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (error: String?) in // Explicit type annotation
                self?.error = error
                if error != nil && self?.isLoading == true {
                    self?.isLoading = false
                }
            }
            .store(in: &cancellables)

    }

    // MARK: - DeviceRepositoryProtocol Methods

    func refreshDevices() {
        isLoading = true
        // Clear all app caches and the deviceID-to-serial map
        // as the device list (and their connections/serials) might entirely change.
        appCache.removeAll()
        deviceIDToSerialNumberMap.removeAll()
        currentFetchingDeviceID = nil // Reset this
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
    
    // Resolution Preferences
    private var resolutionPreferences: [String: Int] = [:] // Keyed by device ID

    func setResolution(for deviceID: String, resolution: Int) {
        resolutionPreferences[deviceID] = resolution
    }

    func getResolution(for deviceID: String) -> Int {
        return resolutionPreferences[deviceID] ?? 900 // Default to 900p
    }
    
    func launchApp(packageID: String, deviceID: String) {
        let audioEnabled = isAudioEnabled(for: deviceID)
        let resolution = getResolution(for: deviceID)
        adbService.launchApp(packageID: packageID, deviceID: deviceID, audioEnabled: audioEnabled, resolution: resolution)
    }

    func mirrorDevice(deviceID: String) {
        let audioEnabled = isAudioEnabled(for: deviceID)
        adbService.mirrorDevice(deviceID: deviceID, audioEnabled: audioEnabled)
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

}
