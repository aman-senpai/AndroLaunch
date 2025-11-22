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
    
    public init(id: String, name: String, model: String? = nil, isConnected: Bool) {
        self.id = id
        self.name = name
        self.model = model
        self.isConnected = isConnected
    }
}
