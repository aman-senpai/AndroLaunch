//
//  AppConstants.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//
import Foundation

enum AppConstants {
    static let adbPaths: [String] = {
        var paths: [String] = []
        if let bundled = Bundle.main.url(forResource: "adb", withExtension: nil)?.path {
            paths.append(bundled)
        }
        paths.append(contentsOf: [
            "/usr/local/bin/adb", // Homebrew
            "/opt/homebrew/bin/adb", // Homebrew (Apple Silicon)
            "/usr/bin/adb", // System default (less common)
            "~/.android-sdk/platform-tools/adb", // Example user path
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb" // Standard Android Studio path
        ])
        return paths.map { ($0 as NSString).expandingTildeInPath }
    }()

    static let scrcpyPaths = [
        "/opt/homebrew/bin/scrcpy",
        "/usr/local/bin/scrcpy",
        "\(NSHomeDirectory())/.local/bin/scrcpy",
        "/Applications/scrcpy.app/Contents/MacOS/scrcpy"
    ]
}
