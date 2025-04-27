//
//  AndroidApp.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import Foundation

public struct AndroidApp: Identifiable, Codable, Equatable {
    public let id: String
    public let name: String
    public let iconName: String
    public let packageName: String
    
    public init(id: String, name: String, iconName: String = "android", packageName: String) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.packageName = packageName
    }
}
