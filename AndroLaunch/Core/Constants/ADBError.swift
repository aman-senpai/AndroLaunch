import Foundation

enum ADBError: LocalizedError {
    case adbNotFound
    case adbNotExecutable
    case deviceNotFound(String)
    case appNotFound(String)
    case commandFailed(String)
    case permissionDenied
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .adbNotFound:
            return "ADB executable not found. Please ensure Android SDK is installed and ADB is in your PATH."
        case .adbNotExecutable:
            return "ADB executable is not executable. Please check permissions."
        case .deviceNotFound(let deviceId):
            return "Device not found: \(deviceId)"
        case .appNotFound(let packageId):
            return "App not found: \(packageId)"
        case .commandFailed(let command):
            return "ADB command failed: \(command)"
        case .permissionDenied:
            return "Permission denied. Please check USB debugging permissions."
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
} 