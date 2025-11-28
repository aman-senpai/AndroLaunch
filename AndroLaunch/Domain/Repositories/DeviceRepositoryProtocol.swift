//
//  DeviceRepositoryProtocol.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import Combine
import SwiftUI

protocol DeviceRepositoryProtocol: ObservableObject {
    var objectWillChange: ObservableObjectPublisher { get }
    var errorPublisher: AnyPublisher<String?, Never> { get }
    var devicesPublisher: AnyPublisher<[AndroidDevice], Never> { get }
    var appsPublisher: AnyPublisher<[AndroidApp], Never> { get }
    var isLoadingPublisher: AnyPublisher<Bool, Never> { get }
    var isLoadingAppsPublisher: AnyPublisher<Bool, Never> { get }
    
    var devices: [AndroidDevice] { get }
    var apps: [AndroidApp] { get }
    var error: String? { get }
    var isLoading: Bool { get }
    var isLoadingApps: Bool { get }
    var adbPath: String? { get }
    
    func refreshDevices()
    func fetchApps(for deviceID: String)
    func forceRefreshApps(for deviceID: String)
    func launchApp(packageID: String, deviceID: String, appName: String)
    func mirrorDevice(deviceID: String)
    func launchCamera(deviceID: String, facing: CameraFacing)
    func disconnectDevice(deviceID: String)
    func installAPK(deviceID: String, apkPath: String)
    func uninstallApp(deviceID: String, packageID: String)
    func clearAppData(deviceID: String, packageID: String)
    
    func toggleAudio(for deviceID: String)
    func isAudioEnabled(for deviceID: String) -> Bool
    
    func toggleClipboard(for deviceID: String)
    func isClipboardEnabled(for deviceID: String) -> Bool
    
    func setResolution(for deviceID: String, resolution: Int)
    func getResolution(for deviceID: String) -> Int

    // Quick Actions
    func reboot(deviceID: String, mode: RebootMode)
    func toggleWiFi(deviceID: String, enable: Bool)
    func toggleBluetooth(deviceID: String, enable: Bool)
    func toggleDarkMode(deviceID: String, enable: Bool)
    
    func toggleAirplaneMode(deviceID: String, enable: Bool)
    func toggleMobileData(deviceID: String, enable: Bool)
    func toggleLocation(deviceID: String, enable: Bool)
    func toggleDoNotDisturb(deviceID: String, enable: Bool)
    func toggleAutoRotate(deviceID: String, enable: Bool)
    func setRingerMode(deviceID: String, mode: RingerMode)
    func toggleAdaptiveBrightness(deviceID: String, enable: Bool)
    
    func fetchQuickActionsState(deviceID: String, completion: @escaping (QuickActionsState) -> Void)
}
