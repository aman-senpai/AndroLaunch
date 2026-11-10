//
//  FileExplorerViewModel.swift
//  AndroLaunch
//
//  Created by Aman Raj on 12/4/26.
//

import Combine
import Foundation
import SwiftUI

class FileExplorerViewModel: ObservableObject {
    let repository: any DeviceRepositoryProtocol
    let deviceID: String
    private let transferCoordinator: TransferCoordinator
    private var cancellables = Set<AnyCancellable>()
    /// Set when this view model enqueued a batch, so it only reacts to its own transfer.
    private var pendingTransferDeviceID: String?

    @Published var currentPath: String = "/sdcard"
    @Published var files: [AndroidFile] = []
    @Published var isLoading: Bool = false
    @Published var selection: Set<String> = []
    @Published var previewURL: URL?
    @Published var showHiddenFiles: Bool = false {
        didSet { refresh() }
    }
    @Published var showDeleteConfirmation: Bool = false

    var pendingDeleteCount: Int = 0

    var breadcrumbs: [(name: String, path: String)] {
        let components = currentPath.components(separatedBy: "/").filter { !$0.isEmpty }
        var crumbs: [(name: String, path: String)] = [("Internal Storage", "/sdcard")]

        var fullPath = "/sdcard"
        var foundSdcard = false

        for component in components {
            if component == "sdcard" {
                foundSdcard = true
                continue
            }
            if !foundSdcard { continue }

            fullPath += "/\(component)"
            crumbs.append((component, fullPath))
        }
        return crumbs
    }

    init(
        repository: any DeviceRepositoryProtocol, deviceID: String,
        transferCoordinator: TransferCoordinator? = nil
    ) {
        self.repository = repository
        self.deviceID = deviceID
        self.transferCoordinator = transferCoordinator ?? .shared
        observeTransfers()
        Task { @MainActor in self.refresh() }
    }

    /// Follows the shared queue so a drop keeps the existing progress spinner and
    /// surfaces per-file failures once the batch finishes.
    private func observeTransfers() {
        transferCoordinator.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                guard let self else { return }
                if isActive {
                    if self.transferCoordinator.activeDeviceID == self.deviceID {
                        self.pendingTransferDeviceID = self.deviceID
                        self.isLoading = true
                    }
                } else if self.pendingTransferDeviceID == self.deviceID {
                    self.pendingTransferDeviceID = nil
                    self.isLoading = false
                    self.refresh()
                    self.presentTransferFailures()
                }
            }
            .store(in: &cancellables)
    }

    func refresh() {
        isLoading = true
        repository.listFiles(for: deviceID, at: currentPath) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let files):
                    let filteredFiles =
                        self.showHiddenFiles
                        ? files : files.filter { !$0.name.hasPrefix(".") }
                    let validIDs = Set(filteredFiles.map { $0.id })
                    self.selection.formIntersection(validIDs)
                    self.files = filteredFiles
                case .failure(let error):
                    AlertPresenter.showWarning(message: error.localizedDescription)
                }
            }
        }
    }

    func navigateTo(path: String) {
        currentPath = path
        selection.removeAll()
        refresh()
    }

    func enter(file: AndroidFile) {
        if file.isDirectory {
            navigateTo(path: file.path)
        }
    }

    func goBack() {
        if currentPath == "/" || currentPath == "/sdcard" { return }
        let components = currentPath.components(separatedBy: "/")
        if components.count > 1 {
            let newPath = components.dropLast().joined(separator: "/")
            navigateTo(path: newPath.isEmpty ? "/" : newPath)
        }
    }

    func pushFiles(urls: [URL]) {
        guard !urls.isEmpty else { return }

        pendingTransferDeviceID = deviceID
        isLoading = true
        transferCoordinator.enqueue(files: urls, deviceID: deviceID, destination: currentPath)
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return !isDirectory.boolValue
    }

    private static func totalSize(of urls: [URL]) -> Int64 {
        urls.reduce(into: Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
    }

    /// Turns the failed items of the last batch into one quiet, actionable alert.
    private func presentTransferFailures() {
        let failures = transferCoordinator.items.compactMap { item -> String? in
            guard item.deviceID == deviceID, case .failed(let reason) = item.state,
                reason != "Cancelled"
            else { return nil }
            return "\(item.url.lastPathComponent): \(reason)"
        }
        guard !failures.isEmpty else { return }

        let deviceItems = transferCoordinator.items.filter { $0.deviceID == deviceID }
        let cancelledCount = deviceItems.filter { item in
            if case .failed(let reason) = item.state { return reason == "Cancelled" }
            return false
        }.count
        let total = deviceItems.count - cancelledCount
        let header =
            total == failures.count
            ? "\(failures.count == 1 ? "The file was" : "All \(failures.count) files were") not sent."
            : "\(failures.count) of \(total) files were not sent."
        AlertPresenter.showWarning(message: header + "\n\n" + failures.joined(separator: "\n"))
    }

    func pullFile(file: AndroidFile) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        if panel.runModal() == .OK, let url = panel.url {
            isLoading = true
            repository.pullFile(deviceID: deviceID, remotePath: file.path, localPath: url.path) {
                [weak self] result in
                Task { @MainActor in
                    self?.isLoading = false
                    if case .failure(let error) = result {
                        AlertPresenter.showWarning(message: error.localizedDescription)
                    }
                }
            }
        }
    }

    func requestDelete() {
        let selectedFiles = files.filter { selection.contains($0.id) }
        guard !selectedFiles.isEmpty else { return }
        pendingDeleteCount = selectedFiles.count
        showDeleteConfirmation = true
    }

    func confirmDelete() {
        showDeleteConfirmation = false
        let selectedFiles = files.filter { selection.contains($0.id) }
        guard !selectedFiles.isEmpty else { return }

        isLoading = true
        let group = DispatchGroup()

        for file in selectedFiles {
            group.enter()
            repository.deleteFile(deviceID: deviceID, path: file.path) { _ in
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.selection.removeAll()
            self.refresh()
        }
    }

    func showPreview() {
        guard let firstSelectedID = selection.first,
              let file = files.first(where: { $0.id == firstSelectedID }),
              !file.isDirectory
        else { return }

        let tempDir = NSTemporaryDirectory()
        let localURL = URL(fileURLWithPath: tempDir).appendingPathComponent(file.name)

        isLoading = true
        repository.pullFile(deviceID: deviceID, remotePath: file.path, localPath: localURL.path) {
            [weak self] result in
            Task { @MainActor in
                self?.isLoading = false
                if case .success = result {
                    self?.previewURL = localURL
                } else if case .failure(let error) = result {
                    AlertPresenter.showWarning(message: error.localizedDescription)
                }
            }
        }
    }
}
