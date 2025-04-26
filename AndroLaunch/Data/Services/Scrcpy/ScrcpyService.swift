//
//  ScrcpyService.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import Foundation
import Combine

final class ScrcpyService: ScrcpyServiceProtocol {
    private var scrcpyPath: String?
    private var runningProcesses: [String: Process] = [:]
    let error = PassthroughSubject<String?, Never>()

    // Path discovery for scrcpy
    private func findScrcpyPath() -> String? {
        let paths = [
            "/opt/homebrew/bin/scrcpy",
            "/usr/local/bin/scrcpy",
            "\(NSHomeDirectory())/.local/bin/scrcpy",
            "/Applications/scrcpy.app/Contents/MacOS/scrcpy"
        ]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    func mirrorDevice(deviceID: String, adbPath: String?) {
        guard let scrcpyPath = findScrcpyPath() else {
            error.send("SCRCPY not installed. Use `brew install scrcpy`.")
            return
        }
    }

    func launchApp(packageID: String, deviceID: String, adbPath: String?) {
        guard let scrcpyPath = findScrcpyPath() else {
            error.send("SCRCPY not installed. Use `brew install scrcpy`.")
            return
        }
    }
}
