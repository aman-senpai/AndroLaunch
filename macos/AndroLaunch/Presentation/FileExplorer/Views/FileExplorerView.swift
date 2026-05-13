//
//  FileExplorerView.swift
//  AndroLaunch
//
//  Created by Aman Raj on 12/4/26.
//

import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct FileExplorerView: View {
    @StateObject var viewModel: FileExplorerViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationSplitView {
            List {
                Section("Shortcuts") {
                    ShortcutItemView(
                        name: "Internal Storage", icon: "iphone", path: "/sdcard",
                        viewModel: viewModel)
                    ShortcutItemView(
                        name: "Downloads", icon: "arrow.down.circle", path: "/sdcard/Download",
                        viewModel: viewModel)
                    ShortcutItemView(
                        name: "DCIM", icon: "photo", path: "/sdcard/DCIM", viewModel: viewModel)
                    ShortcutItemView(
                        name: "Pictures", icon: "photo.on.rectangle", path: "/sdcard/Pictures",
                        viewModel: viewModel)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("AndroExplorer")
        } detail: {
            VStack(spacing: 0) {
                // Header / Breadcrumbs
                headerView

                Divider()

                // File List
                if viewModel.isLoading && viewModel.files.isEmpty {
                    VStack {
                        ProgressView()
                        Text("Loading device files...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    fileTableView
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: viewModel.goBack) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(viewModel.currentPath == "/sdcard" || viewModel.currentPath == "/")
                    .help("Go Back")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: viewModel.refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: { viewModel.showHiddenFiles.toggle() }) {
                        Image(systemName: viewModel.showHiddenFiles ? "eye" : "eye.slash")
                    }
                    .help(viewModel.showHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: viewModel.deleteSelected) {
                        Image(systemName: "trash")
                    }
                    .disabled(viewModel.selection.isEmpty)
                    .help("Delete Selected")
                }

                ToolbarItem(placement: .status) {
                    if viewModel.isLoading {
                        ProgressView().controlSize(.small)
                            .padding(.trailing, 8)
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            let group = DispatchGroup()
            var urls: [URL] = []
            for provider in providers {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        urls.append(url)
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                if !urls.isEmpty {
                    viewModel.pushFiles(urls: urls)
                }
            }
            return true
        }
    }

    private var headerView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(viewModel.breadcrumbs.indices, id: \.self) { index in
                    let crumb = viewModel.breadcrumbs[index]
                    Button(action: { viewModel.navigateTo(path: crumb.path) }) {
                        Text(crumb.name)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                viewModel.currentPath == crumb.path
                                    ? Color.accentColor.opacity(0.1) : Color.clear
                            )
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    if index < viewModel.breadcrumbs.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private var fileTableView: some View {
        Table(viewModel.files, selection: $viewModel.selection) {
            TableColumn("Name") { file in
                FileRowView(file: file, viewModel: viewModel)
            }

            TableColumn("Size") { file in
                Text(file.formattedSize)
                    .foregroundColor(.secondary)
            }

            TableColumn("Modified") { file in
                Text(file.modificationDate ?? "--")
                    .foregroundColor(.secondary)
            }
        }
        .contextMenu(forSelectionType: String.self) { items in
            let selectedFiles = viewModel.files.filter { items.contains($0.id) }
            if selectedFiles.count == 1, let file = selectedFiles.first, !file.isDirectory {
                Button("Download to Mac...") {
                    viewModel.pullFile(file: file)
                }
            }
            if !selectedFiles.isEmpty {
                Divider()
                Button("Delete", role: .destructive) {
                    viewModel.selection = items
                    viewModel.deleteSelected()
                }
            }
        } primaryAction: { items in
            if items.count == 1, let id = items.first,
                let file = viewModel.files.first(where: { $0.id == id })
            {
                viewModel.enter(file: file)
            }
        }
        .quickLookPreview($viewModel.previewURL)
        .onKeyPress { press in
            if press.key == .space {
                viewModel.showPreview()
                return .handled
            }
            return .ignored
        }
    }

    private func fileIcon(for name: String) -> String {
        // ... (move this or keep it helper)
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "webp": return "photo"
        case "mp4", "mkv", "mov": return "video"
        case "mp3", "wav", "m4a": return "music.note"
        case "apk": return "app.badge"
        case "zip", "rar", "7z": return "doc.zipper"
        case "txt", "md": return "doc.text"
        case "pdf": return "doc.richtext"
        default: return "doc"
        }
    }
}

struct FileRowView: View {
    let file: AndroidFile
    @ObservedObject var viewModel: FileExplorerViewModel

    var body: some View {
        HStack {
            Image(systemName: file.isDirectory ? "folder.fill" : fileIcon(for: file.name))
                .foregroundColor(file.isDirectory ? .accentColor : .secondary)
                .frame(width: 20)
            Text(file.name)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDrag {
            let provider = NSItemProvider()
            let utType: UTType
            if file.isDirectory {
                utType = .folder
            } else {
                let ext = (file.name as NSString).pathExtension
                utType = UTType(filenameExtension: ext) ?? .data
            }

            provider.registerFileRepresentation(
                forTypeIdentifier: utType.identifier, visibility: .all
            ) { completion in
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
                    file.name)

                viewModel.repository.pullFile(
                    deviceID: viewModel.deviceID, remotePath: file.path, localPath: tempURL.path
                ) { _ in
                    completion(tempURL, false, nil)
                }

                return nil
            }
            return provider
        }
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "webp": return "photo"
        case "mp4", "mkv", "mov": return "video"
        case "mp3", "wav", "m4a": return "music.note"
        case "apk": return "app.badge"
        case "zip", "rar", "7z": return "doc.zipper"
        case "txt", "md": return "doc.text"
        case "pdf": return "doc.richtext"
        default: return "doc"
        }
    }
}

struct ShortcutItemView: View {
    let name: String
    let icon: String
    let path: String
    @ObservedObject var viewModel: FileExplorerViewModel

    var body: some View {
        Button(action: { viewModel.navigateTo(path: path) }) {
            Label(name, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}
