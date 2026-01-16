//
//  EmulatorManagerView.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 16/1/26.
//

import SwiftUI

struct EmulatorManagerView: View {
    @ObservedObject var viewModel: EmulatorManagerViewModel
    @State private var selectedTab = 0
    @State private var showingCreateSheet = false
    @State private var newAvdName = ""
    @State private var selectedImage: SystemImage?
    
    // Advanced Creation Options
    @State private var selectedHardwareProfileId = "pixel"
    @State private var showAdvancedOptions = false
    
    // Core Hardware
    @State private var ramSize: String = "2048"
    @State private var heapSize: String = "512"
    @State private var storageSize: String = "4096"
    
    // Display
    @State private var screenWidth: String = "1080"
    @State private var screenHeight: String = "2400"
    @State private var screenDensity: String = "420"
    
    // Storage & Misc
    @State private var sdCardSize: String = "512"
    @State private var selectedCamera = "emulated"
    @State private var enableGPS = false
    @State private var enableKeyboard = true
    
    // Performance
    @State private var selectedGPUMode = "auto"
    @State private var useColdBoot = false
    @State private var showDeviceFrame = false
    
    // Resolution Presets (Modern 20:9 Aspect Ratios)
    enum ResolutionPreset: String, CaseIterable, Identifiable {
        case deviceDefault = "Device Default"
        case res360p = "360p (360x800)"
        case res480p = "480p (480x1080)"
        case res540p = "540p (540x1200)"
        case res720p = "720p (720x1600)"
        case res900p = "900p (900x2000)"
        case res1080p = "1080p (1080x2400)"
        case res1440p = "1440p (1440x3200)"
        case res4k = "4K (1644x3840)"
        case custom = "Custom"
        
        var id: String { self.rawValue }
        var width: Int? {
            switch self {
            case .deviceDefault: return nil
            case .res360p: return 360
            case .res480p: return 480
            case .res540p: return 540
            case .res720p: return 720
            case .res900p: return 900
            case .res1080p: return 1080
            case .res1440p: return 1440
            case .res4k: return 1644
            case .custom: return nil
            }
        }
        var height: Int? {
            switch self {
            case .deviceDefault: return nil
            case .res360p: return 800
            case .res480p: return 1080
            case .res540p: return 1200
            case .res720p: return 1600
            case .res900p: return 2000
            case .res1080p: return 2400
            case .res1440p: return 3200
            case .res4k: return 3840
            case .custom: return nil
            }
        }
        var suggestedDensity: Int? {
            switch self {
            case .deviceDefault: return nil
            case .res360p: return 120
            case .res480p: return 160
            case .res540p: return 240
            case .res720p: return 320
            case .res900p: return 360
            case .res1080p: return 420
            case .res1440p: return 560
            case .res4k: return 640
            case .custom: return nil
            }
        }
    }
    @State private var selectedResolutionPreset: ResolutionPreset = .deviceDefault
    
    private func suggestDensityForMac() {
        let screen = NSScreen.main
        let scale = screen?.backingScaleFactor ?? 1.0
        
        if let w = Int(screenWidth), let _ = Int(screenHeight) {
            // Base calculation: for modern phones, we want ~400-440 dp width on standard screens.
            // On high-res Mac screens, we can afford more logical space.
            let baseDpi = Double(w) / 2.5 // Rough heuristic for comfortable width
            
            // Adjust based on Mac scaling
            // On Retina (2.0), things look smaller, so we might want a slightly higher logical density to keep it readable,
            // OR lower it even more if the user wants "more space".
            // Since the user said "too big", we definitely want to bias lower.
            var suggested = Int(baseDpi)
            
            if scale > 1.0 {
                suggested = Int(Double(suggested) * 0.9) // 10% more space on Retina
            }
            
            // Snap to nearest 20
            screenDensity = "\((suggested / 20) * 20)"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Error Banner
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }
            
            // 3-Tab Picker
            Picker("", selection: $selectedTab) {
                Text("AVDs").tag(0)
                Text("System Images").tag(1)
                Text("Manage Images").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            
            Divider()
            
            // Content Area
            Group {
                switch selectedTab {
                case 0:
                    avdListView
                case 1:
                    systemImagesView
                case 2:
                    ManageImagesView(viewModel: viewModel)
                default:
                    avdListView
                }
            }
            
            Divider()
            
            // Path Settings Footer
            pathSettingsView
        }
        .frame(minWidth: 800, idealWidth: 900, minHeight: 650, idealHeight: 750)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { viewModel.refresh() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            viewModel.refresh()
        }
        .sheet(isPresented: $showingCreateSheet) {
            createAvdView
        }
    }
    
    // MARK: - Error Banner
    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(error)
                .foregroundColor(.primary)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button(action: { viewModel.errorMessage = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(8)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
    
    // MARK: - Tab 1: AVD List View
    private var avdListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.existingAVDs.isEmpty && !viewModel.isLoadingAVDs {
                    emptyStateView(
                        icon: "desktopcomputer",
                        title: "No AVDs Found",
                        subtitle: "Go to 'System Images' tab to select an image and create an AVD."
                    )
                    .padding(.top, 80)
                }
                
                ForEach(viewModel.existingAVDs) { avd in
                    avdRow(avd)
                    Divider().padding(.leading, 20)
                }
            }
        }
        .overlay {
            if viewModel.isLoadingAVDs {
                loadingOverlay("Loading AVDs...")
            }
        }
    }
    
    private func avdRow(_ avd: AVD) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "iphone.gen3")
                .font(.title)
                .foregroundColor(.accentColor)
                .frame(width: 44)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(avd.name)
                        .font(.headline)
                    if avd.isStopping {
                        Text("Stopping...")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    } else if avd.isRunning {
                        Text("Running")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    } else if avd.isStarting {
                        Text("Starting...")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
                HStack(spacing: 8) {
                    if let device = avd.device, !device.isEmpty {
                        Label(device, systemImage: "cpu")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let target = avd.target, !target.isEmpty {
                        Text("•").foregroundColor(.secondary)
                        Text(target)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if avd.isStopping {
                    Button(action: {}) {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                            Text("Stopping")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                    .controlSize(.small)
                } else if avd.isRunning {
                    Button(action: { viewModel.stopEmulator(avdName: avd.name) }) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                } else if avd.isStarting {
                    Button(action: {}) {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                            Text("Starting")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                    .controlSize(.small)
                } else {
                    Button(action: { viewModel.startEmulator(avdName: avd.name) }) {
                        Label("Run", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                
                Button(action: { renameAction(avd: avd) }) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Rename AVD")
                .disabled(avd.isRunning || avd.isStarting)
                
                Button(action: { viewModel.deleteAVD(name: avd.name) }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Delete AVD")
                .disabled(avd.isRunning || avd.isStarting)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
    
    // MARK: - Tab 2: System Images (for AVD creation)
    private var systemImagesView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.availableImages.isEmpty && !viewModel.isLoadingImages {
                    emptyStateView(
                        icon: "square.and.arrow.down",
                        title: "No Images Available",
                        subtitle: "Go to 'Manage Images' tab to download system images first."
                    )
                    .padding(.top, 80)
                }
                
                // Only show downloaded images for AVD creation
                let downloadedImages = viewModel.availableImages.filter { $0.isDownloaded }
                
                if !downloadedImages.isEmpty {
                    ForEach(downloadedImages) { image in
                        systemImageRowForAVD(image)
                        Divider().padding(.leading, 60)
                    }
                } else if !viewModel.isLoadingImages && !viewModel.availableImages.isEmpty {
                    emptyStateView(
                        icon: "arrow.down.circle",
                        title: "No Downloaded Images",
                        subtitle: "Go to 'Manage Images' tab to download system images first."
                    )
                    .padding(.top, 80)
                }
            }
        }
        .overlay {
            if viewModel.isLoadingImages {
                loadingOverlay("Loading images...")
            }
        }
    }
    
    private func systemImageRowForAVD(_ image: SystemImage) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "internaldrive.fill")
                .font(.title2)
                .foregroundColor(.green)
                .frame(width: 44)
            
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
            
            Button("Create AVD") {
                selectedImage = image
                newAvdName = ""
                // Reset defaults for modern experience
                selectedHardwareProfileId = "pixel_8"
                ramSize = "4096"
                heapSize = "512"
                storageSize = "8192"
                screenWidth = "1080"
                screenHeight = "2400"
                screenDensity = "420"
                sdCardSize = "1024"
                selectedCamera = "emulated"
                enableGPS = false
                enableKeyboard = true
                selectedGPUMode = "auto"
                useColdBoot = false
                showDeviceFrame = false
                selectedResolutionPreset = .deviceDefault
                showingCreateSheet = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
    
    
    
    // MARK: - Path Settings View
    private var pathSettingsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Android Command Line Tools Path")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            HStack(spacing: 10) {
                TextField("/path/to/android/cmdline-tools/latest/bin", text: Binding(
                    get: { viewModel.commandLineToolsPath },
                    set: { viewModel.commandLineToolsPath = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                
                Button("Browse...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        viewModel.commandLineToolsPath = url.path
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.03))
    }
    
    // MARK: - Helper Views
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
    
    // MARK: - Create AVD Sheet
    private var createAvdView: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Create New AVD")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Configure your device hardware and identity")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                
                VStack(alignment: .leading, spacing: 20) {
                    // Basic Info Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Basic Information")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AVD Name")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            TextField("e.g. Pixel 8 Pro", text: $newAvdName)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.large)
                        }
                        
                        if let image = selectedImage {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("System Image")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                HStack {
                                    Image(systemName: "internaldrive")
                                        .foregroundColor(.accentColor)
                                    VStack(alignment: .leading) {
                                        Text(image.description)
                                            .font(.body)
                                        Text(image.id)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Hardware Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Hardware Profile")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Device Template")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Picker("", selection: $selectedHardwareProfileId) {
                                        if viewModel.hardwareProfiles.isEmpty {
                                            Text("Loading devices...").tag("pixel")
                                        } else {
                                            ForEach(viewModel.hardwareProfiles) { profile in
                                                Text(profile.name).tag(profile.id)
                                            }
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity)
                                    .onChange(of: selectedHardwareProfileId) { _, newId in
                                        // Update dims if using Default preset
                                        if selectedResolutionPreset == .deviceDefault,
                                           let profile = viewModel.hardwareProfiles.first(where: { $0.id == newId }) {
                                            if let w = profile.width, let h = profile.height {
                                                screenWidth = "\(w)"
                                                screenHeight = "\(h)"
                                            }
                                            if let d = profile.density {
                                                screenDensity = "\(d)"
                                            }
                                        }
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Resolution")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Picker("", selection: $selectedResolutionPreset) {
                                        ForEach(ResolutionPreset.allCases) { preset in
                                            Text(preset.rawValue).tag(preset)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 180)
                                    .onChange(of: selectedResolutionPreset) { _, preset in
                                        if preset == .deviceDefault {
                                            // Re-apply profile defaults
                                            if let profile = viewModel.hardwareProfiles.first(where: { $0.id == selectedHardwareProfileId }) {
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
                                }
                            }
                        }
                        
                        Button(action: { withAnimation { showAdvancedOptions.toggle() } }) {
                            HStack {
                                Text("Advanced Settings (Memory & Storage)")
                                Image(systemName: showAdvancedOptions ? "chevron.up" : "chevron.down")
                            }
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                        
                        if showAdvancedOptions {
                            VStack(spacing: 24) {
                                // Memory Section
                                VStack(alignment: .leading, spacing: 12) {
                                    Label("Memory & Performance", systemImage: "memorychip")
                                        .font(.subheadline).fontWeight(.bold)
                                    
                                    HStack(spacing: 16) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("RAM (MB)").font(.caption).foregroundColor(.secondary)
                                            TextField("4096", text: $ramSize).textFieldStyle(.roundedBorder)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("VM Heap (MB)").font(.caption).foregroundColor(.secondary)
                                            TextField("512", text: $heapSize).textFieldStyle(.roundedBorder)
                                        }
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Graphics Acceleration").font(.caption).foregroundColor(.secondary)
                                        Picker("", selection: $selectedGPUMode) {
                                            Text("Auto").tag("auto")
                                            Text("Hardware (GPU)").tag("host")
                                            Text("Software (CPU)").tag("software")
                                        }
                                        .pickerStyle(.menu)
                                    }
                                    
                                    Toggle("Force Cold Boot", isOn: $useColdBoot)
                                    Toggle("Show Device Frame", isOn: $showDeviceFrame)
                                }
                                .font(.caption)
                                
                                Divider()
                                
                                // Display Section
                                VStack(alignment: .leading, spacing: 12) {
                                    Label("Display Settings", systemImage: "display")
                                        .font(.subheadline).fontWeight(.bold)
                                    
                                    if selectedResolutionPreset == .custom {
                                        HStack(spacing: 16) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Width").font(.caption).foregroundColor(.secondary)
                                                TextField("1080", text: $screenWidth).textFieldStyle(.roundedBorder)
                                            }
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Height").font(.caption).foregroundColor(.secondary)
                                                TextField("2400", text: $screenHeight).textFieldStyle(.roundedBorder)
                                            }
                                        }
                                        .transition(.scale.combined(with: .opacity))
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("Density (DPI)").font(.caption).foregroundColor(.secondary)
                                            Spacer()
                                            Button("Auto-Suggest for Mac") {
                                                suggestDensityForMac()
                                            }
                                            .buttonStyle(.plain)
                                            .font(.caption2)
                                            .foregroundColor(.accentColor)
                                        }
                                        TextField("420", text: $screenDensity).textFieldStyle(.roundedBorder)
                                    }
                                }
                                
                                Divider()
                                
                                // Storage & Sensors
                                VStack(alignment: .leading, spacing: 12) {
                                    Label("Storage & Features", systemImage: "externaldrive")
                                        .font(.subheadline).fontWeight(.bold)
                                    
                                    HStack(spacing: 16) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Internal Storage (MB)").font(.caption).foregroundColor(.secondary)
                                            TextField("8192", text: $storageSize).textFieldStyle(.roundedBorder)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("SD Card (MB)").font(.caption).foregroundColor(.secondary)
                                            TextField("1024", text: $sdCardSize).textFieldStyle(.roundedBorder)
                                        }
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Camera Support").font(.caption).foregroundColor(.secondary)
                                        Picker("", selection: $selectedCamera) {
                                            Text("None").tag("none")
                                            Text("Emulated").tag("emulated")
                                            Text("Webcam (Physical)").tag("webcam0")
                                        }
                                        .pickerStyle(.menu)
                                    }
                                    
                                    HStack(spacing: 24) {
                                        Toggle("GPS Support", isOn: $enableGPS)
                                        Toggle("Physical Keyboard", isOn: $enableKeyboard)
                                    }
                                    .font(.caption)
                                }
                            }
                            .padding(.vertical, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal, 8)
                
                if viewModel.isCreatingAVD {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Creating AVD and applying configurations...")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 16) {
                    Button("Cancel") {
                        showingCreateSheet = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                    .disabled(viewModel.isCreatingAVD)
                    
                    Spacer()
                    
                    Button(action: {
                        if let image = selectedImage {
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
                        }
                    }) {
                        Text("Create Device")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newAvdName.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isCreatingAVD)
                }
                .padding(.top, 10)
            }
            .padding(32)
        }
        .frame(width: 520, height: 650)
    }
    
    // MARK: - Rename Action
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
}
