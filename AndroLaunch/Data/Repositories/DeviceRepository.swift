//
//  DeviceRepository.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import Foundation
import Combine
import SwiftUI // Import SwiftUI for ObservableObject

    final class DeviceRepository: DeviceRepositoryProtocol { // Conform to the protocol defined in Domain

    // @Published properties. These automatically provide a publisher ($propertyName).
    // These properties are internal to the repository's state management.
    @Published var devices: [AndroidDevice] = []
    @Published var apps: [AndroidApp] = [] // Assuming AndroidApp is also defined in Domain or a shared module
    @Published var error: String? = nil // Changed to String? as per your code
    @Published var isLoading: Bool = false

    // Implement the publisher requirements from the protocol
    // These provide external access to the published data via the protocol.
    public var errorPublisher: AnyPublisher<String?, Never> { $error.eraseToAnyPublisher() }
    public var devicesPublisher: AnyPublisher<[AndroidDevice], Never> { $devices.eraseToAnyPublisher() }
    public var appsPublisher: AnyPublisher<[AndroidApp], Never> { $apps.eraseToAnyPublisher() } // Assuming AndroidApp is defined
    public var isLoadingPublisher: AnyPublisher<Bool, Never> { $isLoading.eraseToAnyPublisher() }


    // Dependencies (assuming these protocols are defined elsewhere, e.g., in a Service layer)
    private let adbService: ADBServiceProtocol // Assuming ADBServiceProtocol is defined elsewhere
    private let scrcpyService: ScrcpyServiceProtocol // Assuming ScrcpyServiceProtocol is defined elsewhere
    private var cancellables = Set<AnyCancellable>()

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
                self?.apps = apps
            }
            .store(in: &cancellables)

        adbService.error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (error: String?) in // Explicit type annotation
                self?.error = error
                // Set isLoading to false when an error occurs during device refresh
                if error != nil && self?.isLoading == true {
                    self?.isLoading = false
                }
            }
            .store(in: &cancellables)

    }

    // MARK: - DeviceRepositoryProtocol Methods

        func refreshDevices() {
            isLoading = true
            adbService.findADB()
        }

        func fetchApps(for deviceID: String) {
            adbService.fetchApps(for: deviceID)
            // Clear previous apps when fetching new ones
            DispatchQueue.main.async {
                self.apps = []
            }
        }
    func launchApp(packageID: String, deviceID: String) {
        adbService.launchApp(packageID: packageID, deviceID: deviceID)
        // Handle potential errors from launching the app
    }

    func mirrorDevice(deviceID: String) {
        adbService.mirrorDevice(deviceID: deviceID)
        // Handle potential errors from mirroring the device
    }
        
        
}
