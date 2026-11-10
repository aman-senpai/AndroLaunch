//
//  CameraModels.swift
//  AndroLaunch
//
//  Value types for the phone-camera surface (Data/Services/Camera).
//
//  Deliberately Foundation-only: the camera card is a pure function of this state,
//  so it can be rendered and tested without launching scrcpy, ADB or AppKit
//  services. `CameraController` owns the real work; this file owns the copy,
//  bounds and honest status rules.
//

import Foundation

// MARK: - Lens

enum CameraLens: String, CaseIterable, Identifiable {
    case back
    case front

    var id: String { rawValue }

    var title: String {
        switch self {
        case .back: return "Back camera"
        case .front: return "Front camera"
        }
    }

    var shortTitle: String {
        switch self {
        case .back: return "Back"
        case .front: return "Front"
        }
    }

    var icon: String {
        switch self {
        case .back: return "camera.fill"
        case .front: return "person.crop.square.fill"
        }
    }

    /// Value scrcpy expects for `--camera-facing`.
    var scrcpyValue: String { rawValue }

    /// The torch lives on the rear camera on every phone this app supports.
    var supportsTorch: Bool { self == .back }
}

// MARK: - Aspect ratio

enum CameraAspect: String, CaseIterable, Identifiable {
    case sensor
    case wide
    case standard
    case square

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sensor: return "Native"
        case .wide: return "16:9"
        case .standard: return "4:3"
        case .square: return "1:1"
        }
    }

    /// Value scrcpy expects for `--camera-ar`.
    var scrcpyValue: String {
        switch self {
        case .sensor: return "sensor"
        case .wide: return "16:9"
        case .standard: return "4:3"
        case .square: return "1:1"
        }
    }
}

// MARK: - Zoom

enum CameraZoom {
    static let minimum: Double = 1
    static let maximum: Double = 5

    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return minimum }
        return min(maximum, max(minimum, value))
    }

    static func label(_ value: Double) -> String {
        String(format: "%.1f×", clamp(value))
    }

    /// scrcpy only needs `--camera-zoom` when the user actually zoomed.
    static func scrcpyValue(_ value: Double) -> Double? {
        let clamped = clamp(value)
        guard clamped > minimum + 0.01 else { return nil }
        return (clamped * 10).rounded() / 10
    }

    static func adjust(_ value: Double, up: Bool) -> Double {
        clamp(clamp(value) + (up ? 0.5 : -0.5))
    }
}

// MARK: - System camera extension

/// Honest state of the macOS CoreMediaIO camera extension.
///
/// AndroLaunch ships a phone-camera *preview* (scrcpy) in this build. Using the
/// phone as a system webcam for Zoom/QuickTime requires a separate, signed and
/// notarised CMIO system extension that cannot be produced unsigned, so the app
/// must never claim the extension is available unless one is genuinely present.
enum CameraExtensionStatus: Equatable {
    case querying
    case installable(String)
    case installed(String)
    case unavailable(String)

    var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }

    var isQuerying: Bool { self == .querying }

    var canInstall: Bool {
        if case .installable = self { return true }
        return false
    }

    var summary: String {
        switch self {
        case .querying:
            return "Checking…"
        case .installable(let label):
            return "Ready to install · \(label)"
        case .installed(let label):
            return "Installed · \(label)"
        case .unavailable(let reason):
            return reason
        }
    }

    var badgeText: String {
        switch self {
        case .querying: return "Checking"
        case .installable: return "Install"
        case .installed: return "Installed"
        case .unavailable: return "Not available"
        }
    }

    /// Plain-language explanation, shown wherever the extension is surfaced.
    var detail: String {
        switch self {
        case .querying:
            return "Checking for the AndroLaunch camera extension on this Mac."
        case .installable:
            return "The local-signed camera extension is bundled. Install it, then approve it in System Settings › Login Items & Extensions."
        case .installed:
            return "AndroLaunch Camera is active. Apps such as Zoom and QuickTime can select it as a camera."
        case .unavailable:
            return "No camera extension is bundled in this build. Use scripts/install-local-camera-extension.sh for a local-signed test build."
        }
    }
}

// MARK: - Extension probes

enum CameraExtensionProbe {
    /// Finds an AndroLaunch camera extension in `systemextensionsctl list` output.
    ///
    /// The tool prints one row per extension; only a row that names both this app
    /// and a camera/CMIO role counts. Anything else is unknown, never "installed".
    static func extensionLabel(fromSystemExtensionList output: String) -> String? {
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let lowered = line.lowercased()
            guard lowered.contains("androlaunch") else { continue }
            guard
                lowered.contains("camera") || lowered.contains("cmio")
                    || lowered.contains("coremedia")
            else { continue }
            // Prefer the bundle identifier (the third tab-separated column when
            // present), otherwise fall back to the row itself.
            let columns = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
                .map(String.init)
            if let bundle = columns.first(where: {
                $0.lowercased().contains("androlaunch") && $0.contains(".")
            }) {
                return bundle
            }
            return "AndroLaunch Camera"
        }
        return nil
    }

    /// A `.systemextension` bundled inside the app (none in this build). This is
    /// what a future signed build would ship; callers must still verify signing
    /// before claiming it is active.
    static func bundledCameraExtensionName(in directories: [URL?]) -> String? {
        let fileManager = FileManager.default
        for directory in directories.compactMap({ $0 }) {
            guard
                let entries = try? fileManager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: nil)
            else { continue }
            for entry in entries where entry.pathExtension == "systemextension" {
                let name = entry.deletingPathExtension().lastPathComponent
                let lowered = name.lowercased()
                if lowered.contains("camera") || lowered.contains("cmio") {
                    return name
                }
            }
        }
        return nil
    }
}

// MARK: - Preview state

/// Everything the camera card needs to draw itself. The controller fills this in;
/// the view never reaches into ADB, scrcpy or HubStore.
struct CameraPreviewState: Equatable {
    var deviceID: String?
    var deviceName: String?
    var isDeviceConnected: Bool = false
    var isScrcpyAvailable: Bool = false
    var lens: CameraLens = .back
    var aspect: CameraAspect = .wide
    var torchEnabled: Bool = false
    var zoom: Double = CameraZoom.minimum
    var isPreviewing: Bool = false
    var isStarting: Bool = false
    var needsRestart: Bool = false
    var extensionStatus: CameraExtensionStatus = .querying
    var message: String?

    var canPreview: Bool { isDeviceConnected && isScrcpyAvailable && deviceID != nil }

    var primaryActionTitle: String {
        if isPreviewing { return "Stop preview" }
        if isStarting { return "Starting…" }
        return "Start preview"
    }

    var primaryActionIcon: String {
        isPreviewing ? "stop.fill" : "play.fill"
    }

    /// One-line status for the card header.
    var statusSummary: String {
        if let message { return message }
        if isPreviewing {
            return "Previewing \(lens.shortTitle.lowercased()) camera"
        }
        if isStarting { return "Starting preview…" }
        if !isDeviceConnected {
            return deviceID == nil ? "No device connected" : "Device disconnected"
        }
        if !isScrcpyAvailable {
            return "scrcpy is required for camera preview"
        }
        return "Ready to preview"
    }

    var statusTintName: String {
        if isPreviewing { return "success" }
        if !canPreview || message != nil { return "warning" }
        return "secondary"
    }

    var zoomLabel: String { CameraZoom.label(zoom) }

    var torchAvailable: Bool { lens.supportsTorch }

    /// Torch is only meaningful for the back lens; the UI must say why it is off.
    var torchSubtitle: String? {
        lens.supportsTorch ? "Keeps the rear LED on while previewing." : "Torch needs the back camera."
    }

    var extensionBadge: String { extensionStatus.badgeText }

    var extensionBadgeIsWarning: Bool {
        if case .unavailable = extensionStatus { return true }
        return false
    }

    var extensionRowSubtitle: String {
        switch extensionStatus {
        case .querying:
            return "Checking whether the camera extension is present."
        case .installable:
            return "Local-signed extension bundled — install it, then approve it in System Settings."
        case .installed:
            return "AndroLaunch Camera can be selected by Zoom, FaceTime and QuickTime."
        case .unavailable:
            return "Use the local-signing installer to bundle and activate the camera extension."
        }
    }

    var note: String {
        "Preview runs in a separate scrcpy window. Starting or stopping it uses this device's active scrcpy session."
    }

    /// Shown when the preview is running with settings that only apply on launch.
    var restartHint: String? {
        needsRestart ? "Restart the preview to apply the new torch, zoom or aspect." : nil
    }
}

// MARK: - Actions

/// Closures the camera card calls. Grouped so the view stays a pure value renderer
/// and the controller stays the only object with side effects.
struct CameraSettingsActions {
    var startPreview: () -> Void = {}
    var stopPreview: () -> Void = {}
    var restartPreview: () -> Void = {}
    var setLens: (CameraLens) -> Void = { _ in }
    var setAspect: (CameraAspect) -> Void = { _ in }
    var setTorch: (Bool) -> Void = { _ in }
    var setZoom: (Double) -> Void = { _ in }
    var refreshExtensionStatus: () -> Void = {}
    var openExtensionSettings: () -> Void = {}
    var installExtension: () -> Void = {}
    var clearMessage: () -> Void = {}
}
