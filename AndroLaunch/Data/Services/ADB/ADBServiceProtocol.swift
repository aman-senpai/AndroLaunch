//
//  ADBServices.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//


import Foundation
import Combine

enum CameraFacing: String {
    case front
    case back
}

enum RebootMode: String {
    case normal = ""
    case bootloader = "bootloader"
    case recovery = "recovery"
}

protocol ADBServiceProtocol {
    // Publishers for reactive updates
    var devices: PassthroughSubject<[AndroidDevice], Never> { get }
    // Changed apps publisher to include the deviceID
    var apps: PassthroughSubject<(String, [AndroidApp]), Never> { get }
    var error: PassthroughSubject<String?, Never> { get }
    var adbPath: String? { get }

    // Methods to be implemented by conforming types
    func findADB()
    func listDevices()
    func startADBDaemon()
    func fetchApps(for deviceID: String)
    func launchApp(packageID: String, deviceID: String, appName: String?, deviceName: String?, audioEnabled: Bool, resolution: Int, clipboardEnabled: Bool)
    func launchCamera(deviceID: String, facing: CameraFacing)
    func mirrorDevice(deviceID: String, deviceName: String?, audioEnabled: Bool, clipboardEnabled: Bool)
    func startClipboardSync(deviceID: String)
    func stopClipboardSync(deviceID: String)
    func disconnectDevice(deviceID: String)
    func installAPK(deviceID: String, apkPath: String)
    func uninstallApp(deviceID: String, packageID: String)
    func clearAppData(deviceID: String, packageID: String)
    
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

enum RingerMode: String {
    case normal = "normal"
    case vibrate = "vibrate"
    case silent = "silent"
}
