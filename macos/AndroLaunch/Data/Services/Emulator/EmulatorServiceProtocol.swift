//
//  EmulatorServiceProtocol.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 16/1/26.
//

import Combine
import Foundation

protocol EmulatorServiceProtocol {
    var imagesPublisher: AnyPublisher<[SystemImage], Never> { get }
    var avdsPublisher: AnyPublisher<[AVD], Never> { get }
    var downloadProgress: AnyPublisher<(String, Double), Never> { get } // (imagePath, progress 0-1)
    var errorPublisher: AnyPublisher<String?, Never> { get }
    
    func listAvailableImages(toolsPath: String)
    func downloadImage(toolsPath: String, imagePath: String)
    func cancelDownload(imagePath: String)
    func deleteImage(toolsPath: String, imagePath: String)
    func listAVDs(toolsPath: String)
    func listHardwareProfiles(toolsPath: String, completion: @escaping ([HardwareProfile]) -> Void)
    func createAVD(toolsPath: String, name: String, imagePath: String, device: String?, options: AVDOptions)
    func deleteAVD(toolsPath: String, name: String)
    func renameAVD(toolsPath: String, oldName: String, newName: String)
    func startEmulator(toolsPath: String, avdName: String)
    func stopEmulator(toolsPath: String, avdName: String)
}

struct SystemImage: Identifiable, Codable {
    let id: String // e.g. "system-images;android-33;google_apis;arm64-v8a"
    let description: String
    let isDownloaded: Bool
    let sizeBytes: Int64?
}

struct AVD: Identifiable, Codable {
    var id: String { name }
    let name: String
    let device: String?
    let path: String?
    let target: String?
    var isRunning: Bool = false
    var isStarting: Bool = false
    var isStopping: Bool = false
    var serial: String? = nil
}

struct HardwareProfile: Identifiable, Codable {
    let id: String
    let name: String
    let oem: String?
    let width: Int?
    let height: Int?
    let density: Int?
}

struct AVDOptions: Codable {
    var ramMB: Int?
    var heapMB: Int?
    var storageMB: Int?
    var width: Int?
    var height: Int?
    var density: Int?
    var sdCardMB: Int?
    var cameraBack: String? // "emulated", "webcam0", "none"
    var gps: Bool?
    var keyboard: Bool?
    var gpuMode: String? // "host", "software", "auto"
    var coldBoot: Bool?
    var showDeviceFrame: Bool?
    
    static var `default`: AVDOptions {
        AVDOptions(
            ramMB: 2048,
            heapMB: 512,
            storageMB: 4096,
            width: 1080,
            height: 2400,
            density: 420,
            sdCardMB: 512,
            cameraBack: "emulated",
            gps: true,
            keyboard: true,
            gpuMode: "auto",
            coldBoot: false,
            showDeviceFrame: true
        )
    }
}
