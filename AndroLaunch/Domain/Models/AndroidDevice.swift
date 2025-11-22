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
    public let serialNumber: String? // Add this line
    
    public init(id: String, name: String, model: String? = nil, isConnected: Bool, serialNumber: String? = nil) { // Update initializer
        self.id = id
        self.name = name
        self.model = model
        self.isConnected = isConnected
        self.serialNumber = serialNumber // Initialize the new property
    }
}

