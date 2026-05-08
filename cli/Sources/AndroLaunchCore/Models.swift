import Foundation

// MARK: - AndroidDevice

public struct AndroidDevice: Identifiable, Equatable {
    public let id: String
    public var name: String
    public var model: String?
    public let isConnected: Bool
    public let serialNumber: String?
    public let androidVersion: String?
    public let apiLevel: String?
    public let batteryLevel: Int?
    public let isCharging: Bool?

    public init(
        id: String, name: String, model: String? = nil, isConnected: Bool,
        serialNumber: String? = nil, androidVersion: String? = nil, apiLevel: String? = nil,
        batteryLevel: Int? = nil, isCharging: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.isConnected = isConnected
        self.serialNumber = serialNumber
        self.androidVersion = androidVersion
        self.apiLevel = apiLevel
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
    }
}

// MARK: - AndroidApp

public struct AndroidApp: Identifiable, Codable, Equatable {
    public let id: String
    public let name: String
    public let iconName: String
    public let packageName: String

    public init(id: String, name: String, iconName: String = "android", packageName: String) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.packageName = packageName
    }
}

// MARK: - AndroidFile

public struct AndroidFile: Identifiable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let size: Int64
    public let modificationDate: String?
    public let isDirectory: Bool
    public let permissions: String

    public var extensionName: String {
        return (name as NSString).pathExtension.lowercased()
    }

    public var formattedSize: String {
        if isDirectory { return "--" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    public init(
        name: String, path: String, size: Int64, modificationDate: String?, isDirectory: Bool,
        permissions: String
    ) {
        self.name = name
        self.path = path
        self.size = size
        self.modificationDate = modificationDate
        self.isDirectory = isDirectory
        self.permissions = permissions
    }
}

// MARK: - QuickActionsState

public struct QuickActionsState {
    public var isWifiEnabled: Bool = false
    public var isBluetoothEnabled: Bool = false
    public var isDarkModeEnabled: Bool = false
    public var isAirplaneModeEnabled: Bool = false
    public var isMobileDataEnabled: Bool = false
    public var isLocationEnabled: Bool = false
    public var isDoNotDisturbEnabled: Bool = false
    public var isAutoRotateEnabled: Bool = false
    public var isAdaptiveBrightnessEnabled: Bool = false
    public var ringerMode: RingerMode = .normal

    public init() {}
}

// MARK: - Enums

public enum CameraFacing: String {
    case front
    case back
}

public enum RebootMode: String {
    case normal = ""
    case bootloader = "bootloader"
    case recovery = "recovery"
}

public enum RingerMode: String {
    case normal = "normal"
    case vibrate = "vibrate"
    case silent = "silent"
}

// MARK: - ShellCommand

public struct ShellCommand: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var command: String
    public var isBackground: Bool
    public var isHostCommand: Bool

    public init(
        id: UUID = UUID(), name: String, command: String, isBackground: Bool,
        isHostCommand: Bool = false
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.isBackground = isBackground
        self.isHostCommand = isHostCommand
    }
}

// MARK: - Emulator Models

public enum SystemImageType: String, CaseIterable, Codable {
    case phone = "Phone/Tablet"
    case wearOS = "Wear OS"
    case androidTV = "Android TV"
    case automotive = "Automotive"
    case other = "Other"

    public var icon: String {
        switch self {
        case .phone:      return "iphone.gen3"
        case .wearOS:     return "applewatch"
        case .androidTV:  return "tv"
        case .automotive: return "car"
        case .other:      return "questionmark.circle"
        }
    }
}

public struct SystemImage: Identifiable, Codable {
    public let id: String
    public let description: String
    public let isDownloaded: Bool
    public let sizeBytes: Int64?

    public init(id: String, description: String, isDownloaded: Bool, sizeBytes: Int64?) {
        self.id = id
        self.description = description
        self.isDownloaded = isDownloaded
        self.sizeBytes = sizeBytes
    }

    public var apiLevel: String? {
        let parts = id.components(separatedBy: ";")
        guard parts.count >= 2 else { return nil }
        return parts[1].replacingOccurrences(of: "android-", with: "")
    }

    public var variant: String? {
        let parts = id.components(separatedBy: ";")
        guard parts.count >= 3 else { return nil }
        return parts[2]
    }

    public var architecture: String? {
        let parts = id.components(separatedBy: ";")
        guard parts.count >= 4 else { return nil }
        return parts[3]
    }

    public var osType: SystemImageType {
        guard let v = variant?.lowercased() else { return .other }
        if v == "android-wear" || v == "android-wear-cn" { return .wearOS }
        if v == "android-tv" { return .androidTV }
        if v == "google_apis_atd" || v == "android-automotive" { return .automotive }
        return .phone
    }

    public var displayName: String {
        var parts: [String] = []
        if let level = apiLevel { parts.append("API \(level)") }
        if let v = variant { parts.append(formatVariant(v)) }
        if let arch = architecture { parts.append(arch) }
        return parts.isEmpty ? description : parts.joined(separator: " — ")
    }

    private func formatVariant(_ v: String) -> String {
        switch v.lowercased() {
        case "google_apis":              return "Google APIs"
        case "google_apis_playstore":    return "Google Play"
        case "android-wear":             return "Wear OS"
        case "android-wear-cn":          return "Wear OS (China)"
        case "android-tv":               return "Android TV"
        case "google_apis_atd":          return "Automotive"
        case "android-automotive":       return "Automotive"
        case "google_apis_ps_uef":       return "Google Play (UEF)"
        case "google_atd":               return "Google ATD"
        case "aosp_atd":                 return "AOSP ATD"
        case "default":                  return "AOSP"
        default:
            if v.hasPrefix("aosp_") { return v.replacingOccurrences(of: "aosp_", with: "AOSP ").capitalized }
            return v
        }
    }
}

public struct AVD: Identifiable, Codable {
    public var id: String { name }
    public let name: String
    public let device: String?
    public let path: String?
    public let target: String?
    public var isRunning: Bool = false
    public var isStarting: Bool = false
    public var isStopping: Bool = false
    public var serial: String?

    public init(
        name: String, device: String?, path: String?, target: String?, isRunning: Bool = false,
        serial: String? = nil
    ) {
        self.name = name
        self.device = device
        self.path = path
        self.target = target
        self.isRunning = isRunning
        self.serial = serial
    }
}

public struct HardwareProfile: Identifiable, Codable {
    public let id: String
    public let name: String
    public let oem: String?
    public let width: Int?
    public let height: Int?
    public let density: Int?

    public init(id: String, name: String, oem: String?, width: Int?, height: Int?, density: Int?) {
        self.id = id
        self.name = name
        self.oem = oem
        self.width = width
        self.height = height
        self.density = density
    }
}

public struct AVDOptions: Codable {
    public var ramMB: Int?
    public var heapMB: Int?
    public var storageMB: Int?
    public var width: Int?
    public var height: Int?
    public var density: Int?
    public var sdCardMB: Int?
    public var cameraBack: String?
    public var gps: Bool?
    public var keyboard: Bool?
    public var gpuMode: String?
    public var coldBoot: Bool?
    public var showDeviceFrame: Bool?

    public init(
        ramMB: Int? = 2048, heapMB: Int? = 512, storageMB: Int? = 4096, width: Int? = 1080,
        height: Int? = 2400, density: Int? = 420, sdCardMB: Int? = 512,
        cameraBack: String? = "emulated", gps: Bool? = true, keyboard: Bool? = true,
        gpuMode: String? = "auto", coldBoot: Bool? = false, showDeviceFrame: Bool? = true
    ) {
        self.ramMB = ramMB
        self.heapMB = heapMB
        self.storageMB = storageMB
        self.width = width
        self.height = height
        self.density = density
        self.sdCardMB = sdCardMB
        self.cameraBack = cameraBack
        self.gps = gps
        self.keyboard = keyboard
        self.gpuMode = gpuMode
        self.coldBoot = coldBoot
        self.showDeviceFrame = showDeviceFrame
    }

    public static var `default`: AVDOptions {
        AVDOptions()
    }
}
