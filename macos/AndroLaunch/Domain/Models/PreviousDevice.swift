//
//  PreviousDevice.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 2/6/26.
//

import Foundation

/// A wireless device that was previously connected, stored for quick reconnection.
struct PreviousDevice: Codable, Identifiable, Hashable {
    let serialNumber: String
    var name: String
    var model: String?
    var lastKnownHost: String  // IP:port for reconnection
    var lastConnectedDate: Date

    var id: String { serialNumber }

    func hash(into hasher: inout Hasher) {
        hasher.combine(serialNumber)
    }

    static func == (lhs: PreviousDevice, rhs: PreviousDevice) -> Bool {
        lhs.serialNumber == rhs.serialNumber
    }
}
