//
//  AppConstants.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//
import Foundation

enum AppConstants {
    // MARK: - Android SDK Paths

    /// Common locations for the Android SDK command-line tools bin directory.
    static let cmdlineToolsPaths: [String] = {
        let home = NSHomeDirectory()
        return [
            "\(home)/Library/Android/sdk/cmdline-tools/latest/bin",
            "\(home)/Android/Sdk/cmdline-tools/latest/bin",
            "/opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin",
            "/usr/local/share/android-commandlinetools/cmdline-tools/latest/bin",
        ]
    }()

    /// Common locations for the Android SDK root.
    static let sdkRootPaths: [String] = {
        let home = NSHomeDirectory()
        return [
            "\(home)/Library/Android/sdk",
            "\(home)/Android/Sdk",
        ]
    }()

    /// Auto-detect the Android SDK command-line tools path.
    /// Returns the first path that contains both `sdkmanager` and `avdmanager`.
    static func detectCmdlineToolsPath() -> String? {
        let fm = FileManager.default

        // Check environment variables first
        if let sdkRoot = ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"]
            ?? ProcessInfo.processInfo.environment["ANDROID_HOME"]
        {
            let binPath = (sdkRoot as NSString).appendingPathComponent("cmdline-tools/latest/bin")
            if fm.isExecutableFile(
                atPath: (binPath as NSString).appendingPathComponent("sdkmanager")),
                fm.isExecutableFile(
                    atPath: (binPath as NSString).appendingPathComponent("avdmanager"))
            {
                return binPath
            }
        }

        // Check common paths
        for path in cmdlineToolsPaths {
            let sdkmanagerPath = (path as NSString).appendingPathComponent("sdkmanager")
            let avdmanagerPath = (path as NSString).appendingPathComponent("avdmanager")
            if fm.isExecutableFile(atPath: sdkmanagerPath),
                fm.isExecutableFile(atPath: avdmanagerPath)
            {
                return path
            }
        }

        // Fallback: check if there's a sdkmanager in PATH and derive from that
        if let sdkmanagerInPath = findExecutableInPath(named: "sdkmanager") {
            let binDir = (sdkmanagerInPath as NSString).deletingLastPathComponent
            let avdmanagerPath = (binDir as NSString).appendingPathComponent("avdmanager")
            if fm.isExecutableFile(atPath: avdmanagerPath) {
                return binDir
            }
        }

        return nil
    }

    /// Search for an executable in the system PATH.
    private static func findExecutableInPath(named name: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [name]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path =
                String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty && task.terminationStatus == 0 {
                return path
            }
        } catch {}
        return nil
    }

    // MARK: - ADB Paths

    static let adbPaths: [String] = {
        var paths: [String] = []
        if let bundled = Bundle.main.url(forResource: "adb", withExtension: nil)?.path {
            paths.append(bundled)
        }
        paths.append(contentsOf: [
            "/usr/local/bin/adb",  // Homebrew
            "/opt/homebrew/bin/adb",  // Homebrew (Apple Silicon)
            "/usr/bin/adb",  // System default (less common)
            "~/.android-sdk/platform-tools/adb",  // Example user path
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",  // Standard Android Studio path
        ])
        return paths.map { ($0 as NSString).expandingTildeInPath }
    }()

    // MARK: - scrcpy Paths

    static let scrcpyPaths = [
        "/opt/homebrew/bin/scrcpy",
        "/usr/local/bin/scrcpy",
        "\(NSHomeDirectory())/.local/bin/scrcpy",
        "/Applications/scrcpy.app/Contents/MacOS/scrcpy",
    ]
}
