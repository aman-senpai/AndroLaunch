//
//  HomebrewService.swift
//  AndroLaunch
//

import Combine
import Foundation

// MARK: - Install Events

enum HomebrewInstallEvent {
    case progress(phase: String, outputLine: String)
    case completed(path: String)
    case failed(error: String)
}

// MARK: - Protocol

protocol HomebrewServiceProtocol {
    func checkHomebrewAvailability() -> Bool
    func checkFormulaInstalled(_ formula: String) -> String?
    func installFormula(_ formula: String) -> AnyPublisher<HomebrewInstallEvent, Never>
    func brewPrefix(for formula: String) -> String?
}

// MARK: - Service Implementation

final class HomebrewService: HomebrewServiceProtocol {

    private let brewPath: String?

    init() {
        brewPath = Self.resolveBrewPath()
    }

    // MARK: - Detection

    func checkHomebrewAvailability() -> Bool {
        return brewPath != nil
    }

    func checkFormulaInstalled(_ formula: String) -> String? {
        guard let brew = brewPath else { return nil }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: brew)
        task.arguments = ["ls", "--versions", formula]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // brew ls --versions outputs "<formula> <version>" if installed, empty if not
            if task.terminationStatus == 0 && !output.isEmpty {
                return brewPrefix(for: formula)
            }
        } catch {}

        return nil
    }

    func brewPrefix(for formula: String) -> String? {
        guard let brew = brewPath else { return nil }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: brew)
        task.arguments = ["--prefix", formula]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let prefix = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if task.terminationStatus == 0 && !prefix.isEmpty {
                return "\(prefix)/bin/\(formula == "android-platform-tools" ? "adb" : formula)"
            }
        } catch {}

        return nil
    }

    // MARK: - Installation with Streaming

    func installFormula(_ formula: String) -> AnyPublisher<HomebrewInstallEvent, Never> {
        let subject = PassthroughSubject<HomebrewInstallEvent, Never>()

        guard let brew = brewPath else {
            DispatchQueue.main.async {
                subject.send(.failed(error: "Homebrew is not installed. Install it from https://brew.sh"))
                subject.send(completion: .finished)
            }
            return subject.eraseToAnyPublisher()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: brew)
            task.arguments = ["install", formula]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            task.standardOutput = stdoutPipe
            task.standardError = stderrPipe

            // Read stderr line-by-line for progress (brew outputs progress to stderr)
            var accumulatedError = ""
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard data.count > 0, let chunk = String(data: data, encoding: .utf8) else { return }
                accumulatedError += chunk

                let phase = Self.parsePhase(from: chunk)
                DispatchQueue.main.async {
                    subject.send(.progress(phase: phase, outputLine: chunk.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }

            // Also read stdout
            var accumulatedOutput = ""
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard data.count > 0, let chunk = String(data: data, encoding: .utf8) else { return }
                accumulatedOutput += chunk
            }

            do {
                try task.run()
                task.waitUntilExit()

                // Clean up handlers
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                stdoutPipe.fileHandleForReading.readabilityHandler = nil

                DispatchQueue.main.async {
                    if task.terminationStatus == 0 {
                        let prefix = self.brewPrefix(for: formula)
                        let binaryName = formula == "android-platform-tools" ? "adb" : formula
                        let resolvedPath = prefix ?? "/opt/homebrew/bin/\(binaryName)"
                        subject.send(.completed(path: resolvedPath))
                    } else {
                        let errorMessage = Self.extractError(from: accumulatedError + accumulatedOutput)
                        subject.send(.failed(error: errorMessage))
                    }
                    subject.send(completion: .finished)
                }
            } catch {
                DispatchQueue.main.async {
                    subject.send(.failed(error: error.localizedDescription))
                    subject.send(completion: .finished)
                }
            }
        }

        return subject.eraseToAnyPublisher()
    }

    // MARK: - Private Helpers

    private static func resolveBrewPath() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "which brew 2>/dev/null"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {}

        // Fallback: check common paths directly
        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func parsePhase(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("==> Downloading") || trimmed.lowercased().contains("downloading") {
            return "Downloading"
        } else if trimmed.contains("==> Fetching") || trimmed.lowercased().contains("fetching") {
            return "Fetching"
        } else if trimmed.contains("==> Installing") || trimmed.lowercased().contains("installing") {
            return "Installing"
        } else if trimmed.contains("==> Pouring") || trimmed.lowercased().contains("pouring") {
            return "Installing"
        } else if trimmed.contains("==> Linking") || trimmed.lowercased().contains("linking") {
            return "Linking"
        } else if trimmed.hasPrefix("🍺") || trimmed.hasPrefix("==> Summary") {
            return "Finalizing"
        } else if trimmed.contains("==>") {
            return "Preparing"
        }
        return "Working"
    }

    private static func extractError(from output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("error:") {
                return trimmed
            }
        }
        if let last = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return last.trimmingCharacters(in: .whitespaces)
        }
        return "Installation failed with unknown error."
    }
}
