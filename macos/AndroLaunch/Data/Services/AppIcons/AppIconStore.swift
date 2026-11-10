//
//  AppIconStore.swift
//  AndroLaunch
//
//  Real Android app icons for the Mac UI, cached in memory and on disk.
//
//  Flow: views ask for one package; the store coalesces the ask into batches of
//  24, checks the disk cache first, and only then asks the companion. Results are
//  published as `NSImage`s keyed by device + package, so switching devices never
//  shows another phone's icon for the same package name.
//
//  Disk cache: ~/Library/Application Support/AndroLaunch/AppIcons/<device>/<package>.png.
//  Icons are public app artwork, so persisting them is safe; nothing else about
//  the app is stored. A negative cache (10 min) stops repeated requests for
//  packages the phone cannot supply (uninstalled between listing and request, or
//  no icon resource), and a failed device is retried at most once a minute.
//
//  Everything asynchronous is off the main thread; @Published state is only
//  mutated on the main thread.
//

import AppKit
import Combine
import Foundation

final class AppIconStore: ObservableObject {

    static let shared = AppIconStore()

    /// `NSImage` per `deviceID|packageName`, memory-only.
    @Published private(set) var images: [String: NSImage] = [:]
    /// Last transport/decoding failure, for diagnostics (never shown as a banner).
    @Published private(set) var lastError: String?

    private let companion: CompanionClient
    private let fileManager = FileManager.default
    private let baseDirectoryOverride: URL?
    private let workQueue = DispatchQueue(
        label: "com.senpai.AndroLaunch.app-icons", qos: .utility)

    /// Devices → packages waiting for the next flush.
    private var pending: [String: Set<String>] = [:]
    private var flushScheduled = false
    /// Memory keys currently being resolved (disk read or companion request).
    private var inFlight: Set<String> = []
    /// Memory keys whose disk file has already been consulted.
    private var diskChecked: Set<String> = []
    /// Negative cache: memory key → time after which a retry is allowed.
    private var missingUntil: [String: Date] = [:]
    /// Devices that failed recently, so a missing companion is not retried per batch.
    private var failedDevices: [String: Date] = [:]

    private static let batchSize = AppIconBatches.defaultBatchSize
    private static let flushDelay: TimeInterval = 0.06
    private static let negativeCacheTTL: TimeInterval = 10 * 60
    private static let deviceRetryInterval: TimeInterval = 60

    init(companion: CompanionClient = .shared, baseDirectory: URL? = nil) {
        self.companion = companion
        self.baseDirectoryOverride = baseDirectory
    }

    // MARK: - Reading

    func cachedImage(deviceID: String, packageName: String) -> NSImage? {
        images[AppIconCacheKey.memoryKey(deviceID: deviceID, packageName: packageName)]
    }

    func cachedImage(for app: AndroidApp, deviceID: String) -> NSImage? {
        cachedImage(deviceID: deviceID, packageName: app.packageName)
    }

    var cacheRoot: URL {
        if let baseDirectoryOverride { return baseDirectoryOverride }
        let support =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support
            .appendingPathComponent("AndroLaunch", isDirectory: true)
            .appendingPathComponent("AppIcons", isDirectory: true)
    }

    func fileURL(deviceID: String, packageName: String) -> URL {
        cacheRoot.appendingPathComponent(
            AppIconCacheKey.relativePath(deviceID: deviceID, packageName: packageName),
            isDirectory: false)
    }

    // MARK: - Requests from views

    /// Convenience for app lists. Safe to call on every render/list change.
    func ensureIcons(for apps: [AndroidApp], deviceID: String) {
        ensureIcons(packages: apps.map { $0.packageName }, deviceID: deviceID)
    }

    /// Queues missing packages. Cheap: it only touches in-memory sets and schedules
    /// one flush, so a grid of 100 tiles becomes a handful of batched requests.
    func ensureIcons(packages: [String], deviceID: String) {
        guard !deviceID.isEmpty, !packages.isEmpty else { return }
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.ensureIcons(packages: packages, deviceID: deviceID)
            }
            return
        }

        let now = Date()
        var queue = pending[deviceID] ?? []
        for package in packages {
            let trimmed = package.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = AppIconCacheKey.memoryKey(deviceID: deviceID, packageName: trimmed)
            if images[key] != nil { continue }
            if inFlight.contains(key) { continue }
            if let until = missingUntil[key], until > now { continue }
            queue.insert(trimmed)
        }
        guard !queue.isEmpty else { return }
        pending[deviceID] = queue
        scheduleFlush()
    }

    /// Drops memory state and the negative cache (used when a device is
    /// disconnected or its app list changes wholesale). Disk cache is kept.
    func forgetDevice(_ deviceID: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.forgetDevice(deviceID) }
            return
        }
        let prefix = "\(deviceID)|"
        images = images.filter { !$0.key.hasPrefix(prefix) }
        missingUntil = missingUntil.filter { !$0.key.hasPrefix(prefix) }
        diskChecked = diskChecked.filter { !$0.hasPrefix(prefix) }
        failedDevices[deviceID] = nil
        pending[deviceID] = nil
    }

    /// Called by a debug/repair surface: clears memory and the disk cache.
    func clearCache() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.clearCache() }
            return
        }
        images.removeAll()
        missingUntil.removeAll()
        diskChecked.removeAll()
        inFlight.removeAll()
        pending.removeAll()
        failedDevices.removeAll()
        workQueue.async { [root = cacheRoot] in
            try? FileManager.default.removeItem(at: root)
        }
    }

    // MARK: - Flush + batching

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flushDelay) { [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        flushScheduled = false
        let snapshot = pending
        pending.removeAll()
        guard !snapshot.isEmpty else { return }

        for (deviceID, packages) in snapshot {
            guard !packages.isEmpty else { continue }
            // Split the queued set, but keep in-flight bookkeeping per batch.
            for batch in AppIconBatches.split(Array(packages), size: Self.batchSize) {
                loadBatch(deviceID: deviceID, packages: batch)
            }
        }
    }

    private func loadBatch(deviceID: String, packages: [String]) {
        let keys = Set(
            packages.map {
                AppIconCacheKey.memoryKey(deviceID: deviceID, packageName: $0)
            })
        inFlight.formUnion(keys)

        let alreadyCheckedDisk = packages.filter { package in
            diskChecked.contains(
                AppIconCacheKey.memoryKey(deviceID: deviceID, packageName: package))
        }
        let needsDiskRead = packages.filter { package in
            !diskChecked.contains(
                AppIconCacheKey.memoryKey(deviceID: deviceID, packageName: package))
        }

        guard !needsDiskRead.isEmpty else {
            requestFromCompanion(deviceID: deviceID, packages: alreadyCheckedDisk, keys: keys)
            return
        }

        workQueue.async { [weak self] in
            guard let self else { return }
            var loaded: [(String, NSImage)] = []
            for package in needsDiskRead {
                if let image = self.readIconFromDisk(deviceID: deviceID, packageName: package) {
                    loaded.append(
                        (
                            AppIconCacheKey.memoryKey(
                                deviceID: deviceID, packageName: package),
                            image
                        ))
                }
            }
            DispatchQueue.main.async {
                if !loaded.isEmpty {
                    var dictionary = self.images
                    for (key, image) in loaded {
                        dictionary[key] = image
                    }
                    self.images = dictionary
                }
                for package in needsDiskRead {
                    self.diskChecked.insert(
                        AppIconCacheKey.memoryKey(deviceID: deviceID, packageName: package))
                }
                for (key, _) in loaded {
                    self.inFlight.remove(key)
                }
                let stillMissing = alreadyCheckedDisk + needsDiskRead.filter { package in
                    self.images[
                        AppIconCacheKey.memoryKey(deviceID: deviceID, packageName: package)
                    ] == nil
                }
                guard !stillMissing.isEmpty else { return }
                self.requestFromCompanion(
                    deviceID: deviceID, packages: stillMissing, keys: keys)
            }
        }
    }

    private func requestFromCompanion(
        deviceID: String, packages: [String], keys: Set<String>
    ) {
        guard !packages.isEmpty else {
            inFlight.subtract(keys)
            return
        }
        // A device that just failed (no companion, older APK, sleep) is not
        // hammered once per batch; the SF Symbol fallback stays visible instead.
        if let failedAt = failedDevices[deviceID],
            Date().timeIntervalSince(failedAt) < Self.deviceRetryInterval
        {
            inFlight.subtract(keys)
            markMissing(packages: packages, deviceID: deviceID)
            return
        }

        companion.appIcons(packages: packages, deviceID: deviceID) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.inFlight.subtract(keys)
                switch result {
                case .success(let icons):
                    var dictionary = self.images
                    var returned = Set<String>()
                    for icon in icons {
                        guard let image = NSImage(data: icon.pngData) else { continue }
                        let key = AppIconCacheKey.memoryKey(
                            deviceID: deviceID, packageName: icon.packageName)
                        dictionary[key] = image
                        returned.insert(icon.packageName)
                        self.writeIconToDisk(icon, deviceID: deviceID)
                    }
                    self.images = dictionary
                    self.lastError = nil
                    self.failedDevices[deviceID] = nil
                    let absent = packages.filter { !returned.contains($0) }
                    self.markMissing(packages: absent, deviceID: deviceID)
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.failedDevices[deviceID] = Date()
                    self.markMissing(packages: packages, deviceID: deviceID)
                }
            }
        }
    }

    private func markMissing(packages: [String], deviceID: String) {
        let deadline = Date().addingTimeInterval(Self.negativeCacheTTL)
        for package in packages {
            missingUntil[
                AppIconCacheKey.memoryKey(deviceID: deviceID, packageName: package)] = deadline
        }
    }

    // MARK: - Disk cache

    private func readIconFromDisk(deviceID: String, packageName: String) -> NSImage? {
        let url = fileURL(deviceID: deviceID, packageName: packageName)
        guard let data = try? Data(contentsOf: url),
            !data.isEmpty,
            data.count <= AppIconPayload.maxIconBytes,
            AppIconPayload.isPNG(data)
        else { return nil }
        return NSImage(data: data)
    }

    private func writeIconToDisk(_ icon: CompanionAppIcon, deviceID: String) {
        let data = icon.pngData
        let url = fileURL(deviceID: deviceID, packageName: icon.packageName)
        workQueue.async {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                // A read-only Application Support directory only costs a reload next
                // launch; it must never surface as an icon-loading error.
            }
        }
    }
}
