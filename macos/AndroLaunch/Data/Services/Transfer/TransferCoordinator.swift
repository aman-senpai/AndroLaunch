//
//  TransferCoordinator.swift
//  AndroLaunch
//
//  The one serialized file-transfer queue. Drops from the file explorer, the
//  "Send Files to Device…" menu row and the Finder service all enqueue here, so
//  a push starts immediately without opening the browser and one device never
//  receives two pushes at the same time.
//

import Combine
import Foundation
import UserNotifications

/// State of a single file inside a transfer batch.
enum TransferItemState: Equatable {
    case pending
    case running
    case done
    case failed(reason: String)
}

/// One local file queued for `adb push`.
struct TransferItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let deviceID: String
    let remotePath: String
    var state: TransferItemState

    init(
        id: UUID = UUID(), url: URL, deviceID: String, remotePath: String,
        state: TransferItemState = .pending
    ) {
        self.id = id
        self.url = url
        self.deviceID = deviceID
        self.remotePath = remotePath
        self.state = state
    }
}

/// Runs a batch of `adb push` operations serially, publishing per-file progress.
///
/// Work is orchestrated on the main queue but the pushes themselves are async in
/// `DeviceRepositoryProtocol`, so enqueueing never blocks the caller.
final class TransferCoordinator: ObservableObject {
    static let shared = TransferCoordinator(repository: DependencyContainer.shared.deviceRepository)

    /// Files of the current batch, in queue order.
    @Published private(set) var items: [TransferItem] = []
    /// True while a batch still has files waiting or in flight.
    @Published private(set) var isActive = false
    /// Last per-file failure, for callers that surface errors.
    @Published private(set) var lastError: String?
    /// Device ID the running batch was started for, if any.
    @Published private(set) var activeDeviceID: String?

    /// Number of files of the current batch that reached the phone.
    var completed: Int { items.filter { $0.state == .done }.count }
    /// Number of files that failed (including directories and cancellations).
    var failedCount: Int {
        items.filter {
            if case .failed = $0.state { return true }
            return false
        }.count
    }
    /// Size of the current batch.
    var total: Int { items.count }

    private let repository: any DeviceRepositoryProtocol
    private let deviceNameProvider: (String) -> String?
    private var isCancelled = false
    private var didRequestNotificationAuthorization = false

    /// - Parameter deviceNameProvider: Resolves a user-facing device name for the
    ///   completion notification. Defaults to the connected-device list.
    init(
        repository: any DeviceRepositoryProtocol,
        deviceNameProvider: ((String) -> String?)? = nil
    ) {
        self.repository = repository
        self.deviceNameProvider =
            deviceNameProvider ?? { deviceID in
                DependencyContainer.shared.menuViewModel.devices
                    .first(where: { $0.id == deviceID })?.name
            }
    }

    // MARK: - Public API

    /// Queues `files` for the device, pushing them one at a time.
    ///
    /// If a batch is already running the files join that batch, so the pushes
    /// stay serialized. Safe to call from any queue.
    func enqueue(files: [URL], deviceID: String, destination: String = "/sdcard/Download") {
        guard !files.isEmpty else { return }

        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.enqueue(files: files, deviceID: deviceID, destination: destination)
            }
            return
        }

        // Settings → Devices → Ignore system files. Filtering happens before the
        // queue so a batch of only metadata files does not produce a transfer UI.
        let filesToSend =
            AppPreferences.shared.ignoreSystemFiles
            ? files.filter { !AppPreferences.isSystemMetadataFile($0) }
            : files
        guard !filesToSend.isEmpty else { return }

        let queuedItems = filesToSend.map { url in
            TransferItem(
                url: url,
                deviceID: deviceID,
                remotePath: Self.remotePath(destination: destination, fileName: url.lastPathComponent)
            )
        }

        if isActive {
            items.append(contentsOf: queuedItems)
            if isCancelled {
                // New work revives a batch that was being cancelled.
                isCancelled = false
            }
            return
        }

        items = queuedItems
        activeDeviceID = deviceID
        lastError = nil
        isCancelled = false
        isActive = true
        processNextItem()
    }

    /// Stops the current batch after the file that is already pushing finishes.
    /// Remaining files are marked failed with "Cancelled"; no notification is posted.
    func cancel() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.cancel() }
            return
        }
        guard isActive else { return }

        isCancelled = true
        failPending(reason: "Cancelled")
        if !items.contains(where: { $0.state == .running }) {
            finishBatch()
        }
    }

    /// Progress for one device while it has queued or running files, nil otherwise.
    func progress(for deviceID: String) -> (completed: Int, total: Int)? {
        guard isActive else { return nil }
        let deviceItems = items.filter { $0.deviceID == deviceID }
        guard
            deviceItems.contains(where: {
                $0.state == .pending || $0.state == .running
            })
        else { return nil }
        return (deviceItems.filter { $0.state == .done }.count, deviceItems.count)
    }

    // MARK: - Serial execution

    private func processNextItem() {
        guard isActive, !isCancelled else {
            finishBatch()
            return
        }
        guard let index = items.firstIndex(where: { $0.state == .pending }) else {
            finishBatch()
            return
        }

        if let reason = Self.validationFailureReason(for: items[index].url) {
            items[index].state = .failed(reason: reason)
            lastError = reason
            continueOnMain()
            return
        }

        let item = items[index]
        items[index].state = .running
        repository.pushFile(
            deviceID: item.deviceID, localPath: item.url.path, remotePath: item.remotePath
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.complete(itemID: item.id, result: result)
            }
        }
    }

    private func complete(itemID: UUID, result: Result<Void, Error>) {
        guard isActive, let index = items.firstIndex(where: { $0.id == itemID }) else { return }

        switch result {
        case .success:
            items[index].state = .done
        case .failure(let error):
            let reason = Self.failureMessage(for: error)
            items[index].state = .failed(reason: reason)
            lastError = reason
        }

        if isCancelled {
            failPending(reason: "Cancelled")
            finishBatch()
            return
        }
        processNextItem()
    }

    private func failPending(reason: String) {
        for index in items.indices where items[index].state == .pending {
            items[index].state = .failed(reason: reason)
        }
    }

    private func finishBatch() {
        guard isActive else { return }

        let wasCancelled = isCancelled
        let summary = wasCancelled ? nil : batchSummary()
        isActive = false
        activeDeviceID = nil
        isCancelled = false

        if let summary {
            postNotification(body: summary)
        }
    }

    /// Hop through the main queue so a synchronously-failing repository cannot
    /// grow the stack across a long batch.
    private func continueOnMain() {
        DispatchQueue.main.async { [weak self] in
            self?.processNextItem()
        }
    }

    // MARK: - Completion notification

    private func batchSummary() -> String {
        let total = items.count
        let sent = completed
        let deviceIDs = Set(items.map { $0.deviceID })

        if sent == total {
            let noun = total == 1 ? "file" : "files"
            if deviceIDs.count == 1, let deviceID = deviceIDs.first {
                return "\(total) \(noun) sent to \(deviceDisplayName(for: deviceID))"
            }
            return "\(total) \(noun) sent"
        }
        return "\(sent) of \(total) files sent"
    }

    private func deviceDisplayName(for deviceID: String) -> String {
        if let name = deviceNameProvider(deviceID)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
        {
            return name
        }
        return "Android device"
    }

    private func postNotification(body: String) {
        guard AppPreferences.shared.isAlertEnabled(.fileIssues) else { return }
        let center = UNUserNotificationCenter.current()
        let deliver = {
            let content = UNMutableNotificationContent()
            content.title = "AndroLaunch"
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }

        guard !didRequestNotificationAuthorization else {
            deliver()
            return
        }
        didRequestNotificationAuthorization = true
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async(execute: deliver)
        }
    }

    // MARK: - Path / validation helpers

    /// Builds `<destination>/<fileName>` and tolerates a destination without a
    /// leading or with a trailing slash.
    private static func remotePath(destination: String, fileName: String) -> String {
        let base = destination.hasSuffix("/") ? String(destination.dropLast()) : destination
        guard !base.isEmpty else { return "/\(fileName)" }
        return "\(base)/\(fileName)"
    }

    /// Directories cannot go through the current `pushFile` signature, so they are
    /// rejected per item with a readable reason instead of being silently skipped.
    private static func validationFailureReason(for url: URL) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return "File not found — it may have been moved or deleted"
        }
        if isDirectory.boolValue {
            return "Folders are not supported yet — select files"
        }
        return nil
    }

    private static func failureMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Transfer failed" : message
    }
}
