//
//  FinderMirrorService.swift
//  AndroLaunch
//
//  Local Finder mirror of phone folders: pulls a bounded set of user folders over
//  ADB into Application Support, then reveals them in Finder. A stable symlink in
//  `~/AndroLaunch/<device>` makes the mirror available from the Finder sidebar.
//
//  This is explicitly **not** a system File Provider mount. A File Provider is a
//  separately signed extension target; this service ships real Finder access in
//  the current build by materializing local copies.
//

import AppKit
import Combine
import Foundation

// MARK: - Errors

struct FinderMirrorError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Service

final class FinderMirrorService: ObservableObject {
    static let shared = FinderMirrorService()

    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    /// Human progress while a scope is copied ("Copying Camera 42%…").
    @Published private(set) var progressText: String?
    @Published private(set) var lastLocation: FinderMirrorLocation?

    private let adbPathProvider: () -> String?
    private let homeDirectory: String
    private let applicationSupportOverride: String?

    private let queue = DispatchQueue(label: "com.senpai.AndroLaunch.finder-mirror", qos: .utility)
    private let stateLock = NSLock()
    private var activeProcess: Process?
    private var activeToken = UUID()
    private var lastRefreshDates: [String: Date] = [:]

    init(
        adbPath: @escaping () -> String? = { DependencyContainer.shared.adb.adbPath },
        homeDirectory: String = NSHomeDirectory(),
        applicationSupportDirectory: String? = nil
    ) {
        self.adbPathProvider = adbPath
        self.homeDirectory = homeDirectory
        self.applicationSupportOverride = applicationSupportDirectory
    }

    // MARK: - Public API

    /// Materializes a scope and reveals the scope folder in Finder.
    func open(deviceID: String, scope: FinderMirrorScope) {
        let deviceName = deviceName(for: deviceID)
        let location = FinderMirrorLogic.location(
            deviceName: deviceName, deviceID: deviceID, scope: scope,
            homeDirectory: homeDirectory,
            applicationSupportDirectory: applicationSupportOverride)

        if canReuseMirror(deviceID: deviceID, scope: scope, location: location) {
            reveal(location, select: false)
            return
        }

        refresh(deviceID: deviceID, scope: scope) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let location):
                self.reveal(location, select: false)
            case .failure:
                break  // `lastError` is already published.
            }
        }
    }

    /// Materializes a scope and selects it in Finder (the "Mount" action).
    func mount(deviceID: String, scope: FinderMirrorScope) {
        let deviceName = deviceName(for: deviceID)
        let location = FinderMirrorLogic.location(
            deviceName: deviceName, deviceID: deviceID, scope: scope,
            homeDirectory: homeDirectory,
            applicationSupportDirectory: applicationSupportOverride)

        if canReuseMirror(deviceID: deviceID, scope: scope, location: location) {
            reveal(location, select: true)
            return
        }

        refresh(deviceID: deviceID, scope: scope) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let location):
                self.reveal(location, select: true)
            case .failure:
                break
            }
        }
    }

    /// Copies one scope into the mirror without revealing it.
    func refresh(
        deviceID: String,
        scope: FinderMirrorScope,
        completion: ((Result<FinderMirrorLocation, Error>) -> Void)? = nil
    ) {
        guard let adbPath = adbPathProvider(), !adbPath.isEmpty else {
            lastError = "ADB is not available. Install Android Platform Tools first."
            completion?(.failure(FinderMirrorError(message: lastError ?? "ADB unavailable.")))
            return
        }

        let deviceName = deviceName(for: deviceID)
        let location = FinderMirrorLogic.location(
            deviceName: deviceName, deviceID: deviceID, scope: scope,
            homeDirectory: homeDirectory,
            applicationSupportDirectory: applicationSupportOverride)

        let token = UUID()
        stateLock.lock()
        activeToken = token
        stateLock.unlock()
        isRefreshing = true
        lastError = nil
        progressText = "Preparing \(scope.title)…"

        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.ensureRealDirectory(
                    FinderMirrorLogic.mirrorLibraryRoot(
                        homeDirectory: self.homeDirectory,
                        applicationSupportDirectory: self.applicationSupportOverride))
                try self.ensureRealDirectory(location.deviceDirectory)
                try self.ensureRealDirectory(location.scopeDirectory)
                guard
                    FinderMirrorLogic.isContained(
                        location.scopeDirectory,
                        within: FinderMirrorLogic.mirrorLibraryRoot(
                            homeDirectory: self.homeDirectory,
                            applicationSupportDirectory: self.applicationSupportOverride))
                else {
                    throw FinderMirrorError(
                        message: "The Finder mirror path resolved outside its library folder.")
                }

                let remotes = try self.remoteFolders(
                    adbPath: adbPath, deviceID: deviceID, scope: scope, token: token)
                guard !remotes.isEmpty else {
                    throw FinderMirrorError(
                        message: "No \(scope.title) folders were found on this phone.")
                }

                self.publishProgress("Checking \(scope.title) size…")
                let estimate = try self.estimatedBytes(
                    adbPath: adbPath, deviceID: deviceID, remotes: remotes, token: token)
                if let estimate,
                    !FinderMirrorLogic.fitsCap(estimatedBytes: estimate)
                {
                    throw FinderMirrorError(
                        message: FinderMirrorLogic.capDescription(bytes: estimate)
                            + " Open the File Explorer to browse it without copying.")
                }

                let tempDirectory = (location.deviceDirectory as NSString)
                    .appendingPathComponent(".pull-\(UUID().uuidString)")
                try self.ensureRealDirectory(tempDirectory)
                defer { try? FileManager.default.removeItem(atPath: tempDirectory) }

                try self.pull(
                    adbPath: adbPath, deviceID: deviceID, remotes: remotes,
                    into: tempDirectory, scope: scope, token: token)
                try self.install(
                    from: tempDirectory, into: location.scopeDirectory, token: token)
                self.updateSidebarLink(location)

                DispatchQueue.main.async {
                    self.isRefreshing = false
                    self.progressText = nil
                    self.lastLocation = location
                    self.lastRefreshDates[self.refreshKey(deviceID: deviceID, scope: scope)] =
                        Date()
                    completion?(.success(location))
                }
            } catch {
                let message =
                    (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                DispatchQueue.main.async {
                    self.isRefreshing = false
                    self.progressText = nil
                    self.lastError = message
                    completion?(.failure(error))
                }
            }
        }
    }

    /// Cancels an in-flight copy. Partial files are discarded by the caller's
    /// cleanup path.
    func cancelRefresh() {
        stateLock.lock()
        let process = activeProcess
        activeProcess = nil
        activeToken = UUID()
        stateLock.unlock()
        process?.terminate()
    }

    func clearErrors() {
        lastError = nil
    }

    func location(
        deviceID: String, scope: FinderMirrorScope, deviceName: String? = nil
    ) -> FinderMirrorLocation {
        FinderMirrorLogic.location(
            deviceName: deviceName ?? self.deviceName(for: deviceID),
            deviceID: deviceID, scope: scope,
            homeDirectory: homeDirectory,
            applicationSupportDirectory: applicationSupportOverride)
    }

    /// The stable Finder-sidebar link for a device, if it has been created.
    func sidebarLink(deviceID: String, deviceName: String? = nil) -> URL? {
        let folderName = FinderMirrorLogic.sanitizedDeviceFolderName(
            (deviceName ?? self.deviceName(for: deviceID)) ?? deviceID,
            fallback: deviceID)
        let link = (FinderMirrorLogic.sidebarRoot(homeDirectory: homeDirectory) as NSString)
            .appendingPathComponent(folderName)
        guard FileManager.default.fileExists(atPath: link) else { return nil }
        return URL(fileURLWithPath: link, isDirectory: true)
    }

    // MARK: - Scope resolution

    private func remoteFolders(
        adbPath: String, deviceID: String, scope: FinderMirrorScope, token: UUID
    ) throws -> [String] {
        switch scope {
        case .camera:
            let path = "/sdcard/DCIM/Camera"
            let listing = try shell(adbPath: adbPath, deviceID: deviceID, command: "ls -d \(path) 2>/dev/null")
            guard !listing.isEmpty else {
                throw FinderMirrorError(
                    message: "This phone has no Camera folder at DCIM/Camera.")
            }
            return [path]

        case .root:
            return try safeChildFolders(
                adbPath: adbPath, deviceID: deviceID, base: "/sdcard",
                minimal: true)

        case .userFiles:
            return try safeChildFolders(
                adbPath: adbPath, deviceID: deviceID, base: "/sdcard",
                minimal: false)

        case .sdCard:
            let dfOutput = try shell(adbPath: adbPath, deviceID: deviceID, command: "df -k")
            let mounts = StorageAnalyticsParsers.parseAllDFMounts(dfOutput)
            let removable = StorageAnalyticsParsers.removableMounts(from: mounts)
            guard let volume = removable.first else {
                throw FinderMirrorError(
                    message: "No SD card is mounted on this phone.")
            }
            return try safeChildFolders(
                adbPath: adbPath, deviceID: deviceID, base: volume.mountPath,
                minimal: false)
        }
    }

    /// Lists a storage root and keeps only safe, user-facing folder names.
    private func safeChildFolders(
        adbPath: String, deviceID: String, base: String, minimal: Bool
    ) throws -> [String] {
        let listing = try shell(
            adbPath: adbPath, deviceID: deviceID, command: "ls -1 \(shellQuoted(base)) 2>/dev/null")
        let entries = listing
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { FinderMirrorLogic.isSafeComponent($0) }

        let selected: [String]
        if minimal {
            selected = entries.filter { FinderMirrorSafeFolders.contains($0) }
        } else {
            // Everything visible except Android's app-data tree; hidden and
            // system-managed folders are already filtered by isSafeComponent.
            selected = entries.filter { $0 != "Android" }
        }
        return selected.map { (base as NSString).appendingPathComponent($0) }
            .sorted()
    }

    // MARK: - Size estimate

    private func estimatedBytes(
        adbPath: String, deviceID: String, remotes: [String], token: UUID
    ) throws -> Int64? {
        var total: Int64 = 0
        var found = false
        for remote in remotes {
            let output = try shell(
                adbPath: adbPath, deviceID: deviceID,
                command: "du -sk \(shellQuoted(remote)) 2>/dev/null")
            if let bytes = FinderMirrorLogic.estimatedBytes(fromDU: output) {
                total += bytes
                found = true
            }
        }
        return found ? total : nil
    }

    // MARK: - Pull

    private func pull(
        adbPath: String, deviceID: String, remotes: [String],
        into tempDirectory: String, scope: FinderMirrorScope, token: UUID
    ) throws {
        let deadline = Date().addingTimeInterval(FinderMirrorLimits.maxDuration)
        for (index, remote) in remotes.enumerated() {
            try self.checkToken(token)
            if Date() > deadline {
                throw FinderMirrorError(
                    message: "Copying \(scope.title) took too long and was cancelled. Partial files were discarded.")
            }
            publishProgress(
                "Copying \(scope.title) — \(index + 1) of \(remotes.count)…")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: adbPath)
            process.arguments = ["-s", deviceID, "pull", "-a", remote, tempDirectory]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            stateLock.lock()
            activeProcess = process
            stateLock.unlock()
            defer {
                stateLock.lock()
                if activeProcess === process { activeProcess = nil }
                stateLock.unlock()
            }

            var buffer = Data()
            let bufferLock = NSLock()
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { fileHandle in
                let chunk = fileHandle.availableData
                bufferLock.lock()
                defer { bufferLock.unlock() }
                guard !chunk.isEmpty else {
                    fileHandle.readabilityHandler = nil
                    return
                }
                buffer.append(chunk)
                if let text = String(data: chunk, encoding: .utf8),
                    let percent = FinderMirrorLogic.pullProgressPercent(from: text)
                {
                    DispatchQueue.main.async {
                        self.progressText = "Copying \(scope.title) — \(percent)%"
                    }
                }
            }

            do {
                try process.run()
            } catch {
                handle.readabilityHandler = nil
                throw FinderMirrorError(
                    message: "Could not start adb pull: \(error.localizedDescription)")
            }

            while process.isRunning, Date() < deadline {
                try self.checkToken(token)
                Thread.sleep(forTimeInterval: 0.1)
            }
            if process.isRunning {
                process.terminate()
                Thread.sleep(forTimeInterval: 0.2)
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                throw FinderMirrorError(
                    message: "Copying \(scope.title) took too long and was cancelled. Partial files were discarded.")
            }
            process.waitUntilExit()
            Thread.sleep(forTimeInterval: 0.05)
            handle.readabilityHandler = nil
            bufferLock.lock()
            buffer.append(handle.availableData)
            let output = String(data: buffer, encoding: .utf8) ?? ""
            bufferLock.unlock()
            guard process.terminationStatus == 0 else {
                let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
                throw FinderMirrorError(
                    message: detail.isEmpty
                        ? "adb pull failed while copying \(scope.title)."
                        : detail)
            }
        }
    }

    // MARK: - Install

    private func install(from tempDirectory: String, into scopeDirectory: String, token: UUID)
        throws
    {
        try checkToken(token)
        let fileManager = FileManager.default
        guard
            let entries = try? fileManager.contentsOfDirectory(atPath: tempDirectory),
            !entries.isEmpty
        else {
            throw FinderMirrorError(message: "The phone returned no files to mirror.")
        }

        // Clear the old copy. Removing each entry never follows a symlink inside
        // the copy (FileManager removes the link itself).
        if let existing = try? fileManager.contentsOfDirectory(atPath: scopeDirectory) {
            for entry in existing {
                let path = (scopeDirectory as NSString).appendingPathComponent(entry)
                try? fileManager.removeItem(atPath: path)
            }
        }

        for entry in entries {
            try checkToken(token)
            let source = (tempDirectory as NSString).appendingPathComponent(entry)
            let destination = (scopeDirectory as NSString).appendingPathComponent(entry)
            // Refuse path traversal from a hostile file name in the pull output.
            guard FinderMirrorLogic.isContained(destination, within: scopeDirectory) else {
                continue
            }
            if fileManager.fileExists(atPath: destination) {
                try? fileManager.removeItem(atPath: destination)
            }
            try fileManager.moveItem(atPath: source, toPath: destination)
        }
    }

    // MARK: - Finder integration

    private func reveal(_ location: FinderMirrorLocation, select: Bool) {
        let url = location.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            lastError = "The Finder mirror could not be opened."
            return
        }
        DispatchQueue.main.async {
            self.lastLocation = location
            if select {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// `~/AndroLaunch/<device>` → the device mirror folder, for the Finder sidebar.
    private func updateSidebarLink(_ location: FinderMirrorLocation) {
        let fileManager = FileManager.default
        let sidebarRoot = FinderMirrorLogic.sidebarRoot(homeDirectory: homeDirectory)
        do {
            try ensureRealDirectory(sidebarRoot)
            let linkPath = (sidebarRoot as NSString)
                .appendingPathComponent(location.deviceFolderName)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: linkPath, isDirectory: &isDirectory) {
                // Only replace a symlink; never delete a real folder the user made.
                let attributes = try? fileManager.attributesOfItem(atPath: linkPath)
                let isLink = (attributes?[.type] as? FileAttributeType) == .typeSymbolicLink
                guard isLink else { return }
                let existingDestination =
                    (try? fileManager.destinationOfSymbolicLink(atPath: linkPath)) ?? ""
                if (existingDestination as NSString).standardizingPath
                    == (location.deviceDirectory as NSString).standardizingPath
                {
                    return
                }
                try? fileManager.removeItem(atPath: linkPath)
            }
            try fileManager.createSymbolicLink(
                atPath: linkPath, withDestinationPath: location.deviceDirectory)
        } catch {
            // The mirror itself is still usable; the sidebar alias is a convenience.
            DispatchQueue.main.async {
                self.lastError =
                    "Finder mirror copied, but the sidebar link could not be created: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Filesystem safety

    /// Creates a directory only if every existing component is a real directory.
    /// A symlink anywhere in the destination path is refused, so a mirror can
    /// never write through a link planted in Application Support.
    private func ensureRealDirectory(_ path: String) throws {
        let fileManager = FileManager.default
        let standardized = (path as NSString).standardizingPath
        var current = "/"
        for component in standardized.split(separator: "/") {
            current = (current as NSString).appendingPathComponent(String(component))
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: current, isDirectory: &isDirectory) {
                let attributes = try? fileManager.attributesOfItem(atPath: current)
                let isLink = (attributes?[.type] as? FileAttributeType) == .typeSymbolicLink
                if isLink {
                    throw FinderMirrorError(
                        message:
                            "The Finder mirror folder \(current) is a symlink; refusing to write through it.")
                }
                guard isDirectory.boolValue else {
                    throw FinderMirrorError(
                        message: "The Finder mirror path \(current) is not a folder.")
                }
            } else {
                try fileManager.createDirectory(
                    atPath: current, withIntermediateDirectories: false)
            }
        }
    }

    // MARK: - Helpers

    private func refreshKey(deviceID: String, scope: FinderMirrorScope) -> String {
        "\(deviceID)|\(scope.rawValue)"
    }

    private func canReuseMirror(
        deviceID: String, scope: FinderMirrorScope, location: FinderMirrorLocation
    ) -> Bool {
        let fileManager = FileManager.default
        guard
            let date = lastRefreshDates[refreshKey(deviceID: deviceID, scope: scope)],
            Date().timeIntervalSince(date) < FinderMirrorLimits.refreshInterval,
            let entries = try? fileManager.contentsOfDirectory(atPath: location.scopeDirectory),
            !entries.isEmpty
        else { return false }
        return true
    }

    private func checkToken(_ token: UUID) throws {
        stateLock.lock()
        let cancelled = activeToken != token
        stateLock.unlock()
        if cancelled {
            throw FinderMirrorError(message: "The Finder mirror refresh was cancelled.")
        }
    }

    private func deviceName(for deviceID: String) -> String? {
        let devices = HubStore.shared.devices
        if let match = devices.first(where: { $0.id == deviceID }) {
            return match.name
        }
        return nil
    }

    private func publishProgress(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.progressText = text
        }
    }

    // MARK: - Bounded adb helpers

    private func shell(adbPath: String, deviceID: String, command: String) throws -> String {
        let result = try run(
            adbPath: adbPath,
            arguments: ["-s", deviceID, "shell", command],
            timeout: 12)
        guard result.status == 0 else {
            throw FinderMirrorError(
                message: "The phone did not answer the storage request.")
        }
        return result.output
    }

    private func run(
        adbPath: String, arguments: [String], timeout: TimeInterval
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var buffer = Data()
        let bufferLock = NSLock()
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fileHandle in
            let chunk = fileHandle.availableData
            bufferLock.lock()
            defer { bufferLock.unlock() }
            if chunk.isEmpty {
                fileHandle.readabilityHandler = nil
            } else {
                buffer.append(chunk)
            }
        }

        do {
            try process.run()
        } catch {
            handle.readabilityHandler = nil
            throw FinderMirrorError(
                message: "Could not run adb: \(error.localizedDescription)")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.05)
        handle.readabilityHandler = nil
        bufferLock.lock()
        buffer.append(handle.availableData)
        let output = String(data: buffer, encoding: .utf8) ?? ""
        bufferLock.unlock()
        return (process.terminationStatus, output)
    }

    private func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
