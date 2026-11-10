//
//  MirrorOptions.swift
//  AndroLaunch
//
//  Pure mirror-control value types: the per-device option set, keyboard/frame
//  mapping, screenshot & recording file naming, navigation keycodes and the
//  scrcpy argument builder shared by every mirror session. Foundation-only so
//  the mapping rules are covered by `MirrorControlsLogicTests` without AppKit,
//  a device or scrcpy.
//

import Foundation

// MARK: - Keyboard

/// `scrcpy --keyboard=<mode>` values the panel can select.
enum MirrorKeyboardMode: String, CaseIterable, Equatable {
    /// Inject key events through the Android input stack (works on every Android).
    case sdk
    /// Create a virtual UHID keyboard device (needs a newer Android/scrcpy).
    case uhid
    /// Ignore the Mac keyboard; the phone's on-screen keyboard is the only input.
    case disabled

    /// "Use Mac Keyboard" on → SDK injection (broad compatibility); off → disabled.
    ///
    /// UHID is deliberately not the default: it needs newer Android releases and a
    /// scrcpy build with UHID support, so choosing it silently would break typing
    /// on older phones. Callers can still request `.uhid` explicitly.
    static func fromMacKeyboard(_ enabled: Bool) -> MirrorKeyboardMode {
        enabled ? .sdk : .disabled
    }

    var argument: String { "--keyboard=\(rawValue)" }

    var label: String {
        switch self {
        case .sdk: return "SDK injection"
        case .uhid: return "Virtual keyboard (UHID)"
        case .disabled: return "On-screen keyboard only"
        }
    }
}

// MARK: - Frame

/// The reference's "Without Frame / Include Frame" choice maps to the scrcpy
/// borderless window flag.
enum MirrorFrameChoice: String, CaseIterable, Identifiable, Equatable {
    case withoutFrame
    case includeFrame

    var id: String { rawValue }

    var title: String {
        switch self {
        case .withoutFrame: return "Without Frame"
        case .includeFrame: return "Include Frame"
        }
    }

    var borderless: Bool { self == .withoutFrame }

    init(borderless: Bool) {
        self = borderless ? .withoutFrame : .includeFrame
    }
}

// MARK: - Navigation

enum MirrorNavKey: String, CaseIterable, Identifiable, Equatable {
    case back
    case home
    case recents

    var id: String { rawValue }

    /// Android `input keyevent` codes.
    var keycode: Int {
        switch self {
        case .back: return 4
        case .home: return 3
        case .recents: return 187  // KEYCODE_APP_SWITCH
        }
    }

    var title: String {
        switch self {
        case .back: return "Back"
        case .home: return "Home"
        case .recents: return "Recents"
        }
    }

    var icon: String {
        switch self {
        case .back: return "chevron.left"
        case .home: return "circle"
        case .recents: return "square"
        }
    }
}

// MARK: - Options

/// Everything the floating panel can change about the mirror.
struct MirrorOptions: Equatable {
    /// Forward the phone's audio to the Mac (off → `--no-audio`).
    var audioForwarding: Bool
    /// Keep the scrcpy window above other windows (`--always-on-top`).
    var alwaysOnTop: Bool
    /// Turn the phone screen off while the mirror stays visible (`--turn-screen-off`).
    var screenOff: Bool
    /// Hide the scrcpy window frame (`--window-borderless`).
    var borderless: Bool
    /// Share the clipboard with the phone (off → `--no-clipboard-autosync`).
    var clipboard: Bool
    /// Recording is tracked here so the panel can render its state; recording is
    /// implemented with `adb shell screenrecord`, not a scrcpy restart.
    var recording: Bool
    /// Forward Mac key presses (`--keyboard=sdk`, off → `--keyboard=disabled`).
    var macKeyboard: Bool

    init(
        audioForwarding: Bool = true,
        alwaysOnTop: Bool = false,
        screenOff: Bool = false,
        borderless: Bool = false,
        clipboard: Bool = false,
        recording: Bool = false,
        macKeyboard: Bool = true
    ) {
        self.audioForwarding = audioForwarding
        self.alwaysOnTop = alwaysOnTop
        self.screenOff = screenOff
        self.borderless = borderless
        self.clipboard = clipboard
        self.recording = recording
        self.macKeyboard = macKeyboard
    }

    static let `default` = MirrorOptions()

    var keyboardMode: MirrorKeyboardMode { .fromMacKeyboard(macKeyboard) }

    var frameChoice: MirrorFrameChoice { MirrorFrameChoice(borderless: borderless) }

    /// Short truthful summary for the panel footer.
    var summary: String {
        var parts: [String] = []
        parts.append(audioForwarding ? "Audio on" : "Audio off")
        parts.append(clipboard ? "Clipboard on" : "Clipboard off")
        parts.append(macKeyboard ? "Mac keyboard" : "Phone keyboard")
        parts.append(alwaysOnTop ? "Pinned" : "Unpinned")
        return parts.joined(separator: " · ")
    }

    /// True when at least one option that changes scrcpy's arguments differs from
    /// what a previous snapshot recorded.
    func differsFrom(_ other: MirrorOptions) -> Bool {
        audioForwarding != other.audioForwarding
            || alwaysOnTop != other.alwaysOnTop
            || screenOff != other.screenOff
            || borderless != other.borderless
            || clipboard != other.clipboard
            || macKeyboard != other.macKeyboard
    }
}

// MARK: - Quality

/// The user's existing quality preset (DeviceRepository) carried into a restart
/// so the panel never resets resolution, FPS or bitrate.
struct MirrorQuality: Equatable {
    var maxSize: Int?
    var maxFPS: Int?
    var bitRate: Int?
    var orientation: String?
    var flexDisplay: Bool

    init(
        maxSize: Int? = nil,
        maxFPS: Int? = nil,
        bitRate: Int? = nil,
        orientation: String? = nil,
        flexDisplay: Bool = false
    ) {
        self.maxSize = maxSize
        self.maxFPS = maxFPS
        self.bitRate = bitRate
        self.orientation = orientation
        self.flexDisplay = flexDisplay
    }

    static let `default` = MirrorQuality()
}

// MARK: - scrcpy arguments

enum MirrorScrcpyArguments {
    /// Builds the complete scrcpy argument list for a mirror session. One builder
    /// serves the normal mirror, the panel's restarts and tests, so flags cannot
    /// drift between call sites.
    static func build(
        deviceID: String,
        deviceName: String?,
        quality: MirrorQuality,
        options: MirrorOptions,
        recordPath: String?
    ) -> [String] {
        let title = (deviceName?.isEmpty == false ? deviceName! : deviceID)
        var args: [String] = ["--serial", deviceID, "--window-title", title]

        if quality.flexDisplay {
            // Flex display lets scrcpy pick the size; an explicit -m would pin it.
        } else if let maxSize = quality.maxSize, maxSize > 0 {
            args.append(contentsOf: ["-m", "\(maxSize)"])
        }
        if let maxFPS = quality.maxFPS, maxFPS > 0 {
            args.append(contentsOf: ["--max-fps", "\(maxFPS)"])
        }
        if let bitRate = quality.bitRate, bitRate > 0 {
            args.append(contentsOf: ["--video-bit-rate", "\(bitRate)M"])
        }
        if let orientation = quality.orientation, !orientation.isEmpty, orientation != "Auto" {
            args.append(contentsOf: ["--capture-orientation", orientation])
        }

        if options.borderless { args.append("--window-borderless") }
        if options.alwaysOnTop { args.append("--always-on-top") }
        if options.screenOff { args.append("--turn-screen-off") }
        if !options.audioForwarding { args.append("--no-audio") }
        if !options.clipboard { args.append("--no-clipboard-autosync") }
        args.append(options.keyboardMode.argument)
        if let recordPath = recordPath?.trimmingCharacters(in: .whitespacesAndNewlines),
            !recordPath.isEmpty
        {
            args.append(contentsOf: ["--record", recordPath])
        }
        return args
    }
}

// MARK: - Capture naming

enum MirrorCaptureNaming {
    /// Trims a user-facing prefix down to a safe file-name component. Every
    /// non-alphanumeric scalar becomes a single separator, so path separators and
    /// control characters can never reach the file system.
    static func sanitizedPrefix(_ raw: String) -> String {
        let mapped = raw.unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "-"
        }.joined()
        let collapsed = mapped.split(separator: "-").map(String.init).joined(separator: "-")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-_. "))
        return trimmed.isEmpty ? "AndroLaunch" : String(trimmed.prefix(40))
    }

    /// `yyyy-MM-dd-HHmmss`, POSIX locale, caller-selected time zone (tests pass UTC).
    static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }

    /// Safe, unique capture file name such as `AndroLaunch-2026-11-06-211502.png`.
    /// An existing file gets `-2`, `-3`, … before the extension.
    static func fileName(
        prefix: String = "AndroLaunch",
        date: Date,
        fileExtension: String,
        existingNames: [String] = [],
        timeZone: TimeZone = .current
    ) -> String {
        let base = sanitizedPrefix(prefix)
        let stamp = timestamp(date, timeZone: timeZone)
        let ext = sanitizedExtension(fileExtension)
        let stem = "\(base)-\(stamp)"
        let taken = Set(existingNames.map { $0.lowercased() })
        guard taken.contains("\(stem).\(ext)".lowercased()) else { return "\(stem).\(ext)" }
        var index = 2
        while index < 1000 {
            let candidate = "\(stem)-\(index).\(ext)"
            if !taken.contains(candidate.lowercased()) { return candidate }
            index += 1
        }
        return "\(stem)-\(UUID().uuidString.prefix(4)).\(ext)"
    }

    static func sanitizedExtension(_ raw: String) -> String {
        let mapped = raw.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        let value = String(String.UnicodeScalarView(mapped))
        return value.isEmpty ? "dat" : value
    }

    /// `~/Desktop/…` for compact UI copy.
    static func displayPath(_ url: URL) -> String {
        let home = NSHomeDirectory()
        let path = url.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

// MARK: - Session

/// What was actually launched for a device, so the panel can describe reality
/// rather than the options it wishes were applied.
struct MirrorSessionSnapshot: Equatable {
    let deviceID: String
    let deviceName: String?
    let options: MirrorOptions
    let quality: MirrorQuality
    let recordPath: String?
    let startedAt: Date
}

enum MirrorSessionEvent: Equatable {
    case started(MirrorSessionSnapshot)
    case stopped(deviceID: String)
    case failed(deviceID: String, message: String)
}

// MARK: - Preview state

/// Deterministic state for the SwiftUI preview and the HeadSnapshotRenderer.
/// Live values never come from here.
struct MirrorControlsPreview: Equatable {
    var deviceName: String
    var isConnected: Bool
    var options: MirrorOptions
    var isMirroring: Bool
    var recordingElapsedSeconds: Int?
    var statusMessage: String?
    var lastCapturePath: String?

    init(
        deviceName: String = "Pixel 9 Pro",
        isConnected: Bool = true,
        options: MirrorOptions = MirrorOptions(
            audioForwarding: true,
            alwaysOnTop: true,
            screenOff: false,
            borderless: false,
            clipboard: true,
            recording: false,
            macKeyboard: true),
        isMirroring: Bool = true,
        recordingElapsedSeconds: Int? = 42,
        statusMessage: String? = "Mirror running with the selected options.",
        lastCapturePath: String? = "~/Desktop/AndroLaunch-2026-11-06-211502.png"
    ) {
        self.deviceName = deviceName
        self.isConnected = isConnected
        self.options = options
        self.isMirroring = isMirroring
        self.recordingElapsedSeconds = recordingElapsedSeconds
        self.statusMessage = statusMessage
        self.lastCapturePath = lastCapturePath
    }

    static let state = MirrorControlsPreview()
}
