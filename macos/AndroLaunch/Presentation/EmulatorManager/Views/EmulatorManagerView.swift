//
//  EmulatorManagerView.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 16/1/26.
//

import SwiftUI

// MARK: - Sidebar Navigation Item

private enum SidebarItem: String, Identifiable, CaseIterable {
    case myDevices = "My Devices"
    case systemImages = "System Images"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .myDevices: return "iphone.gen3"
        case .systemImages: return "square.and.arrow.down"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - Resolution Preset

enum ResolutionPreset: String, CaseIterable, Identifiable {
    case deviceDefault = "Device Default"
    case res360p = "360p"
    case res480p = "480p"
    case res540p = "540p"
    case res720p = "720p"
    case res900p = "900p"
    case res1080p = "1080p"
    case res1440p = "1440p"
    case res4k = "4K"
    case custom = "Custom"

    var id: String { rawValue }

    var width: Int? {
        switch self {
        case .deviceDefault, .custom: return nil
        case .res360p: return 360
        case .res480p: return 480
        case .res540p: return 540
        case .res720p: return 720
        case .res900p: return 900
        case .res1080p: return 1080
        case .res1440p: return 1440
        case .res4k: return 1644
        }
    }

    var height: Int? {
        switch self {
        case .deviceDefault, .custom: return nil
        case .res360p: return 800
        case .res480p: return 1080
        case .res540p: return 1200
        case .res720p: return 1600
        case .res900p: return 2000
        case .res1080p: return 2400
        case .res1440p: return 3200
        case .res4k: return 3840
        }
    }

    var suggestedDensity: Int? {
        switch self {
        case .deviceDefault, .custom: return nil
        case .res360p: return 120
        case .res480p: return 160
        case .res540p: return 240
        case .res720p: return 320
        case .res900p: return 360
        case .res1080p: return 420
        case .res1440p: return 560
        case .res4k: return 640
        }
    }
}

// MARK: - EmulatorManagerView

struct EmulatorManagerView: View {
    @ObservedObject var viewModel: EmulatorManagerViewModel

    // Sidebar
    @State private var selectedSidebarItem: SidebarItem = .myDevices

    // Create AVD sheet
    @State private var showingCreateSheet = false
    @State private var newAvdName = ""
    @State private var selectedImage: SystemImage?
    @State private var selectedImageId: String?

    // Hardware
    @State private var selectedHardwareProfileId = "pixel"

    // Memory & Performance
    @State private var ramSize: String = "2048"
    @State private var heapSize: String = "512"
    @State private var storageSize: String = "4096"
    @State private var selectedGPUMode = "auto"
    @State private var useColdBoot = false
    @State private var showDeviceFrame = false

    // Display
    @State private var screenWidth: String = "1080"
    @State private var screenHeight: String = "2400"
    @State private var screenDensity: String = "420"
    @State private var selectedResolutionPreset: ResolutionPreset = .deviceDefault

    // Storage & Sensors
    @State private var sdCardSize: String = "512"
    @State private var selectedCamera = "emulated"
    @State private var enableGPS = false
    @State private var enableKeyboard = true

    // System Images tab
    @State private var imagesToDelete: Set<String> = []

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detailContent
        }
        .frame(minWidth: 780, idealWidth: 900, minHeight: 580, idealHeight: 700)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if selectedSidebarItem == .myDevices {
                    Button(action: {
                        newAvdName = ""
                        selectedImage = nil
                        selectedImageId = nil
                        showingCreateSheet = true
                    }) {
                        Label("Create Device", systemImage: "plus")
                    }
                    .help("Create a new virtual device")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: { viewModel.refresh() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh all data")
            }
        }
        .onAppear {
            viewModel.refresh()
        }
        .sheet(isPresented: $showingCreateSheet) {
            createAvdSheet
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            ForEach(SidebarItem.allCases) { item in
                SidebarRow(
                    item: item,
                    isSelected: selectedSidebarItem == item,
                    action: { selectedSidebarItem = item }
                )
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("AndroLaunch")
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSidebarItem {
        case .myDevices:
            avdListView
        case .systemImages:
            systemImagesTab
        case .settings:
            settingsView
        }
    }

    // MARK: - My Devices (AVD List)

    private var avdListView: some View {
        ZStack {
            if viewModel.existingAVDs.isEmpty && !viewModel.isLoadingAVDs {
                EmptyDeviceState(
                    onBrowseImages: {
                        selectedSidebarItem = .systemImages
                    },
                    onCreate: {
                        newAvdName = ""
                        selectedImage = nil
                        selectedImageId = nil
                        showingCreateSheet = true
                    }
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.existingAVDs) { avd in
                            AvdRowView(
                                avd: avd,
                                onRun: { viewModel.startEmulator(avdName: avd.name) },
                                onStop: { viewModel.stopEmulator(avdName: avd.name) },
                                onRename: { renameAction(avd: avd) },
                                onDelete: { viewModel.deleteAVD(name: avd.name) },
                                getLaunchFlags: { viewModel.getLaunchFlags(for: avd.name) },
                                setLaunchFlags: {
                                    viewModel.setLaunchFlags(for: avd.name, flags: $0)
                                }
                            )
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }

            if viewModel.isLoadingAVDs {
                loadingOverlay("Loading devices…")
            }
        }
        .navigationTitle("My Devices")
    }

    // MARK: - System Images Tab (Merged)

    private var systemImagesTab: some View {
        let filteredImages = viewModel.filteredImages
        let downloadingIds = Set(viewModel.downloadProgress.keys)
        let installedImages = filteredImages.filter { $0.isDownloaded }
        let downloadingImages = filteredImages.filter {
            !$0.isDownloaded && downloadingIds.contains($0.id)
        }
        let availableDownloads = filteredImages.filter {
            !$0.isDownloaded && !downloadingIds.contains($0.id)
        }
        let hasSelection = !viewModel.selectedImageIds.isEmpty || !imagesToDelete.isEmpty

        return ZStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search system images…", text: $viewModel.imageSearchText)
                        .textFieldStyle(.plain)
                        .controlSize(.regular)
                    if !viewModel.imageSearchText.isEmpty {
                        Button {
                            viewModel.imageSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // OS Type filter chips
                if !viewModel.availableImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(SystemImageType.allCases, id: \.self) { type in
                                let isSelected = viewModel.enabledOsTypes.contains(type)
                                let count = viewModel.osTypeCounts[type] ?? 0
                                Button {
                                    if isSelected {
                                        viewModel.enabledOsTypes.remove(type)
                                    } else {
                                        viewModel.enabledOsTypes.insert(type)
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: type.icon)
                                        Text(type.rawValue)
                                        Text("\(count)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        isSelected
                                            ? Color.accentColor.opacity(0.15)
                                            : Color.primary.opacity(0.06)
                                    )
                                    .foregroundColor(isSelected ? .accentColor : .secondary)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                isSelected
                                                    ? Color.accentColor.opacity(0.3) : Color.clear,
                                                lineWidth: 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 8)
                }

                if filteredImages.isEmpty && !viewModel.isLoadingImages {
                    VStack(spacing: 20) {
                        Image(
                            systemName: viewModel.imageSearchText.isEmpty
                                ? "externaldrive.badge.questionmark" : "magnifyingglass"
                        )
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                        Text(
                            viewModel.imageSearchText.isEmpty
                                ? "No System Images Found" : "No Matching Images"
                        )
                        .font(.title3)
                        .fontWeight(.medium)
                        Text(
                            viewModel.imageSearchText.isEmpty
                                ? "Check your Android SDK settings and click Refresh."
                                : "Try adjusting your search terms."
                        )
                        .font(.callout)
                        .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            // Installed section
                            if !installedImages.isEmpty {
                                Section {
                                    ForEach(installedImages) { image in
                                        SystemImageRowView(
                                            image: image,
                                            mode: .installed(
                                                isSelected: Binding(
                                                    get: { imagesToDelete.contains(image.id) },
                                                    set: { selected in
                                                        if selected {
                                                            imagesToDelete.insert(image.id)
                                                        } else {
                                                            imagesToDelete.remove(image.id)
                                                        }
                                                    }
                                                ),
                                                deleteDisabled: !viewModel.selectedImageIds.isEmpty
                                            ),
                                            downloadProgress: viewModel.downloadProgress[image.id],
                                            onCancelDownload: {
                                                viewModel.cancelDownload(image.id)
                                            },
                                            onCreateAVD: {
                                                selectedImage = image
                                                selectedImageId = image.id
                                                newAvdName = ""
                                                showingCreateSheet = true
                                            }
                                        )
                                        Divider().padding(.leading, 52)
                                    }
                                } header: {
                                    sectionHeader("Installed")
                                }
                            }

                            // Downloading section
                            if !downloadingImages.isEmpty {
                                Section {
                                    ForEach(downloadingImages) { image in
                                        SystemImageRowView(
                                            image: image,
                                            mode: .installed(
                                                isSelected: Binding(
                                                    get: { false },
                                                    set: { _ in }
                                                ),
                                                deleteDisabled: true
                                            ),
                                            downloadProgress: viewModel.downloadProgress[image.id],
                                            onCancelDownload: {
                                                viewModel.cancelDownload(image.id)
                                            },
                                            onCreateAVD: nil
                                        )
                                        Divider().padding(.leading, 52)
                                    }
                                } header: {
                                    sectionHeader("Downloading")
                                }
                            }

                            // Available section
                            if !availableDownloads.isEmpty {
                                Section {
                                    ForEach(availableDownloads) { image in
                                        SystemImageRowView(
                                            image: image,
                                            mode: .available(
                                                isSelected: Binding(
                                                    get: {
                                                        viewModel.selectedImageIds.contains(
                                                            image.id)
                                                    },
                                                    set: { selected in
                                                        if selected {
                                                            viewModel.selectedImageIds.insert(
                                                                image.id)
                                                        } else {
                                                            viewModel.selectedImageIds.remove(
                                                                image.id)
                                                        }
                                                    }
                                                ),
                                                isDisabled: image.isDownloaded
                                                    || !imagesToDelete.isEmpty
                                            ),
                                            downloadProgress: nil,
                                            onCancelDownload: {},
                                            onCreateAVD: nil
                                        )
                                        Divider().padding(.leading, 52)
                                    }
                                } header: {
                                    sectionHeader("Available for Download")
                                }
                            }
                        }
                        .padding(.bottom, hasSelection ? 60 : 12)
                    }
                }

                // Action bar
                if hasSelection {
                    actionBar
                }
            }

            if viewModel.isLoadingImages {
                loadingOverlay("Loading images…")
            }
        }
        .navigationTitle("System Images")
    }

    // MARK: - Settings View

    private var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Android Command Line Tools Path", systemImage: "terminal")
                            .font(.headline)

                        HStack(spacing: 10) {
                            TextField(
                                "/path/to/android/cmdline-tools/latest/bin",
                                text: Binding(
                                    get: { viewModel.commandLineToolsPath },
                                    set: { viewModel.commandLineToolsPath = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.regular)

                            Button("Browse…") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                panel.title = "Select Android SDK Command Line Tools Directory"
                                panel.message =
                                    "Choose the folder containing the Android SDK command-line tools (e.g., cmdline-tools/latest/bin)."
                                if panel.runModal() == .OK, let url = panel.url {
                                    viewModel.commandLineToolsPath = url.path
                                }
                            }
                            .controlSize(.regular)
                        }

                        Text(
                            "This path should point to the Android SDK command-line tools directory containing avdmanager and sdkmanager."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                }
                .padding(.horizontal, 20)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Android Virtual Device (AVD) Path", systemImage: "externaldrive")
                            .font(.headline)

                        HStack(spacing: 10) {
                            TextField(
                                viewModel.defaultAVDPath,
                                text: Binding(
                                    get: { viewModel.avdPath },
                                    set: { viewModel.avdPath = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.regular)

                            Button("Browse…") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                panel.title = "Select AVD Storage Directory"
                                panel.message =
                                    "Choose the directory where Android Virtual Devices (AVDs) will be stored."
                                if panel.runModal() == .OK, let url = panel.url {
                                    viewModel.avdPath = url.path
                                }
                            }
                            .controlSize(.regular)
                        }

                        HStack(spacing: 4) {
                            Text("Default:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(viewModel.defaultAVDPath)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }

                        Text(
                            "This directory stores AVD configuration and data files. Changing this requires restarting any running emulators."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                }
                .padding(.horizontal, 20)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("System Image Download Path", systemImage: "arrow.down.circle")
                            .font(.headline)

                        HStack(spacing: 10) {
                            TextField(
                                viewModel.defaultImageDownloadPath,
                                text: Binding(
                                    get: { viewModel.imageDownloadPath },
                                    set: { viewModel.imageDownloadPath = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.regular)

                            Button("Browse…") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                panel.title = "Select System Image Download Directory"
                                panel.message =
                                    "Choose the SDK root directory where system images will be downloaded and installed."
                                if panel.runModal() == .OK, let url = panel.url {
                                    viewModel.imageDownloadPath = url.path
                                }
                            }
                            .controlSize(.regular)
                        }

                        HStack(spacing: 4) {
                            Text("Default:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(viewModel.defaultImageDownloadPath)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }

                        Text(
                            "System images are downloaded to the 'system-images' subdirectory of this path. This overrides the SDK root derived from the command-line tools path."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                }
                .padding(.horizontal, 20)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Emulator Path", systemImage: "display")
                            .font(.headline)

                        HStack(spacing: 10) {
                            TextField(
                                "/path/to/emulator/emulator",
                                text: Binding(
                                    get: { viewModel.emulatorPath },
                                    set: { viewModel.emulatorPath = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.regular)

                            Button("Browse…") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = true
                                panel.canChooseDirectories = false
                                panel.allowsMultipleSelection = false
                                panel.title = "Select Emulator Binary"
                                panel.message =
                                    "Choose the emulator executable (e.g., emulator/emulator)."
                                if panel.runModal() == .OK, let url = panel.url {
                                    viewModel.emulatorPath = url.path
                                }
                            }
                            .controlSize(.regular)
                        }

                        Text(
                            "Explicit path to the Android emulator binary. Leave blank to auto-detect from SDK root."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .navigationTitle("Settings")
    }

    // MARK: - Shared Subviews

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial)
    }

    private var actionBar: some View {
        HStack(spacing: 16) {
            if !imagesToDelete.isEmpty {
                Label("\(imagesToDelete.count) selected for deletion", systemImage: "trash")
                    .font(.callout)
                    .foregroundColor(.red)

                Spacer()

                Button {
                    viewModel.deleteSelectedImages(imagesToDelete)
                    imagesToDelete.removeAll()
                } label: {
                    Label("Delete Selected", systemImage: "trash.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.regular)
            } else if !viewModel.selectedImageIds.isEmpty {
                Label(
                    "\(viewModel.selectedImageIds.count) selected for download",
                    systemImage: "square.and.arrow.down"
                )
                .font(.callout)
                .foregroundColor(.secondary)

                Spacer()

                Button {
                    viewModel.downloadSelected()
                } label: {
                    Label("Download Selected", systemImage: "square.and.arrow.down.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private func loadingOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.1)
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Helper: Suggest Density for Mac

    private func suggestDensityForMac() {
        let screen = NSScreen.main
        let scale = screen?.backingScaleFactor ?? 1.0

        if let w = Int(screenWidth), Int(screenHeight) != nil {
            let baseDpi = Double(w) / 2.5
            var suggested = Int(baseDpi)
            if scale > 1.0 {
                suggested = Int(Double(suggested) * 0.9)
            }
            screenDensity = "\((suggested / 20) * 20)"
        }
    }

    // MARK: - Rename Action (NSAlert)

    private func renameAction(avd: AVD) {
        let alert = NSAlert()
        alert.messageText = "Rename AVD"
        alert.informativeText = "Enter a new name for '\(avd.name)':"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        textField.stringValue = avd.name
        alert.accessoryView = textField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
            if !newName.isEmpty && newName != avd.name {
                viewModel.renameAVD(oldName: avd.name, newName: newName)
            }
        }
    }

    // MARK: - Create AVD Sheet

    private var createAvdSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create New Virtual Device")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Configure your virtual device hardware and identity.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)

            Divider()

            // Form content
            ScrollView {
                VStack(spacing: 0) {
                    Form {
                        // MARK: Basic Information
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("AVD Name")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("e.g. Pixel 8 Pro", text: $newAvdName)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.regular)
                            }
                            .padding(.vertical, 2)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("System Image")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                let installed = viewModel.availableImages.filter { $0.isDownloaded }
                                if installed.isEmpty {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text(
                                            "No system images installed. Download one from the System Images tab first."
                                        )
                                        .font(.callout)
                                        .foregroundColor(.secondary)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6).fill(
                                            Color.orange.opacity(0.08)))
                                } else {
                                    Picker("", selection: $selectedImageId) {
                                        Text("Select a system image…").tag(nil as String?)
                                        ForEach(installed) { image in
                                            Text(image.description).tag(image.id as String?)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .controlSize(.regular)
                                    .labelsHidden()
                                    .onChange(of: selectedImageId) { _, newId in
                                        selectedImage = installed.first { $0.id == newId }
                                    }

                                    if let image = installed.first(where: {
                                        $0.id == selectedImageId
                                    }) {
                                        Label {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(image.id)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        } icon: {
                                            Image(systemName: "internaldrive")
                                                .foregroundColor(.accentColor)
                                        }
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6).fill(
                                                Color.primary.opacity(0.05)))
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        } header: {
                            Text("Basic Information")
                        }

                        // MARK: Hardware Profile
                        Section {
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Device Template")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Picker("", selection: $selectedHardwareProfileId) {
                                        if viewModel.hardwareProfiles.isEmpty {
                                            Text("Loading devices…").tag("pixel")
                                        } else {
                                            ForEach(viewModel.hardwareProfiles) { profile in
                                                Text(profile.name).tag(profile.id)
                                            }
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: 220)
                                    .onChange(of: selectedHardwareProfileId) { _, newId in
                                        guard selectedResolutionPreset == .deviceDefault else {
                                            return
                                        }
                                        if let profile = viewModel.hardwareProfiles.first(where: {
                                            $0.id == newId
                                        }) {
                                            if let w = profile.width, let h = profile.height {
                                                screenWidth = "\(w)"
                                                screenHeight = "\(h)"
                                            }
                                            if let d = profile.density { screenDensity = "\(d)" }
                                        }
                                    }
                                    .controlSize(.regular)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Resolution Preset")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Picker("", selection: $selectedResolutionPreset) {
                                        ForEach(ResolutionPreset.allCases) { preset in
                                            Text(preset.rawValue).tag(preset)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 200)
                                    .onChange(of: selectedResolutionPreset) { _, preset in
                                        if preset == .deviceDefault {
                                            if let profile = viewModel.hardwareProfiles.first(
                                                where: { $0.id == selectedHardwareProfileId })
                                            {
                                                if let w = profile.width, let h = profile.height {
                                                    screenWidth = "\(w)"
                                                    screenHeight = "\(h)"
                                                }
                                                if let d = profile.density {
                                                    screenDensity = "\(d)"
                                                }
                                            }
                                        } else if let w = preset.width, let h = preset.height {
                                            screenWidth = "\(w)"
                                            screenHeight = "\(h)"
                                            if let d = preset.suggestedDensity {
                                                screenDensity = "\(d)"
                                            }
                                        }
                                    }
                                    .controlSize(.regular)
                                }
                            }
                            .padding(.vertical, 2)
                        } header: {
                            Text("Hardware Profile")
                        }

                        // MARK: Advanced Settings
                        Section {
                            DisclosureGroup {
                                // Memory & Performance
                                GroupBox {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Label("Memory & Performance", systemImage: "memorychip")
                                            .font(.callout)
                                            .fontWeight(.semibold)

                                        HStack(spacing: 12) {
                                            FormField(label: "RAM (MB)", value: $ramSize)
                                            FormField(label: "VM Heap (MB)", value: $heapSize)
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Graphics Acceleration")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Picker("", selection: $selectedGPUMode) {
                                                Text("Auto").tag("auto")
                                                Text("Hardware (GPU)").tag("host")
                                                Text("Software (CPU)").tag("software")
                                            }
                                            .pickerStyle(.menu)
                                            .controlSize(.regular)
                                        }

                                        Toggle("Force Cold Boot", isOn: $useColdBoot)
                                        Toggle("Show Device Frame", isOn: $showDeviceFrame)
                                    }
                                    .padding(8)
                                }

                                // Display
                                GroupBox {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Label("Display Settings", systemImage: "display")
                                            .font(.callout)
                                            .fontWeight(.semibold)

                                        if selectedResolutionPreset == .custom {
                                            HStack(spacing: 12) {
                                                FormField(label: "Width (px)", value: $screenWidth)
                                                FormField(
                                                    label: "Height (px)", value: $screenHeight)
                                            }
                                        } else {
                                            HStack(spacing: 20) {
                                                LabeledContent("Width") {
                                                    Text(screenWidth).monospacedDigit()
                                                }
                                                LabeledContent("Height") {
                                                    Text(screenHeight).monospacedDigit()
                                                }
                                            }
                                            .font(.callout)
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text("Density (DPI)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Spacer()
                                                Button("Auto-Suggest for Mac") {
                                                    suggestDensityForMac()
                                                }
                                                .buttonStyle(.link)
                                                .font(.caption)
                                            }
                                            TextField("420", text: $screenDensity)
                                                .textFieldStyle(.roundedBorder)
                                                .controlSize(.regular)
                                        }
                                    }
                                    .padding(8)
                                }

                                // Storage & Features
                                GroupBox {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Label("Storage & Features", systemImage: "externaldrive")
                                            .font(.callout)
                                            .fontWeight(.semibold)

                                        HStack(spacing: 12) {
                                            FormField(
                                                label: "Internal Storage (MB)", value: $storageSize)
                                            FormField(label: "SD Card (MB)", value: $sdCardSize)
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Camera Support")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Picker("", selection: $selectedCamera) {
                                                Text("None").tag("none")
                                                Text("Emulated").tag("emulated")
                                                Text("Webcam (Physical)").tag("webcam0")
                                            }
                                            .pickerStyle(.menu)
                                            .controlSize(.regular)
                                        }

                                        HStack(spacing: 24) {
                                            Toggle("GPS Support", isOn: $enableGPS)
                                            Toggle("Physical Keyboard", isOn: $enableKeyboard)
                                        }
                                    }
                                    .padding(8)
                                }
                            } label: {
                                Label("Advanced Settings", systemImage: "slider.horizontal.3")
                                    .font(.callout)
                                    .fontWeight(.medium)
                            }
                        } header: {
                            Text("Configuration")
                        }
                    }
                    .formStyle(.grouped)
                }
            }

            Divider()

            // Footer with cancel/create buttons
            HStack {
                Button("Cancel") {
                    showingCreateSheet = false
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.isCreatingAVD)

                Spacer()

                if viewModel.isCreatingAVD {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.8)
                        Text("Creating AVD…")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }

                Button {
                    guard let image = selectedImage else { return }
                    let options = AVDOptions(
                        ramMB: Int(ramSize),
                        heapMB: Int(heapSize),
                        storageMB: Int(storageSize),
                        width: Int(screenWidth),
                        height: Int(screenHeight),
                        density: Int(screenDensity),
                        sdCardMB: Int(sdCardSize),
                        cameraBack: selectedCamera,
                        gps: enableGPS,
                        keyboard: enableKeyboard,
                        gpuMode: selectedGPUMode,
                        coldBoot: useColdBoot,
                        showDeviceFrame: showDeviceFrame
                    )
                    viewModel.createAVD(
                        name: newAvdName,
                        imagePath: image.id,
                        device: selectedHardwareProfileId,
                        options: options
                    )
                    showingCreateSheet = false
                } label: {
                    Text("Create Device")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    newAvdName.trimmingCharacters(in: .whitespaces).isEmpty
                        || selectedImage == nil
                        || viewModel.isCreatingAVD)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 580, idealHeight: 680)
    }
}

// MARK: - FormField Helper

private struct FormField: View {
    let label: String
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("", text: $value)
                .textFieldStyle(.roundedBorder)
                .controlSize(.regular)
        }
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let item: SidebarItem
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(item.rawValue, systemImage: item.icon)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(backgroundColor)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            Color.accentColor.opacity(0.15)
        } else if isHovering {
            Color.primary.opacity(0.06)
        } else {
            Color.clear
        }
    }
}

// MARK: - Empty Device State

private struct EmptyDeviceState: View {
    var onBrowseImages: () -> Void
    var onCreate: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No Virtual Devices")
                .font(.title2)
                .fontWeight(.medium)
            Text("Create your first Android Virtual Device by downloading a system image.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            HStack(spacing: 12) {
                Button {
                    onCreate()
                } label: {
                    Label("Create Device", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                Button {
                    onBrowseImages()
                } label: {
                    Label("Browse System Images", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - AVD Row View (with hover reveal)

private struct AvdRowView: View {
    let avd: AVD
    let onRun: () -> Void
    let onStop: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let getLaunchFlags: () -> LaunchFlags
    let setLaunchFlags: (LaunchFlags) -> Void

    @State private var isHovering = false
    @State private var showLaunchFlagsPopover = false
    @State private var currentLaunchFlags = LaunchFlags.default

    private var isDisabled: Bool { avd.isRunning || avd.isStarting }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: avd.isRunning ? "iphone.gen3" : "iphone.gen3")
                .font(.title2)
                .foregroundColor(avd.isRunning ? .green : .accentColor)
                .frame(width: 32)
                .symbolEffect(.pulse, isActive: avd.isStarting || avd.isStopping)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(avd.name)
                        .font(.body)
                        .fontWeight(.medium)
                    statusBadge
                }
                HStack(spacing: 6) {
                    if let device = avd.device, !device.isEmpty {
                        Text(device)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let target = avd.target, !target.isEmpty {
                        if avd.device != nil, !avd.device!.isEmpty {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        }
                        Text(target)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer()

            // Primary action
            primaryButton

            // Secondary actions (hover-revealed)
            if isHovering && !avd.isStopping {
                HStack(spacing: 4) {
                    Button {
                        currentLaunchFlags = getLaunchFlags()
                        showLaunchFlagsPopover = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Launch Options")
                    .popover(isPresented: $showLaunchFlagsPopover) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Launch Flags")
                                    .font(.headline)

                                Divider()

                                // MARK: Core
                                Text("Core").font(.subheadline).foregroundColor(.secondary)
                                Toggle("No Audio (-no-audio)", isOn: $currentLaunchFlags.noAudio)
                                Toggle("No Window (-no-window)", isOn: $currentLaunchFlags.noWindow)
                                Toggle("Verbose (-verbose)", isOn: $currentLaunchFlags.verbose)
                                Toggle("No Skin (-no-skin)", isOn: $currentLaunchFlags.noSkin)
                                Toggle(
                                    "Qt Hide Window (-qt-hide-window)",
                                    isOn: $currentLaunchFlags.qtHideWindow)

                                Divider()

                                // MARK: Boot
                                Text("Boot").font(.subheadline).foregroundColor(.secondary)
                                Toggle("Wipe Data (-wipe-data)", isOn: $currentLaunchFlags.wipeData)
                                Toggle("Read Only (-read-only)", isOn: $currentLaunchFlags.readOnly)
                                Toggle(
                                    "No Boot Anim (-no-boot-anim)",
                                    isOn: $currentLaunchFlags.noBootAnim)
                                Toggle("No JNI (-nojni)", isOn: $currentLaunchFlags.noJni)

                                Divider()

                                // MARK: Snapshot
                                Text("Snapshot").font(.subheadline).foregroundColor(.secondary)
                                Toggle(
                                    "No Snapshot Save (-no-snapshot-save)",
                                    isOn: $currentLaunchFlags.noSnapshotSave)
                                Toggle(
                                    "No Snapshot Load (-no-snapshot-load)",
                                    isOn: $currentLaunchFlags.noSnapshotLoad)
                                HStack(spacing: 8) {
                                    Text("Name:").frame(width: 90, alignment: .leading)
                                    TextField("snapshot name", text: $currentLaunchFlags.snapshot)
                                        .textFieldStyle(.roundedBorder).controlSize(.small)
                                }

                                Divider()

                                // MARK: GPU
                                Text("GPU").font(.subheadline).foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    Text("Mode:").frame(width: 90, alignment: .leading)
                                    Picker("", selection: $currentLaunchFlags.gpuMode) {
                                        Text("host").tag("host")
                                        Text("auto").tag("auto")
                                        Text("swiftshader").tag("swiftshader_indirect")
                                        Text("angle").tag("angle_indirect")
                                        Text("off").tag("off")
                                    }
                                    .pickerStyle(.menu).controlSize(.small).frame(width: 130)
                                }

                                Divider()

                                // MARK: Network
                                Text("Network").font(.subheadline).foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    Text("Speed:").frame(width: 90, alignment: .leading)
                                    Picker("", selection: $currentLaunchFlags.netSpeed) {
                                        Text("full").tag("full")
                                        Text("gsm").tag("gsm")
                                        Text("hscsd").tag("hscsd")
                                        Text("gprs").tag("gprs")
                                        Text("edge").tag("edge")
                                        Text("umts").tag("umts")
                                        Text("hsdpa").tag("hsdpa")
                                        Text("lte").tag("lte")
                                        Text("evdo").tag("evdo")
                                    }
                                    .pickerStyle(.menu).controlSize(.small).frame(width: 130)
                                }
                                HStack(spacing: 8) {
                                    Text("Delay:").frame(width: 90, alignment: .leading)
                                    Picker("", selection: $currentLaunchFlags.netDelay) {
                                        Text("none").tag("none")
                                        Text("gprs").tag("gprs")
                                        Text("edge").tag("edge")
                                        Text("umts").tag("umts")
                                    }
                                    .pickerStyle(.menu).controlSize(.small).frame(width: 130)
                                }
                                HStack(spacing: 8) {
                                    Text("Proxy:").frame(width: 90, alignment: .leading)
                                    TextField(
                                        "http://proxy:8080", text: $currentLaunchFlags.httpProxy
                                    )
                                    .textFieldStyle(.roundedBorder).controlSize(.small)
                                }
                                HStack(spacing: 8) {
                                    Text("DNS:").frame(width: 90, alignment: .leading)
                                    TextField("8.8.8.8", text: $currentLaunchFlags.dnsServer)
                                        .textFieldStyle(.roundedBorder).controlSize(.small)
                                }

                                Divider()

                                // MARK: Performance
                                Text("Performance").font(.subheadline).foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    Text("RAM (MB):").frame(width: 90, alignment: .leading)
                                    TextField("2048", text: $currentLaunchFlags.memoryMB)
                                        .textFieldStyle(.roundedBorder).controlSize(.small).frame(
                                            width: 80)
                                    Text("Cores:").frame(width: 40, alignment: .leading)
                                    TextField("4", text: $currentLaunchFlags.cores)
                                        .textFieldStyle(.roundedBorder).controlSize(.small).frame(
                                            width: 50)
                                }
                                HStack(spacing: 8) {
                                    Text("Port:").frame(width: 90, alignment: .leading)
                                    TextField("5554", text: $currentLaunchFlags.port)
                                        .textFieldStyle(.roundedBorder).controlSize(.small).frame(
                                            width: 80)
                                }

                                Divider()

                                // MARK: Camera
                                Text("Camera").font(.subheadline).foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    Text("Back:").frame(width: 90, alignment: .leading)
                                    Picker("", selection: $currentLaunchFlags.cameraBack) {
                                        Text("AVD default").tag("")
                                        Text("emulated").tag("emulated")
                                        Text("webcam0").tag("webcam0")
                                        Text("none").tag("none")
                                    }
                                    .pickerStyle(.menu).controlSize(.small).frame(width: 130)
                                }
                                HStack(spacing: 8) {
                                    Text("Front:").frame(width: 90, alignment: .leading)
                                    Picker("", selection: $currentLaunchFlags.cameraFront) {
                                        Text("AVD default").tag("")
                                        Text("emulated").tag("emulated")
                                        Text("webcam0").tag("webcam0")
                                        Text("none").tag("none")
                                    }
                                    .pickerStyle(.menu).controlSize(.small).frame(width: 130)
                                }

                                Divider()

                                // MARK: Audio
                                Text("Audio").font(.subheadline).foregroundColor(.secondary)
                                Toggle(
                                    "Audio Input (-prop hw.audioInput=yes)",
                                    isOn: $currentLaunchFlags.audioInput
                                )
                                .disabled(currentLaunchFlags.noAudio)
                                Toggle(
                                    "Audio Output (-prop hw.audioOutput=yes)",
                                    isOn: $currentLaunchFlags.audioOutput
                                )
                                .disabled(currentLaunchFlags.noAudio)
                                if currentLaunchFlags.noAudio {
                                    Text("Disabled when No Audio is on").font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Divider()

                                // MARK: Extra
                                Text("Extra").font(.subheadline).foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    Text("Timezone:").frame(width: 90, alignment: .leading)
                                    TextField("Asia/Kolkata", text: $currentLaunchFlags.timezone)
                                        .textFieldStyle(.roundedBorder).controlSize(.small)
                                }
                                HStack(spacing: 8) {
                                    Text("tcpdump:").frame(width: 90, alignment: .leading)
                                    TextField(
                                        "/path/to/capture.pcap", text: $currentLaunchFlags.tcpdump
                                    )
                                    .textFieldStyle(.roundedBorder).controlSize(.small)
                                }

                                HStack {
                                    Spacer()
                                    Button("Apply") {
                                        setLaunchFlags(currentLaunchFlags)
                                        showLaunchFlagsPopover = false
                                    }
                                    .buttonStyle(.borderedProminent).controlSize(.small)
                                    Button("Cancel") {
                                        showLaunchFlagsPopover = false
                                    }
                                    .buttonStyle(.borderless).controlSize(.small)
                                }
                            }
                            .padding(16)
                        }
                        .frame(height: 600)
                        .frame(width: 325)
                    }

                    Button {
                        onRename()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Rename")
                    .disabled(isDisabled)

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Delete")
                    .disabled(isDisabled)
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(isHovering ? Color.primary.opacity(0.05) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                isHovering = showLaunchFlagsPopover || hovering
            }
        }
        .onChange(of: showLaunchFlagsPopover) { newValue in
            if !newValue {
                isHovering = false
            }
        }
        .contextMenu {
            Button("Rename…") { onRename() }
                .disabled(isDisabled)
            Button("Delete", role: .destructive) { onDelete() }
                .disabled(isDisabled)
            Divider()
            Button("Show in Finder") {
                // no-op for now; placeholder
            }
            .disabled(true)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if avd.isStopping {
            Badge(text: "Stopping…", color: .red)
        } else if avd.isRunning {
            Badge(text: "Running", color: .green)
        } else if avd.isStarting {
            Badge(text: "Starting…", color: .blue)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if avd.isStopping {
            Button {
            } label: {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text("Stopping")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(true)
        } else if avd.isRunning {
            Button {
                onStop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.small)
            .help("Stop emulator")
        } else if avd.isStarting {
            Button {
            } label: {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text("Starting")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(true)
        } else {
            Button {
                onRun()
            } label: {
                Label("Run", systemImage: "play.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Run emulator")
        }
    }
}

// MARK: - Status Badge

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

// MARK: - System Image Row View

private struct SystemImageRowView: View {
    enum Mode {
        case installed(isSelected: Binding<Bool>, deleteDisabled: Bool)
        case available(isSelected: Binding<Bool>, isDisabled: Bool)
    }

    let image: SystemImage
    let mode: Mode
    let downloadProgress: Double?
    let onCancelDownload: () -> Void
    let onCreateAVD: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Left: selection control
            selectionControl

            // Icon
            Image(
                systemName: downloadProgress != nil
                    ? "arrow.down.circle"
                    : (image.isDownloaded ? "internaldrive.fill" : image.osType.icon)
            )
            .font(.title3)
            .foregroundColor(
                downloadProgress != nil
                    ? .blue
                    : (image.isDownloaded ? .green : .accentColor)
            )
            .frame(width: 24)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let apiLevel = image.apiLevel {
                        Text("API \(apiLevel)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .cornerRadius(4)
                    }
                    Text(image.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    if let arch = image.architecture {
                        Text(arch)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if image.architecture != nil {
                        Text("\u{00B7}")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(image.osType.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Hover: Create AVD button for installed images
            if image.isDownloaded, let onCreateAVD = onCreateAVD, isHovering {
                Button(action: onCreateAVD) {
                    Label("Create AVD", systemImage: "plus.circle")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("Create virtual device from this image")
                .transition(.scale.combined(with: .opacity))
            }

            // Status / Progress
            statusView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(isHovering ? Color.primary.opacity(0.05) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    @ViewBuilder
    private var selectionControl: some View {
        switch mode {
        case .installed(let isSelected, let deleteDisabled):
            if downloadProgress != nil {
                Button {
                    onCancelDownload()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Cancel download")
            } else {
                Toggle("", isOn: isSelected)
                    .toggleStyle(.checkbox)
                    .disabled(deleteDisabled)
                    .controlSize(.small)
            }

        case .available(let isSelected, let isDisabled):
            Toggle("", isOn: isSelected)
                .toggleStyle(.checkbox)
                .disabled(isDisabled)
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var statusView: some View {
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
        } else if let progress = downloadProgress {
            if progress > 0 {
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .frame(width: 100)
                        .controlSize(.small)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                .animation(.easeInOut(duration: 0.25), value: progress)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                        .frame(width: 100)
                    Text("Downloading…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        } else {
            Text("Not installed")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
