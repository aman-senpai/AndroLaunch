//
//  DeviceRepository.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import Combine
import Foundation
import SwiftUI

final class DeviceRepository: DeviceRepositoryProtocol {  // Conform to the protocol defined in Domain

    @Published var devices: [AndroidDevice] = []
    @Published var apps: [AndroidApp] = []  // Assuming AndroidApp is also defined in Domain or a shared module
    @Published var error: String? = nil  // Changed to String? as per your code
    @Published var isLoading: Bool = false
    @Published var isLoadingApps: Bool = false
    @Published var previousDevices: [PreviousDevice] = []

    public var errorPublisher: AnyPublisher<String?, Never> { $error.eraseToAnyPublisher() }
    public var devicesPublisher: AnyPublisher<[AndroidDevice], Never> {
        $devices.eraseToAnyPublisher()
    }
    public var appsPublisher: AnyPublisher<[AndroidApp], Never> { $apps.eraseToAnyPublisher() }  // Assuming AndroidApp is defined
    public var isLoadingPublisher: AnyPublisher<Bool, Never> { $isLoading.eraseToAnyPublisher() }
    public var isLoadingAppsPublisher: AnyPublisher<Bool, Never> {
        $isLoadingApps.eraseToAnyPublisher()
    }
    public var previousDevicesPublisher: AnyPublisher<[PreviousDevice], Never> {
        $previousDevices.eraseToAnyPublisher()
    }

    public var imagesPublisher: AnyPublisher<[SystemImage], Never> {
        emulatorService.imagesPublisher.eraseToAnyPublisher()
    }
    public var avdsPublisher: AnyPublisher<[AVD], Never> {
        emulatorService.avdsPublisher.eraseToAnyPublisher()
    }
    public var downloadProgressPublisher: AnyPublisher<(String, Double), Never> {
        emulatorService.downloadProgress.eraseToAnyPublisher()
    }

    public var adbPath: String? { adbService.adbPath }

    private let commandLineToolsPathKey = "android_command_line_tools_path"
    private var didAttemptAutoDetect = false

    public var commandLineToolsPath: String? {
        if let saved = UserDefaults.standard.string(forKey: commandLineToolsPathKey),
            !saved.isEmpty
        {
            return saved
        }
        // Auto-detect on first access only
        if !didAttemptAutoDetect {
            didAttemptAutoDetect = true
            if let detected = AppConstants.detectCmdlineToolsPath() {
                UserDefaults.standard.set(detected, forKey: commandLineToolsPathKey)
                return detected
            }
        }
        return nil
    }

    /// Returns the effective tools path (auto-detected or user-configured), or nil if unavailable.
    private var effectiveToolsPath: String? {
        guard let path = commandLineToolsPath, !path.isEmpty else { return nil }
        return path
    }

    func setCommandLineToolsPath(_ path: String) {
        if path.isEmpty {
            UserDefaults.standard.removeObject(forKey: commandLineToolsPathKey)
            didAttemptAutoDetect = false
        } else {
            UserDefaults.standard.set(path, forKey: commandLineToolsPathKey)
        }
        objectWillChange.send()
    }

    private let avdPathKey = "android_avd_path"
    public var avdPath: String? {
        UserDefaults.standard.string(forKey: avdPathKey)
    }

    func setAVDPath(_ path: String?) {
        if let path, !path.isEmpty {
            UserDefaults.standard.set(path, forKey: avdPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: avdPathKey)
        }
        objectWillChange.send()
    }

    private let imageDownloadPathKey = "android_image_download_path"
    public var imageDownloadPath: String? {
        UserDefaults.standard.string(forKey: imageDownloadPathKey)
    }

    func setImageDownloadPath(_ path: String?) {
        if let path, !path.isEmpty {
            UserDefaults.standard.set(path, forKey: imageDownloadPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: imageDownloadPathKey)
        }
        objectWillChange.send()
    }

    private let emulatorPathKey = "android_emulator_path"
    public var emulatorPath: String? {
        UserDefaults.standard.string(forKey: emulatorPathKey)
    }

    func setEmulatorPath(_ path: String?) {
        if let path, !path.isEmpty {
            UserDefaults.standard.set(path, forKey: emulatorPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: emulatorPathKey)
        }
        objectWillChange.send()
    }

    private let avdLaunchFlagsKey = "avd_launch_flags"
    private var avdLaunchFlagsRaw: [String: String] {
        get {
            UserDefaults.standard.dictionary(forKey: avdLaunchFlagsKey) as? [String: String] ?? [:]
        }
        set { UserDefaults.standard.set(newValue, forKey: avdLaunchFlagsKey) }
    }

    func getLaunchFlags(for avdName: String) -> LaunchFlags {
        guard let jsonStr = avdLaunchFlagsRaw[avdName],
            let data = jsonStr.data(using: .utf8),
            let flags = try? JSONDecoder().decode(LaunchFlags.self, from: data)
        else { return LaunchFlags.default }
        return flags
    }

    func setLaunchFlags(for avdName: String, flags: LaunchFlags) {
        if flags == LaunchFlags.default {
            avdLaunchFlagsRaw.removeValue(forKey: avdName)
            UserDefaults.standard.set(avdLaunchFlagsRaw, forKey: avdLaunchFlagsKey)
        } else if let data = try? JSONEncoder().encode(flags),
            let jsonStr = String(data: data, encoding: .utf8)
        {
            avdLaunchFlagsRaw[avdName] = jsonStr
            UserDefaults.standard.set(avdLaunchFlagsRaw, forKey: avdLaunchFlagsKey)
        }
    }

    // MARK: - Previous Wireless Devices

    private let previousDevicesKey = "previous_wireless_devices"
    private var lastKnownConnectedWireless: [String: AndroidDevice] = [:]  // serial → device

    private func loadPreviousDevices() {
        guard let data = UserDefaults.standard.data(forKey: previousDevicesKey),
            let decoded = try? JSONDecoder().decode([PreviousDevice].self, from: data)
        else { return }
        previousDevices = decoded
    }

    private func savePreviousDevices() {
        if let data = try? JSONEncoder().encode(previousDevices) {
            UserDefaults.standard.set(data, forKey: previousDevicesKey)
        }
    }

    private func syncPreviousDevices(liveDevices: [AndroidDevice]) {
        let liveSerials = Set(liveDevices.map(\.serialNumber).compactMap { $0 })

        // Remove from previous if now connected
        let beforeCount = previousDevices.count
        previousDevices.removeAll { liveSerials.contains($0.serialNumber) }

        // Detect wireless devices that went offline (were connected, now gone)
        for (serial, prevDevice) in lastKnownConnectedWireless {
            if !liveSerials.contains(serial),
                prevDevice.id.contains(":") || prevDevice.id.contains("_tcp")
                    || prevDevice.id.contains("_udp")
            {
                let entry = PreviousDevice(
                    serialNumber: serial,
                    name: prevDevice.name,
                    model: prevDevice.model,
                    lastKnownHost: prevDevice.id,
                    lastConnectedDate: Date()
                )
                previousDevices.removeAll { $0.serialNumber == serial }
                previousDevices.insert(entry, at: 0)
            }
        }

        // Update tracking of connected wireless devices
        lastKnownConnectedWireless.removeAll()
        for device in liveDevices {
            if let serial = device.serialNumber,
                device.id.contains(":") || device.id.contains("_tcp")
                    || device.id.contains("_udp")
            {
                lastKnownConnectedWireless[serial] = device
            }
        }

        if previousDevices.count != beforeCount {
            savePreviousDevices()
        }
    }

    func removePreviousDevice(serialNumber: String) {
        previousDevices.removeAll { $0.serialNumber == serialNumber }
        savePreviousDevices()
    }

    func connectToPreviousDevice(_ device: PreviousDevice) {
        let hostPort = device.lastKnownHost

        adbService.connectToHost(hostPort) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.refreshDevices()
                } else {
                    self?.error = "Failed to connect to \(device.name)"
                }
            }
        }
    }

    // Dependencies (assuming these protocols are defined elsewhere, e.g., in a Service layer)
    private let adbService: ADBServiceProtocol  // Assuming ADBServiceProtocol is defined elsewhere
    private let scrcpyService: ScrcpyServiceProtocol  // Assuming ScrcpyServiceProtocol is defined elsewhere
    private let emulatorService: EmulatorServiceProtocol
    private var cancellables = Set<AnyCancellable>()

    // App cache storage: [serialNumber: [apps]]
    private var appCache: [String: [AndroidApp]] = [:]

    // Store the deviceID for which apps are currently being fetched.
    // This is used for UI updates (to display the correct app list), not for caching.
    private var currentFetchingDeviceID: String?

    // A mapping from ADB's reported deviceID to its actual serialNumber
    // This helps in looking up the serial number when an app list comes in for a deviceID.
    private var deviceIDToSerialNumberMap: [String: String] = [:]

    // Mapping from Serial Number (emulator-5554) to AVD Name (Pixel)
    private var serialToAVDNameMap: [String: String] = [:]

    // Initialize with dependencies
    init(
        adbService: ADBServiceProtocol, scrcpyService: ScrcpyServiceProtocol,
        emulatorService: EmulatorServiceProtocol
    ) {
        self.adbService = adbService
        self.scrcpyService = scrcpyService
        self.emulatorService = emulatorService
        loadPreviousDevices()
        setupBindings()
    }

    // Setup bindings to observe the ADBService
    private func setupBindings() {
        adbService.devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                guard let self = self else { return }

                var updatedDevices = devices
                // Override names for emulators if we have a mapping
                for i in 0..<updatedDevices.count {
                    if let serial = updatedDevices[i].serialNumber,
                        let avdName = self.serialToAVDNameMap[serial]
                    {
                        updatedDevices[i].name = avdName
                        updatedDevices[i].model = avdName
                    }
                }

                self.devices = updatedDevices
                self.isLoading = false

                // Sync previous devices: remove ones that are now connected
                self.syncPreviousDevices(liveDevices: updatedDevices)

                // Update the deviceID to serial number map
                self.deviceIDToSerialNumberMap = updatedDevices.compactMap { device in
                    if let serial = device.serialNumber {
                        return (device.id, serial)
                    }
                    return nil
                }
                .reduce(into: [:]) { $0[$1.0] = $1.1 }
            }
            .store(in: &cancellables)

        // Listen for AVD updates from EmulatorService to maintain the serial-to-name mapping
        emulatorService.avdsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] avds in
                guard let self = self else { return }
                // Update our serial to name map
                for avd in avds {
                    if let serial = avd.serial, !serial.isEmpty {
                        self.serialToAVDNameMap[serial] = avd.name
                    }
                }
                // Re-apply naming to current devices
                var updatedDevices = self.devices
                var changed = false
                for i in 0..<updatedDevices.count {
                    if let serial = updatedDevices[i].serialNumber,
                        let avdName = self.serialToAVDNameMap[serial]
                    {
                        if updatedDevices[i].name != avdName || updatedDevices[i].model != avdName {
                            updatedDevices[i].name = avdName
                            updatedDevices[i].model = avdName
                            changed = true
                        }
                    }
                }
                if changed {
                    self.devices = updatedDevices
                }
            }
            .store(in: &cancellables)

        // Observe apps from adbService
        // adbService.apps now publishes (deviceID, [AndroidApp])
        adbService.apps
            .receive(on: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (receivedDeviceID, apps: [AndroidApp]) in
                guard let self = self else { return }

                // Always reset loading state when we get a response
                self.isLoadingApps = false

                // Try to use the serial number as the cache key
                if let serialNumber = self.deviceIDToSerialNumberMap[receivedDeviceID] {
                    self.appCache[serialNumber] = apps

                    // If the received apps are for the currently selected device, update the UI
                    if let currentDeviceID = self.currentFetchingDeviceID,
                        let currentDevice = self.devices.first(where: { $0.id == currentDeviceID }),
                        currentDevice.serialNumber == serialNumber
                    {
                        self.apps = apps
                    }
                } else {
                    // Fallback if serial number not found
                    if receivedDeviceID == self.currentFetchingDeviceID {
                        self.apps = apps
                    }
                    if self.deviceIDToSerialNumberMap[receivedDeviceID] == nil {
                        // Only log if we really don't know this device
                        // self.error = "⚠️ Received apps for an untracked deviceID..." // Optional logging
                    }
                }
            }
            .store(in: &cancellables)

        adbService.error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (error: String?) in
                self?.error = error
                if error != nil {
                    self?.isLoading = false
                    self?.isLoadingApps = false
                }
                if let error = error {
                    AlertPresenter.showWarning(message: error)
                }
            }
            .store(in: &cancellables)

        emulatorService.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (error: String?) in
                if let error = error {
                    self?.error = error
                    self?.isLoading = false
                    AlertPresenter.showWarning(message: error)
                }
            }
            .store(in: &cancellables)

    }

    // MARK: - DeviceRepositoryProtocol Methods

    func refreshDevices() {
        isLoading = true
        error = nil
        // Clear deviceID-to-serial map as IDs might change, but KEEP app cache (keyed by serial)
        // so we don't re-fetch apps unnecessarily when just refreshing device status.
        deviceIDToSerialNumberMap.removeAll()
        adbService.findADB()
    }

    func fetchApps(for deviceID: String) {
        // Find the AndroidDevice to get its serial number
        guard let device = devices.first(where: { $0.id == deviceID }) else {
            self.error = "Device with ID \(deviceID) not found to fetch apps."  // Corrected
            self.apps = []
            return
        }

        guard let serialNumber = device.serialNumber else {
            self.error = "Serial number not available for device \(deviceID). Cannot cache apps."  // Corrected
            self.apps = []
            // Proceed to fetch without caching if no serial, but log the issue.
            currentFetchingDeviceID = deviceID  // Still track it for UI update
            adbService.fetchApps(for: deviceID)
            return
        }

        // Check if apps are already cached for this serial number
        if let cachedApps = appCache[serialNumber] {
            DispatchQueue.main.async {
                self.apps = cachedApps
            }
            // Update currentFetchingDeviceID to ensure subsequent UI updates or actions
            // are correctly attributed to this device, even if cached.
            currentFetchingDeviceID = deviceID
            return
        }

        // Not cached, fetch from ADB service
        currentFetchingDeviceID = deviceID  // This is the ADB deviceID, used to trigger the ADBService call
        isLoadingApps = true
        adbService.fetchApps(for: deviceID)
        // Clear previous apps when fetching new ones for UI
        DispatchQueue.main.async {
            self.apps = []
        }
    }

    func forceRefreshApps(for deviceID: String) {
        guard let device = devices.first(where: { $0.id == deviceID }) else {
            self.error = "Device with ID \(deviceID) not found to force refresh apps."  // Corrected
            self.apps = []
            return
        }

        // Clear cache for this device's serial number and force a fresh fetch
        if let serialNumber = device.serialNumber {
            appCache.removeValue(forKey: serialNumber)
        } else {
            // If no serial number, we can't clear by serial. Log an error or fallback.
            self.error =
                "Cannot force refresh apps by serial for device \(deviceID): no serial number."  // Corrected
        }

        currentFetchingDeviceID = deviceID
        isLoadingApps = true
        adbService.fetchApps(for: deviceID)
        DispatchQueue.main.async {
            self.apps = []
        }
    }

    // Audio Preferences
    private var audioPreferences: [String: Bool] = [:]  // Keyed by device ID (or serial if available)

    func toggleAudio(for deviceID: String) {
        let current = isAudioEnabled(for: deviceID)
        audioPreferences[deviceID] = !current
    }

    func isAudioEnabled(for deviceID: String) -> Bool {
        return audioPreferences[deviceID] ?? true  // Default to true
    }

    // Clipboard Preferences
    private var clipboardPreferences: [String: Bool] = [:]  // Keyed by device ID

    func toggleClipboard(for deviceID: String) {
        let current = isClipboardEnabled(for: deviceID)
        let newState = !current
        clipboardPreferences[deviceID] = newState

        if newState {
            adbService.startClipboardSync(deviceID: deviceID)
        } else {
            adbService.stopClipboardSync(deviceID: deviceID)
        }
    }

    func isClipboardEnabled(for deviceID: String) -> Bool {
        return clipboardPreferences[deviceID] ?? false  // Default to false if we want explicit enable, or true? User said "toggle is on... automatically copied". Let's default to false so they have to turn it on to start the process.
    }

    // Resolution Preferences
    private var resolutionPreferences: [String: Int] = [:]  // Keyed by device ID

    func setResolution(for deviceID: String, resolution: Int) {
        resolutionPreferences[deviceID] = resolution
    }

    func getResolution(for deviceID: String) -> Int {
        return resolutionPreferences[deviceID] ?? 900  // Default to 900p
    }

    // Mirroring Size Preferences (for Mirroring)
    private var maxSizePreferences: [String: Int] = [:]  // Keyed by device ID

    func setMaxSize(for deviceID: String, size: Int) {
        maxSizePreferences[deviceID] = size
    }

    func getMaxSize(for deviceID: String) -> Int {
        return maxSizePreferences[deviceID] ?? 0  // Default to 0 (Original/No Limit)
    }

    // FPS Preferences
    private var fpsPreferences: [String: Int] = [:]

    func setMaxFPS(for deviceID: String, fps: Int) {
        fpsPreferences[deviceID] = fps
    }

    func getMaxFPS(for deviceID: String) -> Int {
        return fpsPreferences[deviceID] ?? 0  // Default 0 (Unlimited)
    }

    // Bit Rate Preferences
    private var bitRatePreferences: [String: Int] = [:]

    func setBitRate(for deviceID: String, bitRate: Int) {
        bitRatePreferences[deviceID] = bitRate
    }

    func getBitRate(for deviceID: String) -> Int {
        return bitRatePreferences[deviceID] ?? 8  // Default 8 Mbps
    }

    // Borderless Preferences
    private var borderlessPreferences: [String: Bool] = [:]

    func toggleBorderless(for deviceID: String) {
        let current = isBorderlessEnabled(for: deviceID)
        borderlessPreferences[deviceID] = !current
    }

    func isBorderlessEnabled(for deviceID: String) -> Bool {
        return borderlessPreferences[deviceID] ?? false  // Default false
    }

    private var flexDisplayPreferences: [String: Bool] = [:]

    func toggleFlexDisplay(for deviceID: String) {
        let current = isFlexDisplayEnabled(for: deviceID)
        flexDisplayPreferences[deviceID] = !current
    }

    func isFlexDisplayEnabled(for deviceID: String) -> Bool {
        return flexDisplayPreferences[deviceID] ?? false  // Default false
    }

    // Orientation Preferences
    private var orientationPreferences: [String: String] = [:]
    private var captureOrientationEnabledPreferences: [String: Bool] = [:]

    func setOrientation(for deviceID: String, orientation: String) {
        orientationPreferences[deviceID] = orientation
        // Auto-enable when a specific orientation is selected
        if orientation != "Auto" {
            captureOrientationEnabledPreferences[deviceID] = true
        } else {
            captureOrientationEnabledPreferences[deviceID] = false
        }
    }

    func getOrientation(for deviceID: String) -> String {
        let isEnabled = isCaptureOrientationEnabled(for: deviceID)
        if !isEnabled { return "Auto" }
        return orientationPreferences[deviceID] ?? "0"  // Default to 0 if enabled but not set
    }

    func toggleCaptureOrientation(for deviceID: String) {
        let current = isCaptureOrientationEnabled(for: deviceID)
        captureOrientationEnabledPreferences[deviceID] = !current
    }

    func isCaptureOrientationEnabled(for deviceID: String) -> Bool {
        return captureOrientationEnabledPreferences[deviceID] ?? false
    }

    // Camera Preferences
    private var cameraFacingPreferences: [String: String] = [:]
    private var cameraFPSPreferences: [String: Int] = [:]
    private var cameraSizePreferences: [String: Int] = [:]
    private var cameraARPreferences: [String: String] = [:]

    func setCameraFacing(for deviceID: String, facing: String) {
        cameraFacingPreferences[deviceID] = facing
    }

    func getCameraFacing(for deviceID: String) -> String {
        return cameraFacingPreferences[deviceID] ?? "Auto"
    }

    func setCameraFPS(for deviceID: String, fps: Int) {
        cameraFPSPreferences[deviceID] = fps
    }

    func getCameraFPS(for deviceID: String) -> Int {
        return cameraFPSPreferences[deviceID] ?? 0  // Default 0 (Default/30)
    }

    func setCameraSize(for deviceID: String, size: Int) {
        cameraSizePreferences[deviceID] = size
    }

    func getCameraSize(for deviceID: String) -> Int {
        return cameraSizePreferences[deviceID] ?? 0  // Default 0 (Original)
    }

    func setCameraAR(for deviceID: String, ar: String) {
        cameraARPreferences[deviceID] = ar
    }

    func getCameraAR(for deviceID: String) -> String {
        return cameraARPreferences[deviceID] ?? "Auto"
    }

    func mirrorCamera(deviceID: String) {
        let audioEnabled = isAudioEnabled(for: deviceID)
        let facing = getCameraFacing(for: deviceID)
        let fps = getCameraFPS(for: deviceID)
        let size = getCameraSize(for: deviceID)
        let ar = getCameraAR(for: deviceID)
        let bitRate = getBitRate(for: deviceID)  // Reuse bit rate
        let orientation = getOrientation(for: deviceID)

        let deviceName = devices.first(where: { $0.id == deviceID })?.name

        adbService.mirrorCamera(
            deviceID: deviceID,
            deviceName: deviceName,
            audioEnabled: audioEnabled,
            facing: facing,
            fps: fps,
            size: size,
            bitRate: bitRate,
            orientation: orientation,
            aspectRatio: ar
        )
    }

    func launchApp(packageID: String, deviceID: String, appName: String) {
        let audioEnabled = isAudioEnabled(for: deviceID)
        let clipboardEnabled = isClipboardEnabled(for: deviceID)
        let resolution = getResolution(for: deviceID)
        let flexDisplay = isFlexDisplayEnabled(for: deviceID)
        let deviceName = devices.first(where: { $0.id == deviceID })?.name
        adbService.launchApp(
            packageID: packageID, deviceID: deviceID, appName: appName, deviceName: deviceName,
            audioEnabled: audioEnabled, resolution: resolution, clipboardEnabled: clipboardEnabled,
            flexDisplay: flexDisplay)
    }

    func mirrorDevice(deviceID: String) {
        let audioEnabled = isAudioEnabled(for: deviceID)
        let clipboardEnabled = isClipboardEnabled(for: deviceID)
        let maxSize = getMaxSize(for: deviceID)
        let maxFPS = getMaxFPS(for: deviceID)
        let bitRate = getBitRate(for: deviceID)
        let orientation = getOrientation(for: deviceID)
        let flexDisplay = isFlexDisplayEnabled(for: deviceID)

        let deviceName = devices.first(where: { $0.id == deviceID })?.name
        adbService.mirrorDevice(
            deviceID: deviceID,
            deviceName: deviceName,
            audioEnabled: audioEnabled,
            clipboardEnabled: clipboardEnabled,
            maxSize: maxSize,
            maxFPS: maxFPS,
            bitRate: bitRate,
            orientation: orientation,
            borderless: isBorderlessEnabled(for: deviceID),
            flexDisplay: flexDisplay
        )
    }

    func launchCamera(deviceID: String, facing: CameraFacing) {
        adbService.launchCamera(deviceID: deviceID, facing: facing)
    }

    func disconnectDevice(deviceID: String) {
        // Save wireless device to previous devices before disconnecting
        if let device = devices.first(where: { $0.id == deviceID }),
            let serialNumber = device.serialNumber,
            deviceID.contains(":") || deviceID.contains("_tcp")
                || deviceID.contains("_udp")
        {
            let entry = PreviousDevice(
                serialNumber: serialNumber,
                name: device.name,
                model: device.model,
                lastKnownHost: deviceID,
                lastConnectedDate: Date()
            )
            // Update or insert
            previousDevices.removeAll { $0.serialNumber == serialNumber }
            previousDevices.insert(entry, at: 0)
            savePreviousDevices()

            appCache.removeValue(forKey: serialNumber)
        }
        adbService.disconnectDevice(deviceID: deviceID)
    }

    func installAPK(deviceID: String, apkPath: String) {
        adbService.installAPK(deviceID: deviceID, apkPath: apkPath)
    }

    func uninstallApp(deviceID: String, packageID: String) {
        adbService.uninstallApp(deviceID: deviceID, packageID: packageID)
    }

    func clearAppData(deviceID: String, packageID: String) {
        adbService.clearAppData(deviceID: deviceID, packageID: packageID)
    }

    // MARK: - Quick Actions
    func reboot(deviceID: String, mode: RebootMode) {
        adbService.reboot(deviceID: deviceID, mode: mode)
    }

    func toggleWiFi(deviceID: String, enable: Bool) {
        adbService.toggleWiFi(deviceID: deviceID, enable: enable)
    }

    func toggleBluetooth(deviceID: String, enable: Bool) {
        adbService.toggleBluetooth(deviceID: deviceID, enable: enable)
    }

    func toggleDarkMode(deviceID: String, enable: Bool) {
        adbService.toggleDarkMode(deviceID: deviceID, enable: enable)
    }

    func toggleAirplaneMode(deviceID: String, enable: Bool) {
        adbService.toggleAirplaneMode(deviceID: deviceID, enable: enable)
    }

    func toggleMobileData(deviceID: String, enable: Bool) {
        adbService.toggleMobileData(deviceID: deviceID, enable: enable)
    }

    func toggleLocation(deviceID: String, enable: Bool) {
        adbService.toggleLocation(deviceID: deviceID, enable: enable)
    }

    func toggleDoNotDisturb(deviceID: String, enable: Bool) {
        adbService.toggleDoNotDisturb(deviceID: deviceID, enable: enable)
    }

    func toggleAutoRotate(deviceID: String, enable: Bool) {
        adbService.toggleAutoRotate(deviceID: deviceID, enable: enable)
    }

    func setRingerMode(deviceID: String, mode: RingerMode) {
        adbService.setRingerMode(deviceID: deviceID, mode: mode)
    }

    func toggleAdaptiveBrightness(deviceID: String, enable: Bool) {
        adbService.toggleAdaptiveBrightness(deviceID: deviceID, enable: enable)
    }

    func fetchQuickActionsState(deviceID: String, completion: @escaping (QuickActionsState) -> Void)
    {
        adbService.fetchQuickActionsState(deviceID: deviceID, completion: completion)
    }

    // MARK: - Emulator Manager
    func listAvailableImages() {
        guard let toolsPath = effectiveToolsPath else {
            self.error = "Android Command Line Tools path not set in Preferences."
            return
        }
        emulatorService.listAvailableImages(toolsPath: toolsPath, sdkRoot: imageDownloadPath)
    }

    func downloadImage(imagePath: String) {
        guard let toolsPath = effectiveToolsPath else {
            self.error = "Android Command Line Tools path not set in Preferences."
            return
        }
        emulatorService.downloadImage(
            toolsPath: toolsPath, imagePath: imagePath, sdkRoot: imageDownloadPath)
    }

    func deleteImage(imagePath: String) {
        guard let toolsPath = effectiveToolsPath else {
            self.error = "Android Command Line Tools path not set in Preferences."
            return
        }
        emulatorService.deleteImage(
            toolsPath: toolsPath, imagePath: imagePath, sdkRoot: imageDownloadPath)
    }

    func listAVDs() {
        guard let toolsPath = effectiveToolsPath else {
            self.error = "Android Command Line Tools path not set in Preferences."
            return
        }
        emulatorService.listAVDs(toolsPath: toolsPath, avdPath: avdPath)
    }

    func listHardwareProfiles(completion: @escaping ([HardwareProfile]) -> Void) {
        guard let toolsPath = effectiveToolsPath else {
            completion([])
            return
        }
        emulatorService.listHardwareProfiles(toolsPath: toolsPath, completion: completion)
    }

    func createAVD(name: String, imagePath: String, device: String?, options: AVDOptions) {
        guard let toolsPath = effectiveToolsPath else {
            self.error = "Android Command Line Tools path not set in Preferences."
            return
        }
        emulatorService.createAVD(
            toolsPath: toolsPath, name: name, imagePath: imagePath, device: device,
            options: options,
            avdPath: avdPath, sdkRoot: imageDownloadPath
        )
    }

    func deleteAVD(name: String) {
        guard let toolsPath = effectiveToolsPath else {
            self.error = "Android Command Line Tools path not set in Preferences."
            return
        }
        emulatorService.deleteAVD(toolsPath: toolsPath, name: name, avdPath: avdPath)
    }

    func renameAVD(oldName: String, newName: String) {
        guard let toolsPath = effectiveToolsPath else {
            self.error = "Android Command Line Tools path not set in Preferences."
            return
        }
        emulatorService.renameAVD(
            toolsPath: toolsPath, oldName: oldName, newName: newName, avdPath: avdPath)
    }

    func startEmulator(avdName: String, launchFlags: LaunchFlags = LaunchFlags.default) {
        guard let toolsPath = effectiveToolsPath else {
            self.error = "Android Command Line Tools path not set in Preferences."
            return
        }
        emulatorService.startEmulator(
            toolsPath: toolsPath, avdName: avdName, avdPath: avdPath,
            emulatorPath: emulatorPath, launchFlags: launchFlags)

        // After starting, refresh devices to see it appearing
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.refreshDevices()
        }
    }
    func stopEmulator(avdName: String) {
        guard let toolsPath = effectiveToolsPath else {
            self.error = "Android Command Line Tools path not set in Preferences."
            return
        }
        emulatorService.stopEmulator(toolsPath: toolsPath, avdName: avdName)
    }

    func isEmulatorProcessRunning(avdName: String) -> Bool {
        emulatorService.isEmulatorProcessRunning(avdName: avdName)
    }

    func cancelDownload(imagePath: String) {
        emulatorService.cancelDownload(imagePath: imagePath)
    }

    // File Management
    func listFiles(
        for deviceID: String, at path: String,
        completion: @escaping (Result<[AndroidFile], Error>) -> Void
    ) {
        adbService.listFiles(for: deviceID, at: path, completion: completion)
    }

    func pushFile(
        deviceID: String, localPath: String, remotePath: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        adbService.pushFile(
            deviceID: deviceID, localPath: localPath, remotePath: remotePath, completion: completion
        )
    }

    func pullFile(
        deviceID: String, remotePath: String, localPath: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        adbService.pullFile(
            deviceID: deviceID, remotePath: remotePath, localPath: localPath, completion: completion
        )
    }

    func deleteFile(
        deviceID: String, path: String, completion: @escaping (Result<Void, Error>) -> Void
    ) {
        adbService.deleteFile(deviceID: deviceID, path: path, completion: completion)
    }

    func createDirectory(
        deviceID: String, path: String, completion: @escaping (Result<Void, Error>) -> Void
    ) {
        adbService.createDirectory(deviceID: deviceID, path: path, completion: completion)
    }
}
