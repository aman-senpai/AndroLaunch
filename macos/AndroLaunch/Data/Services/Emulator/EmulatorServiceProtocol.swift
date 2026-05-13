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
    var downloadProgress: AnyPublisher<(String, Double), Never> { get }  // (imagePath, progress 0-1)
    var errorPublisher: AnyPublisher<String?, Never> { get }

    func listAvailableImages(toolsPath: String, sdkRoot: String?)
    func downloadImage(toolsPath: String, imagePath: String, sdkRoot: String?)
    func cancelDownload(imagePath: String)
    func deleteImage(toolsPath: String, imagePath: String, sdkRoot: String?)
    func listAVDs(toolsPath: String, avdPath: String?)
    func listHardwareProfiles(toolsPath: String, completion: @escaping ([HardwareProfile]) -> Void)
    func createAVD(
        toolsPath: String, name: String, imagePath: String, device: String?, options: AVDOptions,
        avdPath: String?, sdkRoot: String?)
    func deleteAVD(toolsPath: String, name: String, avdPath: String?)
    func renameAVD(toolsPath: String, oldName: String, newName: String, avdPath: String?)
    func startEmulator(
        toolsPath: String, avdName: String, avdPath: String?, emulatorPath: String?,
        launchFlags: LaunchFlags)
    func stopEmulator(toolsPath: String, avdName: String)
    func isEmulatorProcessRunning(avdName: String) -> Bool
}

struct LaunchFlags: Codable, Equatable {
    // Core
    var noAudio: Bool = true
    var noWindow: Bool = true
    var verbose: Bool = true
    var noSkin: Bool = true
    var qtHideWindow: Bool = false

    // Boot
    var wipeData: Bool = false
    var readOnly: Bool = false
    var noBootAnim: Bool = false
    var noJni: Bool = false

    // Snapshot
    var noSnapshotSave: Bool = false
    var noSnapshotLoad: Bool = false
    var snapshot: String = ""

    // GPU
    var gpuMode: String = "host"  // "host", "auto", "swiftshader_indirect", "angle_indirect", "off"

    // Network
    var netSpeed: String = "full"  // "full", "gsm", "hscsd", "gprs", "edge", "umts", "hsdpa", "lte", "evdo"
    var netDelay: String = "none"  // "none", "gprs", "edge", "umts"
    var httpProxy: String = ""
    var dnsServer: String = ""

    // Performance
    var memoryMB: String = ""
    var cores: String = ""
    var port: String = ""

    // Camera
    var cameraBack: String = ""  // "emulated", "webcam0", "none" (empty = AVD default)
    var cameraFront: String = ""

    // Audio
    var audioInput: Bool = false  // overrides hw.audioInput via -prop when enabled
    var audioOutput: Bool = false  // overrides hw.audioOutput via -prop when enabled

    // Extra
    var tcpdump: String = ""
    var timezone: String = ""

    static var `default`: LaunchFlags { LaunchFlags() }
}

enum SystemImageType: String, CaseIterable, Codable {
    case phone = "Phone/Tablet"
    case wearOS = "Wear OS"
    case androidTV = "Android TV"
    case automotive = "Automotive"
    case other = "Other"

    var icon: String {
        switch self {
        case .phone: return "iphone.gen3"
        case .wearOS: return "applewatch"
        case .androidTV: return "tv"
        case .automotive: return "car"
        case .other: return "questionmark.circle"
        }
    }
}

struct SystemImage: Identifiable, Codable, Hashable {
    let id: String  // e.g. "system-images;android-33;google_apis;arm64-v8a"
    let description: String
    let isDownloaded: Bool
    let sizeBytes: Int64?

    var apiLevel: String? {
        let parts = id.components(separatedBy: ";")
        guard parts.count >= 2 else { return nil }
        return parts[1].replacingOccurrences(of: "android-", with: "")
    }

    var variant: String? {
        let parts = id.components(separatedBy: ";")
        guard parts.count >= 3 else { return nil }
        return parts[2]
    }

    var architecture: String? {
        let parts = id.components(separatedBy: ";")
        guard parts.count >= 4 else { return nil }
        return parts[3]
    }

    var osType: SystemImageType {
        guard let v = variant?.lowercased() else { return .other }
        if v == "android-wear" || v == "android-wear-cn" { return .wearOS }
        if v == "android-tv" { return .androidTV }
        if v == "google_apis_atd" || v == "android-automotive" { return .automotive }
        return .phone
    }

    var displayName: String {
        var parts: [String] = []
        if let level = apiLevel { parts.append("API \(level)") }
        if let v = variant { parts.append(formatVariant(v)) }
        if let arch = architecture { parts.append(arch) }
        return parts.isEmpty ? description : parts.joined(separator: " — ")
    }

    private func formatVariant(_ v: String) -> String {
        switch v.lowercased() {
        case "google_apis": return "Google APIs"
        case "google_apis_playstore": return "Google Play"
        case "android-wear": return "Wear OS"
        case "android-wear-cn": return "Wear OS (China)"
        case "android-tv": return "Android TV"
        case "google_apis_atd": return "Automotive"
        case "android-automotive": return "Automotive"
        case "google_apis_ps_uef": return "Google Play (UEF)"
        case "google_atd": return "Google ATD"
        case "aosp_atd": return "AOSP ATD"
        case "default": return "AOSP"
        default:
            if v.hasPrefix("aosp_") {
                return v.replacingOccurrences(of: "aosp_", with: "AOSP ").capitalized
            }
            return v
        }
    }
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
    var cameraBack: String?  // "emulated", "webcam0", "none"
    var gps: Bool?
    var keyboard: Bool?
    var gpuMode: String?  // "host", "software", "auto"
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
