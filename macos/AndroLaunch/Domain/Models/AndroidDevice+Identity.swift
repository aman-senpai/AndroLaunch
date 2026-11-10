//
//  AndroidDevice+Identity.swift
//  AndroLaunch
//
//  ADB identifies a device by the transport it is currently reachable on, so the
//  same phone reports a different ID over USB and over Wi-Fi. Everything that must
//  survive a transport change (preferences, endpoint history, clipboard state) is
//  keyed by `stableID` instead.
//

import Foundation

extension AndroidDevice {
    /// Transport-independent identity. Falls back to the transport ID when the
    /// device is too old/dormant to answer `getprop ro.serialno`.
    var stableID: String {
        if let serial = serialNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
            !serial.isEmpty
        {
            return serial
        }
        return id
    }

    var transportKind: TransportKind { TransportKind.classify(id) }

    var isWirelessTransport: Bool { transportKind.isWireless }
}
