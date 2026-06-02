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
    @State private var hoveredFileID: String?

    var body: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            detailView
        }
        .frame(minWidth: 800, minHeight: 500)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let item = try? await provider.loadItem(
                        forTypeIdentifier: UTType.fileURL.identifier),
                        let data = item as? Data,
                        let url = URL(dataRepresentation: data, relativeTo: nil)
                    {
                        urls.append(url)
                    }
                }
                if !urls.isEmpty {
                    viewModel.pushFiles(urls: urls)
                }
            }
            return true
        }
        .confirmationDialog(
            "Delete \(viewModel.pendingDeleteCount) item\(viewModel.pendingDeleteCount == 1 ? "" : "s")?",
            isPresented: $viewModel.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                viewModel.confirmDelete()
            }
        }
    }

    private var sidebarView: some View {
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
    }

    private var detailView: some View {
        VStack(spacing: 0) {
            BreadcrumbView(viewModel: viewModel)
            Divider()

            if viewModel.isLoading && viewModel.files.isEmpty {
                loadingView
            } else if viewModel.files.isEmpty {
                emptyStateView
            } else {
                fileTableView
            }
        }
        .toolbar {
            FileExplorerToolbar(viewModel: viewModel)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading device files...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("Empty Folder")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
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
        .animation(.easeInOut(duration: 0.2), value: viewModel.files.map(\.id))
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
                    viewModel.requestDelete()
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
}

// MARK: - Breadcrumbs

struct BreadcrumbView: View {
    @ObservedObject var viewModel: FileExplorerViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(viewModel.breadcrumbs, id: \.path) { crumb in
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

                        if crumb.path != viewModel.breadcrumbs.last?.path {
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
            .onChange(of: viewModel.currentPath) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if let last = viewModel.breadcrumbs.last {
                        proxy.scrollTo(last.path, anchor: .trailing)
                    }
                }
            }
            .onAppear {
                if let last = viewModel.breadcrumbs.last {
                    proxy.scrollTo(last.path, anchor: .trailing)
                }
            }
        }
    }
}

// MARK: - Toolbar

struct FileExplorerToolbar: ToolbarContent {
    @ObservedObject var viewModel: FileExplorerViewModel

    var body: some ToolbarContent {
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
            Button(action: viewModel.requestDelete) {
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

// MARK: - File Row (inside Table)

struct FileRowView: View {
    let file: AndroidFile
    @ObservedObject var viewModel: FileExplorerViewModel
    @State private var isHovering = false

    var body: some View {
        HStack {
            Image(systemName: file.isDirectory ? "folder.fill" : file.fileIcon)
                .foregroundColor(file.isDirectory ? .accentColor : .secondary)
                .frame(width: 20)
            Text(file.name)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? Color.primary.opacity(0.05) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
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
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent(file.name)

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
}

// MARK: - Sidebar Shortcut

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
