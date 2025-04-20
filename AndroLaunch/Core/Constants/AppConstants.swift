//
//  AppConstants.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//
import Foundation

enum AppConstants {
    static let adbPaths: [String] = [
        "/usr/local/bin/adb", // Homebrew
        "/opt/homebrew/bin/adb", // Homebrew (Apple Silicon)
        "/usr/bin/adb", // System default (less common)
        "~/.android-sdk/platform-tools/adb", // Example user path
        "/Users/\(NSUserName())/Library/Android/sdk/platform-tools/adb" // Standard Android Studio path
        // Add more potential paths here if necessary
    ].map { ($0 as NSString).expandingTildeInPath } // Expand the tilde (~)
    
    static let scrcpyPaths = [
        "/opt/homebrew/bin/scrcpy",
        "/usr/local/bin/scrcpy",
        "\(NSHomeDirectory())/.local/bin/scrcpy",
        "/Applications/scrcpy.app/Contents/MacOS/scrcpy"
    ]
}
