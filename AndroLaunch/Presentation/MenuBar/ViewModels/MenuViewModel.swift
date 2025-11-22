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
    func launchApp(packageID: String, deviceID: String) { repository.launchApp(packageID: packageID, deviceID: deviceID) }
    func mirrorDevice(deviceID: String) { repository.mirrorDevice(deviceID: deviceID) }
    func disconnectDevice(deviceID: String) { repository.disconnectDevice(deviceID: deviceID) }

    
}
