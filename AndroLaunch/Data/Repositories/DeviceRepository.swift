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
    
    // App cache storage: [deviceID: [apps]]
    private var appCache: [String: [AndroidApp]] = [:]
    private var currentFetchingDeviceID: String?

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
                    self?.devices = devices
                    self?.isLoading = false
                }
                .store(in: &cancellables)

        // Observe apps from adbService
        // Assuming adbService.apps publishes [AndroidApp]
        adbService.apps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (apps: [AndroidApp]) in // Explicit type annotation
                guard let self = self else { return }
                self.apps = apps
                
                // Store in cache for the current device
                if let deviceID = self.currentFetchingDeviceID {
                    self.appCache[deviceID] = apps
                    print("📦 Cached \(apps.count) apps for device: \(deviceID)")
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
        // Clear all app caches when refreshing devices
        appCache.removeAll()
        currentFetchingDeviceID = nil
        print("🗑️ Cleared all app caches on device refresh")
        adbService.findADB()
    }

    func fetchApps(for deviceID: String) {
        // Check if apps are already cached for this device
        if let cachedApps = appCache[deviceID] {
            print("⚡ Using cached apps for device: \(deviceID) (\(cachedApps.count) apps)")
            DispatchQueue.main.async {
                self.apps = cachedApps
            }
            return
        }
        
        // Not cached, fetch from ADB service
        print("🔄 Fetching apps for device: \(deviceID)")
        currentFetchingDeviceID = deviceID
        adbService.fetchApps(for: deviceID)
        // Clear previous apps when fetching new ones
        DispatchQueue.main.async {
            self.apps = []
        }
    }
    
    func forceRefreshApps(for deviceID: String) {
        // Clear cache for this device and force a fresh fetch
        appCache.removeValue(forKey: deviceID)
        print("🔄 Force refreshing apps for device: \(deviceID)")
        currentFetchingDeviceID = deviceID
        adbService.fetchApps(for: deviceID)
        DispatchQueue.main.async {
            self.apps = []
        }
    }
    
    func launchApp(packageID: String, deviceID: String) {
        adbService.launchApp(packageID: packageID, deviceID: deviceID)
    }

    func mirrorDevice(deviceID: String) {
        adbService.mirrorDevice(deviceID: deviceID)
    }
    
    func disconnectDevice(deviceID: String) {
        // Clear app cache for this device when disconnecting
        appCache.removeValue(forKey: deviceID)
        print("🗑️ Cleared app cache for disconnected device: \(deviceID)")
        adbService.disconnectDevice(deviceID: deviceID)
    }

}
