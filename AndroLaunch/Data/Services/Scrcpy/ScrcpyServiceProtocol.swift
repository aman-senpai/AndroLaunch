//
//  ScrcpyServiceProtocol.swift
//  AndroLaunch
//
//  Created by Aman Raj on 22/4/25.
//

import Foundation
import Combine

protocol ScrcpyServiceProtocol {
    var error: PassthroughSubject<String?, Never> { get }
    func mirrorDevice(deviceID: String, adbPath: String?)
    func launchApp(packageID: String, deviceID: String, adbPath: String?)
}
