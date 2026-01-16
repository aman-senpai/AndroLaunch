//
//  EnvironmentManager.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 16/1/26.
//

import Foundation

final class EnvironmentManager {
    static let shared = EnvironmentManager()
    
    private init() {}
    
    /// Resolves JAVA_HOME dynamically using /usr/libexec/java_home
    var javaHome: String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/libexec/java_home")
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                return output
            }
        } catch {
            print("[EnvironmentManager] Failed to resolve JAVA_HOME: \(error)")
        }
        return nil
    }
}
