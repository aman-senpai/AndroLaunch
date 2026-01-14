//
//  AndroidDevices.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import Foundation

public struct AndroidDevice: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let model: String?
    public let isConnected: Bool
    public let serialNumber: String?
    public let androidVersion: String?
    public let apiLevel: String?
    public let batteryLevel: Int?
    public let isCharging: Bool?
    
    public init(id: String, name: String, model: String? = nil, isConnected: Bool, serialNumber: String? = nil, androidVersion: String? = nil, apiLevel: String? = nil, batteryLevel: Int? = nil, isCharging: Bool? = nil) {
        self.id = id
        self.name = name
        self.model = model
        self.isConnected = isConnected
        self.serialNumber = serialNumber
        self.androidVersion = androidVersion
        self.apiLevel = apiLevel
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
    }
}

