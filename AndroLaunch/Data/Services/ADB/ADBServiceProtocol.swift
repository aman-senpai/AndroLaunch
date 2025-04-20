//
//  ADBServices.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

//
//  ADBServiceProtocol.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import Foundation
import Combine
// import SwiftUI // Only import SwiftUI if needed for the protocol itself,
                 // not for structs/classes defined elsewhere

// --- ADBService Protocol Definition ---
protocol ADBServiceProtocol {
    // Publishers for reactive updates
    var devices: PassthroughSubject<[AndroidDevice], Never> { get }
    var apps: PassthroughSubject<[AndroidApp], Never> { get }
    var error: PassthroughSubject<String?, Never> { get }

    // Methods to be implemented by conforming types
    func findADB() // Discover ADB path and start daemon
    func listDevices() // List connected devices
    func startADBDaemon() // Start the ADB server
    func fetchApps(for deviceID: String) // Fetch apps for a specific device
    func launchApp(packageID: String, deviceID: String) // Launch an app on a device
    func mirrorDevice(deviceID: String)
}
// --- End ADBService Protocol Definition ---

// Remove the definitions for AndroidDevice, AndroidApp, ScrcpyServiceProtocol,
// and DeviceRepositoryProtocol if they are currently in this file.
// They should be in their own respective files.
