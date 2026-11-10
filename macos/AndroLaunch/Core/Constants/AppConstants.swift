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

    /// A usable command-line-tools directory contains both binaries the emulator
    /// features shell out to. Anything else (a folder the user picked once, a moved
    /// SDK, an interrupted install) must not be treated as configured.
    static func isValidCmdlineToolsDirectory(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: (path as NSString).appendingPathComponent("sdkmanager"))
            && fm.isExecutableFile(atPath: (path as NSString).appendingPathComponent("avdmanager"))
    }

    /// Every `cmdline-tools` bin directory under an SDK root, best first.
    ///
    /// Android Studio installs into `cmdline-tools/latest`, but versioned folders
    /// (`17.0`, `18.1`, …) and the legacy `cmdline-tools/bin` layout are common —
    /// assuming `latest` is what produced a permanent "avdmanager not found".
    static func cmdlineToolsBinDirectories(inRoot root: String) -> [String] {
        guard !root.isEmpty else { return [] }
        let tools = (root as NSString).appendingPathComponent("cmdline-tools")
        var directories = [(tools as NSString).appendingPathComponent("latest/bin")]

        let entries =
            (try? FileManager.default.contentsOfDirectory(atPath: tools)) ?? []
        let versions =
            entries
            .filter { $0 != "latest" && !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedDescending }
        directories.append(
            contentsOf: versions.map { (tools as NSString).appendingPathComponent("\($0)/bin") })
        directories.append((tools as NSString).appendingPathComponent("bin"))
        return directories
    }

    /// Every SDK root worth looking in, including a user-configured one.
    static func candidateSDKRoots(additional: String? = nil) -> [String] {
        let home = NSHomeDirectory()
        let environment = ProcessInfo.processInfo.environment
        var roots: [String] = []
        for root in [
            additional,
            environment["ANDROID_SDK_ROOT"],
            environment["ANDROID_HOME"],
            "\(home)/Library/Android/sdk",
            "\(home)/Android/Sdk",
            "/opt/homebrew/share/android-commandlinetools",
            "/usr/local/share/android-commandlinetools",
        ] {
            guard let root, !root.isEmpty, !roots.contains(root) else { continue }
            roots.append(root)
        }
        return roots
    }

    /// Auto-detect the Android SDK command-line tools path.
    /// Returns the first directory that contains both `sdkmanager` and `avdmanager`.
    static func detectCmdlineToolsPath(additionalRoots: [String] = []) -> String? {
        for root in candidateSDKRoots() + additionalRoots {
            if let match = cmdlineToolsBinDirectories(inRoot: root)
                .first(where: isValidCmdlineToolsDirectory)
            {
                return match
            }
        }

        // Fallback: check if there's a sdkmanager in PATH and derive from that
        if let sdkmanagerInPath = findExecutableInPath(named: "sdkmanager") {
            let binDir = (sdkmanagerInPath as NSString).deletingLastPathComponent
            if isValidCmdlineToolsDirectory(binDir) {
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
