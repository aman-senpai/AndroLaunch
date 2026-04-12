//
//  DeviceRepositoryProtocol.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import Combine
import SwiftUI

protocol DeviceRepositoryProtocol: ObservableObject {
    var objectWillChange: ObservableObjectPublisher { get }
    var errorPublisher: AnyPublisher<String?, Never> { get }
    var devicesPublisher: AnyPublisher<[AndroidDevice], Never> { get }
    var appsPublisher: AnyPublisher<[AndroidApp], Never> { get }
    var isLoadingPublisher: AnyPublisher<Bool, Never> { get }
    var isLoadingAppsPublisher: AnyPublisher<Bool, Never> { get }
    var imagesPublisher: AnyPublisher<[SystemImage], Never> { get }
    var avdsPublisher: AnyPublisher<[AVD], Never> { get }
    var downloadProgressPublisher: AnyPublisher<(String, Double), Never> { get }
    
    var devices: [AndroidDevice] { get }
    var apps: [AndroidApp] { get }
    var error: String? { get }
    var isLoading: Bool { get }
    var isLoadingApps: Bool { get }
    var adbPath: String? { get }
    var commandLineToolsPath: String? { get }
    
    func setCommandLineToolsPath(_ path: String)
    
    func refreshDevices()
    func fetchApps(for deviceID: String)
    func forceRefreshApps(for deviceID: String)
    func launchApp(packageID: String, deviceID: String, appName: String)
    func mirrorDevice(deviceID: String)
    func launchCamera(deviceID: String, facing: CameraFacing)
    func disconnectDevice(deviceID: String)
    func installAPK(deviceID: String, apkPath: String)
    func uninstallApp(deviceID: String, packageID: String)
    func clearAppData(deviceID: String, packageID: String)
    
    func toggleAudio(for deviceID: String)
    func isAudioEnabled(for deviceID: String) -> Bool
    
    func toggleClipboard(for deviceID: String)
    func isClipboardEnabled(for deviceID: String) -> Bool
    
    func setResolution(for deviceID: String, resolution: Int)
    func getResolution(for deviceID: String) -> Int
    
    func setMaxSize(for deviceID: String, size: Int)
    func getMaxSize(for deviceID: String) -> Int
    
    func setMaxFPS(for deviceID: String, fps: Int)
    func getMaxFPS(for deviceID: String) -> Int
    
    func setBitRate(for deviceID: String, bitRate: Int)
    func getBitRate(for deviceID: String) -> Int
    
    func setOrientation(for deviceID: String, orientation: String)
    func getOrientation(for deviceID: String) -> String
    
    func toggleCaptureOrientation(for deviceID: String)
    func isCaptureOrientationEnabled(for deviceID: String) -> Bool
    
    func toggleBorderless(for deviceID: String)
    func isBorderlessEnabled(for deviceID: String) -> Bool
    
    // Camera Preferences
    func setCameraFacing(for deviceID: String, facing: String)
    func getCameraFacing(for deviceID: String) -> String
    
    func setCameraFPS(for deviceID: String, fps: Int)
    func getCameraFPS(for deviceID: String) -> Int
    
    func setCameraSize(for deviceID: String, size: Int)
    func getCameraSize(for deviceID: String) -> Int
    
    func setCameraAR(for deviceID: String, ar: String)
    func getCameraAR(for deviceID: String) -> String
    
    func mirrorCamera(deviceID: String)
    
    // Quick Actions
    func reboot(deviceID: String, mode: RebootMode)
    func toggleWiFi(deviceID: String, enable: Bool)
    func toggleBluetooth(deviceID: String, enable: Bool)
    func toggleDarkMode(deviceID: String, enable: Bool)
    
    func toggleAirplaneMode(deviceID: String, enable: Bool)
    func toggleMobileData(deviceID: String, enable: Bool)
    func toggleLocation(deviceID: String, enable: Bool)
    func toggleDoNotDisturb(deviceID: String, enable: Bool)
    func toggleAutoRotate(deviceID: String, enable: Bool)
    func setRingerMode(deviceID: String, mode: RingerMode)
    func toggleAdaptiveBrightness(deviceID: String, enable: Bool)
    
    func fetchQuickActionsState(deviceID: String, completion: @escaping (QuickActionsState) -> Void)
    
    // Emulator Manager
    func listAvailableImages()
    func downloadImage(imagePath: String)
    func cancelDownload(imagePath: String)
    func deleteImage(imagePath: String)
    func listAVDs()
    func listHardwareProfiles(completion: @escaping ([HardwareProfile]) -> Void)
    func createAVD(name: String, imagePath: String, device: String?, options: AVDOptions)
    func deleteAVD(name: String)
    func renameAVD(oldName: String, newName: String)
    func startEmulator(avdName: String)
    func stopEmulator(avdName: String)
    
    // File Management
    func listFiles(for deviceID: String, at path: String, completion: @escaping (Result<[AndroidFile], Error>) -> Void)
    func pushFile(deviceID: String, localPath: String, remotePath: String, completion: @escaping (Result<Void, Error>) -> Void)
    func pullFile(deviceID: String, remotePath: String, localPath: String, completion: @escaping (Result<Void, Error>) -> Void)
    func deleteFile(deviceID: String, path: String, completion: @escaping (Result<Void, Error>) -> Void)
    func createDirectory(deviceID: String, path: String, completion: @escaping (Result<Void, Error>) -> Void)
}
