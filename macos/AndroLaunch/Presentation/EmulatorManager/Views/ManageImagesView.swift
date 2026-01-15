//
//  ManageImagesView.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 16/1/26.
//

import SwiftUI

struct ManageImagesView: View {
    @ObservedObject var viewModel: EmulatorManagerViewModel
    
    @State private var imagesToDelete: Set<String> = []
    @State private var imageSearchText = ""
    
    var body: some View {
        let filteredImages = viewModel.availableImages.filter { image in
            imageSearchText.isEmpty ||
            image.description.localizedCaseInsensitiveContains(imageSearchText) ||
            image.id.localizedCaseInsensitiveContains(imageSearchText)
        }
        
        // Items currently downloading should appear in the "Installed" section
        let downloadingIds = Set(viewModel.downloadProgress.keys)
        let installedImages = filteredImages.filter { $0.isDownloaded || downloadingIds.contains($0.id) }
        
        // Removed already installed/downloading from "Available"
        let availableDownloads = filteredImages.filter { !$0.isDownloaded && !downloadingIds.contains($0.id) }
        
        return VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search images...", text: $imageSearchText)
                    .textFieldStyle(.plain)
                if !imageSearchText.isEmpty {
                    Button(action: { imageSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 5)

            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if filteredImages.isEmpty && !viewModel.isLoadingImages {
                        emptyStateView(
                            icon: imageSearchText.isEmpty ? "externaldrive.badge.questionmark" : "magnifyingglass",
                            title: imageSearchText.isEmpty ? "No Images Found" : "No Matches",
                            subtitle: imageSearchText.isEmpty ? "Check your Android SDK path and click Refresh." : "No images match your search criteria."
                        )
                        .padding(.top, 80)
                    }
                    
                    if !installedImages.isEmpty {
                        Section(header: sectionHeader("Installed Images")) {
                            ForEach(installedImages) { image in
                                manageImageRow(image, isDeleteRow: true)
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                    
                    if !availableDownloads.isEmpty {
                        Section(header: sectionHeader("Available for Download")) {
                            ForEach(availableDownloads) { image in
                                manageImageRow(image, isDeleteRow: false)
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                }
            }
            .id(UUID()) // Force redraw if layout gets stuck, purely experimental but safest for stubborn UI
            
            // Action Bar
            if !viewModel.selectedImageIds.isEmpty || !imagesToDelete.isEmpty {
                actionBar
            }
        }
        .overlay {
            if viewModel.isLoadingImages {
                loadingOverlay("Loading images...")
            }
        }
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func manageImageRow(_ image: SystemImage, isDeleteRow: Bool) -> some View {
        let isDownloading = viewModel.downloadProgress[image.id] != nil
        
        return HStack(spacing: 16) {
            // Selection checkbox or Cancel button
            if isDownloading {
                Button(action: {
                    // Call cancel on VM
                    viewModel.cancelDownload(image.id)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Cancel download")
            } else if isDeleteRow {
                Toggle("", isOn: Binding(
                    get: { imagesToDelete.contains(image.id) },
                    set: { isSelected in
                        if isSelected {
                            imagesToDelete.insert(image.id)
                        } else {
                            imagesToDelete.remove(image.id)
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .disabled(!viewModel.selectedImageIds.isEmpty)
            } else {
                Toggle("", isOn: Binding(
                    get: { viewModel.selectedImageIds.contains(image.id) },
                    set: { isSelected in
                        if isSelected {
                            viewModel.selectedImageIds.insert(image.id)
                        } else {
                            viewModel.selectedImageIds.remove(image.id)
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .disabled(image.isDownloaded || !imagesToDelete.isEmpty)
                .opacity(image.isDownloaded ? 0.4 : 1.0)
            }
            
            // Icon
            Image(systemName: image.isDownloaded ? "internaldrive.fill" : "icloud.and.arrow.down")
                .font(.title2)
                .foregroundColor(image.isDownloaded ? .green : .secondary)
                .frame(width: 30)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(image.description)
                    .font(.body)
                    .fontWeight(.medium)
                Text(image.id)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            // Status
            if image.isDownloaded {
                VStack(alignment: .trailing, spacing: 2) {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    if let size = image.sizeBytes {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else if let progress = viewModel.downloadProgress[image.id] {
                if progress > 0 {
                    HStack(spacing: 8) {
                        ProgressView(value: progress)
                            .frame(width: 100)
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                } else {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.8)
                        Text("Downloading...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Not installed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    private var actionBar: some View {
        HStack(spacing: 16) {
            if !imagesToDelete.isEmpty {
                Text("\(imagesToDelete.count) to delete")
                    .font(.callout)
                    .foregroundColor(.red)
                
                Button(action: {
                    viewModel.deleteSelectedImages(imagesToDelete)
                    imagesToDelete.removeAll()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                        Text("Delete Selected")
                    }
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else if !viewModel.selectedImageIds.isEmpty {
                Text("\(viewModel.selectedImageIds.count) to download")
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                Button(action: { viewModel.downloadSelected() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text("Download Selected")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.05))
    }
    
    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title)
                .font(.title3)
                .fontWeight(.medium)
            Text(subtitle)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 350)
        .padding()
    }
    
    private func loadingOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.02))
    }
}
