//
//  AndroidDevices.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import Foundation

public struct AndroidDevice: Identifiable, Equatable {
    public let id: String
    public var name: String
    public var model: String?
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

extension AndroidDevice {
    /// scrcpy's `--new-display` creates a virtual display. On Android 12, 12L and 13 the platform
    /// SystemUI (WM Shell `LegacySplitScreenController`) dereferences a null `DisplayLayout` for
    /// that display on its next rotation/configuration event, crashes, and on restart re-shows the
    /// lock screen — the phone ends up locked. Android 14 removed that code path, so only these
    /// versions must fall back to mirroring the main display.
    ///
    /// An unknown API level is treated as unsafe so the device is never locked by mistake.
    public var virtualDisplayIsUnsafe: Bool {
        guard let level = apiLevel.flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) })
        else { return true }
        return (31...33).contains(level)
    }
}

