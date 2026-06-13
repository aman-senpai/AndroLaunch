//
//  DependencyStatus.swift
//  AndroLaunch
//

import Foundation

enum DependencyStatus: Equatable {
    case checking
    case found(path: String)
    case notFound
    case installing(phase: String)
    case installed(path: String)
    case failed(error: String)

    var isResolved: Bool {
        switch self {
        case .found, .installed, .failed: return true
        case .checking, .notFound, .installing: return false
        }
    }

    var isInstalled: Bool {
        switch self {
        case .found, .installed: return true
        case .checking, .notFound, .installing, .failed: return false
        }
    }
}

struct DependencyInfo: Identifiable {
    let id: String
    let name: String
    let formulaName: String
    let description: String
    let icon: String
    let brewPackageName: String

    static let adb = DependencyInfo(
        id: "adb",
        name: "ADB (Android Debug Bridge)",
        formulaName: "adb",
        description: "Communicate with your Android device from your Mac.",
        icon: "terminal.fill",
        brewPackageName: "android-platform-tools"
    )

    static let scrcpy = DependencyInfo(
        id: "scrcpy",
        name: "scrcpy (Screen Copy)",
        formulaName: "scrcpy",
        description: "Mirror and control your Android device display.",
        icon: "display",
        brewPackageName: "scrcpy"
    )
}
