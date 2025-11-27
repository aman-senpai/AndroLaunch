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
    func launchApp(packageID: String, deviceID: String, audioEnabled: Bool, resolution: Int)
    func launchCamera(deviceID: String, facing: CameraFacing)
    func mirrorDevice(deviceID: String, audioEnabled: Bool)
    func disconnectDevice(deviceID: String)
    func installAPK(deviceID: String, apkPath: String)
    func uninstallApp(deviceID: String, packageID: String)

}
