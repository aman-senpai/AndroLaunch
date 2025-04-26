//
//  ADBServices.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//


import Foundation
import Combine

protocol ADBServiceProtocol {
    // Publishers for reactive updates
    var devices: PassthroughSubject<[AndroidDevice], Never> { get }
    var apps: PassthroughSubject<[AndroidApp], Never> { get }
    var error: PassthroughSubject<String?, Never> { get }

    // Methods to be implemented by conforming types
    func findADB()
    func listDevices()
    func startADBDaemon()
    func fetchApps(for deviceID: String)
    func launchApp(packageID: String, deviceID: String)
    func mirrorDevice(deviceID: String)
}
