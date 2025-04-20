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
    
    var devices: [AndroidDevice] { get }
    var apps: [AndroidApp] { get }
    var error: String? { get }
    var isLoading: Bool { get }
    
    func refreshDevices()
    func fetchApps(for deviceID: String)
    func launchApp(packageID: String, deviceID: String)
    func mirrorDevice(deviceID: String)
}
