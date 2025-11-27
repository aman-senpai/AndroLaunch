//
//  QuickActionsViewModel.swift
//  AndroLaunch
//
//  Created by Aman Raj on 27/11/25.
//

import Foundation
import Combine
import SwiftUI

class QuickActionsViewModel: ObservableObject {
    @Published var deviceID: String
    @Published var deviceName: String = "Device"
    
    // Toggle States (Optimistic)
    @Published var isWifiEnabled: Bool = true
    @Published var isBluetoothEnabled: Bool = true
    @Published var isDarkModeEnabled: Bool = false
    
    @Published var isAirplaneModeEnabled: Bool = false
    @Published var isMobileDataEnabled: Bool = true
    @Published var isLocationEnabled: Bool = true
    @Published var isDoNotDisturbEnabled: Bool = false
    @Published var isAutoRotateEnabled: Bool = true
    @Published var isAdaptiveBrightnessEnabled: Bool = true
    
    private let repository: any DeviceRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(deviceID: String, repository: any DeviceRepositoryProtocol) {
        self.deviceID = deviceID
        self.repository = repository
        
        // Fetch device name if possible or just use ID
        // For now we just use the ID or pass name in init if we want
        
        fetchInitialState()
    }
    
    func fetchInitialState() {
        repository.fetchQuickActionsState(deviceID: deviceID) { [weak self] state in
            DispatchQueue.main.async {
                self?.isWifiEnabled = state.isWifiEnabled
                self?.isBluetoothEnabled = state.isBluetoothEnabled
                self?.isDarkModeEnabled = state.isDarkModeEnabled
                self?.isAirplaneModeEnabled = state.isAirplaneModeEnabled
                self?.isMobileDataEnabled = state.isMobileDataEnabled
                self?.isLocationEnabled = state.isLocationEnabled
                self?.isDoNotDisturbEnabled = state.isDoNotDisturbEnabled
                self?.isAutoRotateEnabled = state.isAutoRotateEnabled
                self?.isAdaptiveBrightnessEnabled = state.isAdaptiveBrightnessEnabled
                // Ringer mode not yet bound to UI state directly other than actions, but good to have if we add UI for it.
            }
        }
    }
    
    // MARK: - Reboot Actions
    func reboot(mode: RebootMode) {
        repository.reboot(deviceID: deviceID, mode: mode)
    }
    
    // MARK: - Toggles
    func toggleWifi() {
        isWifiEnabled.toggle()
        repository.toggleWiFi(deviceID: deviceID, enable: isWifiEnabled)
    }
    
    func toggleBluetooth() {
        isBluetoothEnabled.toggle()
        repository.toggleBluetooth(deviceID: deviceID, enable: isBluetoothEnabled)
    }
    
    func toggleDarkMode() {
        isDarkModeEnabled.toggle()
        repository.toggleDarkMode(deviceID: deviceID, enable: isDarkModeEnabled)
    }
    
    func toggleAirplaneMode() {
        isAirplaneModeEnabled.toggle()
        repository.toggleAirplaneMode(deviceID: deviceID, enable: isAirplaneModeEnabled)
    }
    
    func toggleMobileData() {
        isMobileDataEnabled.toggle()
        repository.toggleMobileData(deviceID: deviceID, enable: isMobileDataEnabled)
    }
    
    func toggleLocation() {
        isLocationEnabled.toggle()
        repository.toggleLocation(deviceID: deviceID, enable: isLocationEnabled)
    }
    
    func toggleDoNotDisturb() {
        isDoNotDisturbEnabled.toggle()
        repository.toggleDoNotDisturb(deviceID: deviceID, enable: isDoNotDisturbEnabled)
    }
    
    func toggleAutoRotate() {
        isAutoRotateEnabled.toggle()
        repository.toggleAutoRotate(deviceID: deviceID, enable: isAutoRotateEnabled)
    }
    
    func toggleAdaptiveBrightness() {
        isAdaptiveBrightnessEnabled.toggle()
        repository.toggleAdaptiveBrightness(deviceID: deviceID, enable: isAdaptiveBrightnessEnabled)
    }
    
    func setRingerMode(_ mode: RingerMode) {
        repository.setRingerMode(deviceID: deviceID, mode: mode)
    }
}
