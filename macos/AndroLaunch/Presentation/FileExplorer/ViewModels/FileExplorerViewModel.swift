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
    private var cancellables = Set<AnyCancellable>()

    @Published var currentPath: String = "/sdcard"
    @Published var files: [AndroidFile] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var selection: Set<String> = []
    @Published var previewURL: URL?
    @Published var showHiddenFiles: Bool = false {
        didSet {
            DispatchQueue.main.async {
                self.refresh()
            }
        }
    }

    // Breadcrumbs support
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

    init(repository: any DeviceRepositoryProtocol, deviceID: String) {
        self.repository = repository
        self.deviceID = deviceID
        DispatchQueue.main.async {
            self.refresh()
        }
    }

    func refresh() {
        isLoading = true
        error = nil
        repository.listFiles(for: deviceID, at: currentPath) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let files):
                    let filteredFiles =
                        self?.showHiddenFiles == true
                        ? files : files.filter { !$0.name.hasPrefix(".") }
                    let validIDs = Set(filteredFiles.map { $0.id })
                    self?.selection.formIntersection(validIDs)
                    self?.files = filteredFiles
                case .failure(let error):
                    self?.error = error.localizedDescription
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
        isLoading = true
        let group = DispatchGroup()

        for url in urls {
            group.enter()
            let remotePath =
                currentPath.hasSuffix("/")
                ? "\(currentPath)\(url.lastPathComponent)"
                : "\(currentPath)/\(url.lastPathComponent)"
            repository.pushFile(deviceID: deviceID, localPath: url.path, remotePath: remotePath) {
                _ in
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.refresh()
        }
    }

    func pullFile(file: AndroidFile) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        if panel.runModal() == .OK, let url = panel.url {
            isLoading = true
            repository.pullFile(deviceID: deviceID, remotePath: file.path, localPath: url.path) {
                [weak self] result in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    if case .failure(let error) = result {
                        self?.error = error.localizedDescription
                    }
                }
            }
        }
    }

    func deleteSelected() {
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
            DispatchQueue.main.async {
                self?.isLoading = false
                if case .success = result {
                    self?.previewURL = localURL
                }
            }
        }
    }
}
