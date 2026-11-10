//
//  RingService.swift
//  AndroLaunch
//
//  Make a connected phone ring at alarm volume for a bounded window.
//
//  "Find my phone" with no new permissions: the companion raises the alarm
//  stream, loops the alarm sound and always restores the previous volume. The
//  phone bounds the ring to 30 s itself, and its foreground notification grows a
//  "Stop ringing" action, so a Mac that disappears mid-ring cannot leave the
//  phone ringing forever.
//
//  Honest limit: Do Not Disturb can still silence the alarm on some OEM skins.
//  The command reports whether the phone accepted the ring; the Mac does not
//  claim the phone is audible.
//

import Combine
import Foundation

final class RingService: ObservableObject {

    static let shared = RingService()

    /// Devices the Mac asked to ring, with the local deadline used to clear the UI.
    @Published private(set) var ringingUntil: [String: Date] = [:]
    @Published private(set) var lastError: String?

    private let companion: CompanionClient
    private var timers: [String: Timer] = [:]

    /// The companion clamps to the same maximum; this mirrors it for the UI.
    static let maximumDurationMs = 30_000
    private static let defaultDurationMs = 20_000

    init(companion: CompanionClient = .shared) {
        self.companion = companion
    }

    func isRinging(deviceID: String) -> Bool {
        guard let until = ringingUntil[deviceID] else { return false }
        return until > Date()
    }

    /// There is at most one phone ringing normally, but the map keeps per-device
    /// state so a multi-device menu row stays truthful.
    func ring(deviceID: String, durationMs: Int = defaultDurationMs) {
        let clamped = max(1_000, min(Self.maximumDurationMs, durationMs))
        companion.ring(deviceID: deviceID, durationMs: clamped) { [weak self] success, message in
            guard let self else { return }
            DispatchQueue.main.async {
                guard success else {
                    self.lastError = Self.friendlyMessage(message)
                    return
                }
                self.lastError = nil
                let deadline = Date().addingTimeInterval(Double(clamped) / 1000 + 0.5)
                self.ringingUntil[deviceID] = deadline
                self.scheduleClear(deviceID: deviceID, at: deadline)
            }
        }
    }

    func stop(deviceID: String) {
        clearState(deviceID: deviceID)
        companion.stopRing(deviceID: deviceID)
    }

    func toggle(deviceID: String) {
        if isRinging(deviceID: deviceID) {
            stop(deviceID: deviceID)
        } else {
            ring(deviceID: deviceID)
        }
    }

    func stopAll() {
        for deviceID in ringingUntil.keys {
            companion.stopRing(deviceID: deviceID)
        }
        for timer in timers.values { timer.invalidate() }
        timers.removeAll()
        ringingUntil.removeAll()
    }

    // MARK: - Private

    private func scheduleClear(deviceID: String, at deadline: Date) {
        timers[deviceID]?.invalidate()
        let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
            self?.clearState(deviceID: deviceID)
        }
        RunLoop.main.add(timer, forMode: .common)
        timers[deviceID] = timer
    }

    private func clearState(deviceID: String) {
        timers[deviceID]?.invalidate()
        timers[deviceID] = nil
        if ringingUntil[deviceID] != nil {
            ringingUntil[deviceID] = nil
        }
    }

    private static func friendlyMessage(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "The phone did not start ringing." }
        if raw.contains("unknown_command") {
            return "Update AndroLaunch Comp on the phone to use Ring Phone."
        }
        switch raw {
        case "failed": return "The phone could not play the alarm sound."
        default: return raw
        }
    }
}
