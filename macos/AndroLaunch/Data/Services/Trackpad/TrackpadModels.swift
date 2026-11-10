//
//  TrackpadModels.swift
//  AndroLaunch
//
//  Pure gesture math and persisted preferences for the floating trackpad panel.
//  Foundation-only so the mapping is unit-tested and the panel view can render
//  without ADB or AppKit services.
//

import Foundation

// MARK: - Gestures

enum TrackpadGesture: String, CaseIterable, Identifiable {
    case back
    case home
    case recents
    case notifications
    case scrollUp
    case scrollDown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .back: return "Back"
        case .home: return "Home"
        case .recents: return "Recents"
        case .notifications: return "Notifications"
        case .scrollUp: return "Scroll up"
        case .scrollDown: return "Scroll down"
        }
    }

    var icon: String {
        switch self {
        case .back: return "chevron.backward"
        case .home: return "house.fill"
        case .recents: return "square.on.square"
        case .notifications: return "bell.fill"
        case .scrollUp: return "arrow.up"
        case .scrollDown: return "arrow.down"
        }
    }

    /// Short, human confirmation shown in the panel after the gesture is sent.
    var confirmation: String {
        switch self {
        case .back: return "Back sent"
        case .home: return "Home sent"
        case .recents: return "Recents sent"
        case .notifications: return "Shade opened"
        case .scrollUp: return "Scrolled up"
        case .scrollDown: return "Scrolled down"
        }
    }

    /// The four one-tap fallbacks shown under the gesture surface.
    static var buttonGestures: [TrackpadGesture] { [.back, .home, .recents, .notifications] }
}

// MARK: - Commands

/// A single Android input action. Arguments are already split for `adb shell`.
enum TrackpadCommand: Equatable {
    case keyEvent(Int)
    case shell(String)

    var arguments: [String] {
        switch self {
        case .keyEvent(let code):
            return ["input", "keyevent", "\(code)"]
        case .shell(let command):
            return shellWords(command)
        }
    }

    /// Minimal whitespace splitter. Commands here never contain user text.
    private func shellWords(_ command: String) -> [String] {
        command.split(separator: " ").map(String.init)
    }
}

enum TrackpadGestureMapping {
    /// Android key codes: BACK=4, HOME=3, APP_SWITCH=187.
    static func commands(
        for gesture: TrackpadGesture,
        screen: TrackpadScreenSize = .fallback
    ) -> [TrackpadCommand] {
        switch gesture {
        case .back:
            return [.keyEvent(4)]
        case .home:
            return [.keyEvent(3)]
        case .recents:
            return [.keyEvent(187)]
        case .notifications:
            return [.shell("cmd statusbar expand-notifications")]
        case .scrollUp:
            return [
                .shell(
                    swipeCommand(
                        direction: .contentUp, distance: 420, screen: screen))
            ]
        case .scrollDown:
            return [
                .shell(
                    swipeCommand(
                        direction: .contentDown, distance: 420, screen: screen))
            ]
        }
    }

    private static func swipeCommand(
        direction: TrackpadScrollDirection,
        distance: Int,
        screen: TrackpadScreenSize
    ) -> String {
        let arguments = TrackpadScrollAccumulator.swipeArguments(
            direction: direction, distance: distance, screen: screen)
        return arguments.joined(separator: " ")
    }
}

// MARK: - Screen geometry

struct TrackpadScreenSize: Equatable {
    var width: Int
    var height: Int

    /// Used until `wm size` answers; typical for a modern phone.
    static let fallback = TrackpadScreenSize(width: 1080, height: 2400)

    var label: String { "\(width) × \(height)" }

    /// Parses `wm size`: prefers an override size, then the physical size.
    static func parse(wmSize output: String) -> TrackpadScreenSize? {
        var override: TrackpadScreenSize?
        var physical: TrackpadScreenSize?
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                let range = line.range(of: #"\d{2,5}x\d{2,5}"#, options: .regularExpression)
            else { continue }
            let parts = line[range].split(separator: "x")
            guard parts.count == 2,
                let width = Int(parts[0]),
                let height = Int(parts[1]),
                width > 0, height > 0
            else { continue }
            let value = TrackpadScreenSize(width: width, height: height)
            if line.lowercased().hasPrefix("override") {
                override = value
            } else if line.lowercased().hasPrefix("physical") {
                physical = value
            } else if physical == nil {
                physical = value
            }
        }
        return override ?? physical
    }
}

// MARK: - Scrolling

enum TrackpadScrollDirection: String, Equatable {
    /// Content moves up the screen: the finger travels up on the phone.
    case contentUp
    /// Content moves down the screen: the finger travels down on the phone.
    case contentDown
}

struct TrackpadScrollSwipe: Equatable {
    let direction: TrackpadScrollDirection
    let distance: Int
}

/// Turns a stream of two-finger scroll deltas into occasional, throttled
/// `input swipe` gestures. One swipe per accumulated threshold keeps ADB traffic
/// low while still feeling continuous.
struct TrackpadScrollAccumulator {
    private(set) var residual: Double = 0

    static func clampSensitivity(_ value: Double) -> Double {
        guard value.isFinite else { return 0.6 }
        return min(1, max(0.1, value))
    }

    /// Finger travel needed to emit one swipe. Higher sensitivity = less travel.
    static func stepDistance(sensitivity: Double) -> Double {
        let normalized = clampSensitivity(sensitivity)
        return 56 - 38 * normalized
    }

    mutating func add(
        deltaY: Double,
        naturalScrolling: Bool,
        sensitivity: Double
    ) -> TrackpadScrollSwipe? {
        guard deltaY.isFinite else { return nil }
        // Positive scroll delta means content moves up; "natural" keeps the finger
        // and content moving together, non-natural inverts it.
        let effective = naturalScrolling ? deltaY : -deltaY
        guard abs(effective) > 0.01 else { return nil }
        residual += effective

        let threshold = Self.stepDistance(sensitivity: sensitivity)
        guard abs(residual) >= threshold else { return nil }

        let direction: TrackpadScrollDirection = residual > 0 ? .contentUp : .contentDown
        let scale = 1.1 + 0.9 * Self.clampSensitivity(sensitivity)
        let distance = Int(min(900, max(80, abs(residual) * scale)))
        residual = 0
        return TrackpadScrollSwipe(direction: direction, distance: distance)
    }

    mutating func reset() {
        residual = 0
    }

    static func swipeArguments(
        direction: TrackpadScrollDirection,
        distance: Int,
        screen: TrackpadScreenSize
    ) -> [String] {
        let x = max(1, screen.width / 2)
        let centerY = screen.height / 2
        let half = max(40, min(max(1, screen.height / 3), max(80, distance))) / 2
        let startY = direction == .contentUp ? centerY + half : centerY - half
        let endY = direction == .contentUp ? centerY - half : centerY + half
        return ["input", "swipe", "\(x)", "\(startY)", "\(x)", "\(endY)", "110"]
    }
}

// MARK: - Gesture classification

struct TrackpadPoint: Equatable {
    var x: Double
    var y: Double
}

struct TrackpadSize: Equatable {
    var width: Double
    var height: Double
}

/// Turns one drag on the panel's gesture surface into an Android gesture.
///
/// Back is an edge swipe (left edge → right). Recents is an upward swipe anywhere.
/// Notifications is a downward swipe that starts near the top. Everything else is
/// ignored so an accidental drag never changes Android state.
struct TrackpadGestureClassifier {
    var edgeFraction: Double = 0.24
    var minimumFraction: Double = 0.16
    var minimumTravel: Double = 26

    func classify(
        start: TrackpadPoint,
        end: TrackpadPoint,
        size: TrackpadSize,
        sensitivity: Double = 0.6
    ) -> TrackpadGesture? {
        guard size.width > 0, size.height > 0 else { return nil }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let scale = 1.35 - 0.55 * TrackpadScrollAccumulator.clampSensitivity(sensitivity)
        let thresholdX = max(minimumTravel * scale, size.width * minimumFraction * scale)
        let thresholdY = max(minimumTravel * scale, size.height * minimumFraction * scale)

        if abs(dx) >= thresholdX && abs(dx) > abs(dy) {
            // Only a left-edge swipe is a navigation gesture; a forward swipe is
            // intentionally unsupported because Android apps rarely map it.
            if dx > 0 && start.x <= size.width * edgeFraction { return .back }
            return nil
        }

        if abs(dy) >= thresholdY && abs(dy) > abs(dx) {
            if dy < 0 { return .recents }
            if start.y <= size.height * 0.32 { return .notifications }
        }
        return nil
    }
}

// MARK: - Preferences

struct TrackpadPreferences: Equatable {
    var sensitivity: Double = TrackpadPreferences.defaultSensitivity
    var naturalScrolling: Bool = true

    static let defaultSensitivity = 0.6

    enum Keys {
        static let sensitivity = "platform.trackpad.sensitivity"
        static let naturalScrolling = "platform.trackpad.naturalScrolling"
    }

    static func load(from defaults: UserDefaults = .standard) -> TrackpadPreferences {
        var prefs = TrackpadPreferences()
        if let stored = defaults.object(forKey: Keys.sensitivity) as? Double {
            prefs.sensitivity = TrackpadScrollAccumulator.clampSensitivity(stored)
        }
        if let stored = defaults.object(forKey: Keys.naturalScrolling) as? Bool {
            prefs.naturalScrolling = stored
        }
        return prefs
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(
            TrackpadScrollAccumulator.clampSensitivity(sensitivity), forKey: Keys.sensitivity)
        defaults.set(naturalScrolling, forKey: Keys.naturalScrolling)
    }
}

// MARK: - Panel state

struct TrackpadPanelState: Equatable {
    var deviceID: String?
    var deviceName: String?
    var isDeviceConnected: Bool = false
    var sensitivity: Double = TrackpadPreferences.defaultSensitivity
    var naturalScrolling: Bool = true
    var lastAction: String?
    var isSending: Bool = false
    var screen: TrackpadScreenSize = .fallback

    var isAvailable: Bool { deviceID != nil && isDeviceConnected }

    var deviceLine: String {
        guard let deviceName, isAvailable else { return "No device connected" }
        return deviceName
    }

    var surfaceHint: String {
        isAvailable ? "Swipe to navigate · Scroll to scroll" : "Connect a device to send gestures"
    }

    var screenLabel: String? {
        isAvailable ? screen.label : nil
    }
}

struct TrackpadPanelActions {
    var gesture: (TrackpadGesture) -> Void = { _ in }
    var scroll: (Double) -> Void = { _ in }
    var setSensitivity: (Double) -> Void = { _ in }
    var setNaturalScrolling: (Bool) -> Void = { _ in }
    var close: () -> Void = {}
    var openHub: () -> Void = {}
}
