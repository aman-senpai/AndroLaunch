//
//  StorageService.swift
//  AndroLaunch
//
//  Phone storage analytics: volumes, category breakdown and folder drill-down.
//
//  Sources, in order:
//   1. `adb shell df -k` — exact capacity for the internal volume (/data) and any
//      removable volume mounted under /storage (emulated storage is part of /data
//      and is excluded).
//   2. `adb shell du -sk <root>/*` — top-level folder sizes on shared storage and
//      on each removable volume. Missing folders are marked partial, never zero.
//   3. `adb shell dumpsys diskstats` — Apps / cache / system sizes when the phone
//      exposes them. Without it, Apps is folded into System & Others and the card
//      says the split is partial.
//   4. `adb shell content query` against MediaStore for the largest media files.
//
//  Every shell read has a deadline and a cancellable token; a partial answer is
//  labelled as partial. Nothing here writes to the phone.
//

import Combine
import Foundation

// MARK: - Service

final class StorageService: ObservableObject {

    static let shared = StorageService()

    @Published private(set) var snapshot: StorageSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    /// Folder drill-down state for the analytics window.
    @Published private(set) var folderDetail: StorageFolderDetail?
    @Published private(set) var isLoadingFolderDetail = false
    @Published private(set) var folderDetailError: String?

    private let companion: CompanionClient
    private var loadToken = UUID()
    private var detailToken = UUID()

    private static let sharedRoot = "/storage/emulated/0"
    private static let dfTimeout: TimeInterval = 6
    private static let statsTimeout: TimeInterval = 8
    private static let duTimeout: TimeInterval = 14
    private static let removableDuTimeout: TimeInterval = 10
    private static let mediaQueryTimeout: TimeInterval = 10
    private static let folderTimeout: TimeInterval = 12
    private static let largestMediaFloorBytes: Int64 = 10 * 1024 * 1024
    private static let maxRemovableVolumesToScan = 2

    init(companion: CompanionClient = .shared) {
        self.companion = companion
    }

    // MARK: - Loading

    /// Loads a fresh breakdown. Repeated calls collapse into the newest request.
    func load(deviceID: String) {
        let token = UUID()
        loadToken = token
        isLoading = true
        lastError = nil
        folderDetail = nil
        folderDetailError = nil
        if snapshot?.deviceID != deviceID { snapshot = nil }

        runADBShell(deviceID: deviceID, command: "df -k", timeout: Self.dfTimeout) {
            [weak self] output in
            guard let self, self.loadToken == token else { return }
            let mounts = StorageAnalyticsParsers.parseAllDFMounts(output)
            if let internalMount = StorageAnalyticsParsers.internalMount(from: mounts) {
                let removable = StorageAnalyticsParsers.removableMounts(from: mounts)
                self.collect(
                    deviceID: deviceID, token: token, internalMount: internalMount,
                    removableMounts: removable)
                return
            }
            // Some OEM builds need the explicit path.
            self.runADBShell(
                deviceID: deviceID, command: "df -k /data", timeout: Self.dfTimeout
            ) { [weak self] retryOutput in
                guard let self, self.loadToken == token else { return }
                let retryMounts = StorageAnalyticsParsers.parseAllDFMounts(retryOutput)
                guard let internalMount = StorageAnalyticsParsers.internalMount(from: retryMounts)
                else {
                    // Last resort: the companion's StatFs numbers.
                    self.loadFromCompanion(deviceID: deviceID, token: token)
                    return
                }
                self.collect(
                    deviceID: deviceID, token: token, internalMount: internalMount,
                    removableMounts: StorageAnalyticsParsers.removableMounts(from: mounts))
            }
        }
    }

    func reset() {
        loadToken = UUID()
        detailToken = UUID()
        snapshot = nil
        isLoading = false
        lastError = nil
        folderDetail = nil
        folderDetailError = nil
        isLoadingFolderDetail = false
    }

    // MARK: - Folder drill-down

    /// Lists the immediate children of a folder with their sizes. Used by the
    /// analytics window when the user taps a folder.
    func loadChildren(deviceID: String, path: String, title: String) {
        let token = UUID()
        detailToken = token
        isLoadingFolderDetail = true
        folderDetailError = nil

        let safePath = path.hasPrefix("/") ? path : "/" + path
        let command = "du -sk \(shellQuoted(safePath))/* 2>/dev/null"
        runADBShell(deviceID: deviceID, command: command, timeout: Self.folderTimeout) {
            [weak self] output in
            guard let self, self.detailToken == token else { return }
            self.isLoadingFolderDetail = false
            let folders = StorageParsers.parseDU(output)
            if folders.isEmpty {
                self.folderDetail = nil
                self.folderDetailError =
                    "Android returned no readable entries for \(title). App-private folders are not exposed to adb."
                return
            }
            self.folderDetail = StorageFolderDetail(
                path: safePath,
                title: title,
                folders: folders,
                isPartial: false)
        }
    }

    func clearFolderDetail() {
        detailToken = UUID()
        folderDetail = nil
        folderDetailError = nil
        isLoadingFolderDetail = false
    }

    // MARK: - Collection

    /// Runs the independent probes concurrently, then assembles one snapshot.
    private func collect(
        deviceID: String,
        token: UUID,
        internalMount: StorageAnalyticsParsers.DFMount,
        removableMounts: [StorageAnalyticsParsers.DFMount]
    ) {
        let group = DispatchGroup()
        var sharedFolders: [StorageFolder]?
        var diskStats: StorageAnalyticsParsers.DiskStats?
        var largestItems: [StorageItem] = []
        var removableFolders: [String: [StorageFolder]] = [:]
        let scannedRemovable = Array(removableMounts.prefix(Self.maxRemovableVolumesToScan))

        group.enter()
        scanFolders(deviceID: deviceID, root: Self.sharedRoot, timeout: Self.duTimeout) {
            folders in
            sharedFolders = folders
            group.leave()
        }

        group.enter()
        runADBShell(
            deviceID: deviceID, command: "dumpsys diskstats", timeout: Self.statsTimeout
        ) { output in
            diskStats = StorageAnalyticsParsers.parseDiskStats(output)
            group.leave()
        }

        group.enter()
        loadLargestMedia(deviceID: deviceID) { items in
            largestItems = items
            group.leave()
        }

        for mount in scannedRemovable {
            group.enter()
            scanFolders(deviceID: deviceID, root: mount.mountPath, timeout: Self.removableDuTimeout)
            { folders in
                if let folders { removableFolders[mount.mountPath] = folders }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self, self.loadToken == token else { return }
            self.finish(
                deviceID: deviceID,
                internalMount: internalMount,
                removableMounts: removableMounts,
                scannedRemovable: scannedRemovable,
                sharedFolders: sharedFolders,
                removableFolders: removableFolders,
                diskStats: diskStats,
                largestItems: largestItems)
        }
    }

    private func finish(
        deviceID: String,
        internalMount: StorageAnalyticsParsers.DFMount,
        removableMounts: [StorageAnalyticsParsers.DFMount],
        scannedRemovable: [StorageAnalyticsParsers.DFMount],
        sharedFolders: [StorageFolder]?,
        removableFolders: [String: [StorageFolder]],
        diskStats: StorageAnalyticsParsers.DiskStats?,
        largestItems: [StorageItem]
    ) {
        var partialReasons: [String] = []
        let userFilesBytes = sharedFolders.map(StorageAnalyticsParsers.sumFolders)
        if sharedFolders == nil {
            partialReasons.append(
                "Shared-storage folder sizes are partial: Android did not expose the folder tree to adb."
            )
        }
        if diskStats?.appsTotal == nil {
            partialReasons.append(
                "Apps could not be measured separately; its space is included in System & Others."
            )
        }

        let internalCategories = StorageAnalyticsParsers.computeInternalCategories(
            usedBytes: internalMount.usedBytes,
            appsBytes: diskStats?.appsTotal,
            userFilesBytes: userFilesBytes,
            userFilesIsPartial: sharedFolders == nil)
        let internalPartial =
            sharedFolders == nil || diskStats?.appsTotal == nil
            || internalCategories.contains { $0.role == .system && $0.isPartial }
        let internalVolume = StorageVolume(
            id: "internal-\(internalMount.mountPath)",
            kind: .internalStorage,
            title: "Internal storage",
            mountPath: internalMount.mountPath,
            totalBytes: internalMount.totalBytes,
            usedBytes: internalMount.usedBytes,
            freeBytes: internalMount.freeBytes,
            categories: internalCategories,
            folders: sharedFolders ?? [],
            isPartial: internalPartial)

        let sharedStorage = StorageVolume(
            id: "shared-\(Self.sharedRoot)",
            kind: .sharedStorage,
            title: "Shared storage",
            mountPath: Self.sharedRoot,
            totalBytes: 0,
            usedBytes: userFilesBytes ?? 0,
            freeBytes: 0,
            categories: [
                StorageCategory(
                    role: .userFiles, bytes: userFilesBytes ?? 0,
                    isPartial: sharedFolders == nil)
            ],
            folders: sharedFolders ?? [],
            isPartial: sharedFolders == nil)

        var removableVolumes: [StorageVolume] = []
        for (index, mount) in removableMounts.enumerated() {
            let folders = removableFolders[mount.mountPath]
            if folders == nil {
                partialReasons.append(
                    "SD-card folder sizes are partial on \(mount.mountPath)."
                )
            }
            // Only the first few volumes were measured to keep the scan bounded.
            if index >= scannedRemovable.count {
                partialReasons.append(
                    "Additional removable volumes beyond the first two were not scanned."
                )
            }
            let userBytes = folders.map(StorageAnalyticsParsers.sumFolders)
            let categories = StorageAnalyticsParsers.computeRemovableCategories(
                usedBytes: mount.usedBytes,
                userFilesBytes: userBytes,
                userFilesIsPartial: folders == nil)
            removableVolumes.append(
                StorageVolume(
                    id: "removable-\(mount.mountPath)",
                    kind: .removable,
                    title: removableVolumes.isEmpty ? "SD card" : "SD card \(index + 1)",
                    mountPath: mount.mountPath,
                    totalBytes: mount.totalBytes,
                    usedBytes: mount.usedBytes,
                    freeBytes: mount.freeBytes,
                    categories: categories,
                    folders: folders ?? [],
                    isPartial: folders == nil))
        }

        let folderListComplete =
            sharedFolders != nil
            && scannedRemovable.allSatisfy { removableFolders[$0.mountPath] != nil }

        let snapshot = StorageSnapshot(
            deviceID: deviceID,
            totalBytes: internalMount.totalBytes,
            usedBytes: internalMount.usedBytes,
            freeBytes: internalMount.freeBytes,
            folders: sharedFolders ?? [],
            largestItems: largestItems,
            scannedAt: Date(),
            source: .adb,
            folderListComplete: folderListComplete,
            internalVolume: internalVolume,
            sharedStorage: sharedStorage,
            removableVolumes: removableVolumes,
            partialReasons: partialReasons)

        self.snapshot = snapshot
        self.isLoading = false
    }

    /// StatFs fallback when `df` is unavailable on the device.
    private func loadFromCompanion(deviceID: String, token: UUID) {
        companion.storageInfo(deviceID: deviceID) { [weak self] result in
            guard let self, self.loadToken == token else { return }
            switch result {
            case .success(let state) where state.totalBytes > 0:
                let folders = state.folders.map { StorageFolder(name: $0.name, bytes: $0.bytes) }
                self.scanFolders(deviceID: deviceID, root: Self.sharedRoot, timeout: Self.duTimeout)
                { adbFolders in
                    guard self.loadToken == token else { return }
                    let resolved = adbFolders ?? folders
                    let partial = adbFolders == nil
                    let categories = StorageAnalyticsParsers.computeInternalCategories(
                        usedBytes: state.usedBytes,
                        appsBytes: nil,
                        userFilesBytes: StorageAnalyticsParsers.sumFolders(resolved),
                        userFilesIsPartial: partial)
                    let volume = StorageVolume(
                        id: "internal-\(state.path)",
                        kind: .internalStorage,
                        title: "Internal storage",
                        mountPath: state.path,
                        totalBytes: state.totalBytes,
                        usedBytes: state.usedBytes,
                        freeBytes: state.freeBytes,
                        categories: categories,
                        folders: resolved,
                        isPartial: true)
                    self.snapshot = StorageSnapshot(
                        deviceID: deviceID,
                        totalBytes: state.totalBytes,
                        usedBytes: state.usedBytes,
                        freeBytes: state.freeBytes,
                        folders: resolved,
                        largestItems: [],
                        scannedAt: Date(),
                        source: .companion,
                        folderListComplete: false,
                        internalVolume: volume,
                        sharedStorage: nil,
                        removableVolumes: [],
                        partialReasons: [
                            "Capacity comes from the companion; app sizes are not split."
                        ])
                    self.isLoading = false
                }
            case .success:
                self.isLoading = false
                self.lastError = "Storage could not be read from this device."
            case .failure(let error):
                self.isLoading = false
                self.lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Probes

    private func scanFolders(
        deviceID: String,
        root: String,
        timeout: TimeInterval,
        completion: @escaping ([StorageFolder]?) -> Void
    ) {
        // `adb shell` hands the string to the device sh, which expands the glob.
        let command = "du -sk \(shellQuoted(root))/* 2>/dev/null"
        runADBShell(deviceID: deviceID, command: command, timeout: timeout) { output in
            guard let output, !output.isEmpty else {
                completion(nil)
                return
            }
            let folders = StorageParsers.parseDU(output)
            completion(folders.isEmpty ? nil : folders)
        }
    }

    private func loadLargestMedia(
        deviceID: String, completion: @escaping ([StorageItem]) -> Void
    ) {
        let floor = Self.largestMediaFloorBytes
        let command =
            "content query --uri content://media/external/file "
            + "--projection _display_name,_size "
            + "--where '_size>\(floor)' --sort '_size DESC'"
        runADBShell(deviceID: deviceID, command: command, timeout: Self.mediaQueryTimeout) {
            output in
            guard let output, !output.isEmpty else {
                completion([])
                return
            }
            completion(StorageParsers.parseMediaQuery(output, limit: 8))
        }
    }

    // MARK: - Bounded adb shell

    /// Runs one adb shell command on a utility queue and kills it after `timeout`.
    /// Output is drained concurrently so a chatty command cannot fill the pipe.
    /// Completions always arrive on the main thread.
    private func runADBShell(
        deviceID: String,
        command: String,
        timeout: TimeInterval,
        completion: @escaping (String?) -> Void
    ) {
        guard let adbPath = DependencyContainer.shared.adb.adbPath else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: adbPath)
            process.arguments = ["-s", deviceID, "shell", command]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

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
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            let timedOut = process.isRunning
            if timedOut {
                process.terminate()
                Thread.sleep(forTimeInterval: 0.2)
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
            Thread.sleep(forTimeInterval: 0.05)
            bufferLock.lock()
            handle.readabilityHandler = nil
            buffer.append(handle.availableData)
            let collected = buffer
            bufferLock.unlock()

            let text = String(data: collected, encoding: .utf8)
            DispatchQueue.main.async {
                completion(timedOut && (text ?? "").isEmpty ? nil : text)
            }
        }
    }

    /// Single-quotes a device path so spaces and shell metacharacters are safe;
    /// the trailing glob stays unquoted so the device shell expands it.
    private func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
