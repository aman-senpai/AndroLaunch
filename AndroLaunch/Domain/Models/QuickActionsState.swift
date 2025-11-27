//
//  QuickActionsState.swift
//  AndroLaunch
//
//  Created by Aman Raj on 27/11/25.
//

import Foundation

struct QuickActionsState {
    var isWifiEnabled: Bool = false
    var isBluetoothEnabled: Bool = false
    var isDarkModeEnabled: Bool = false
    var isAirplaneModeEnabled: Bool = false
    var isMobileDataEnabled: Bool = false
    var isLocationEnabled: Bool = false
    var isDoNotDisturbEnabled: Bool = false
    var isAutoRotateEnabled: Bool = false
    var isAdaptiveBrightnessEnabled: Bool = false
    var ringerMode: RingerMode = .normal
}
