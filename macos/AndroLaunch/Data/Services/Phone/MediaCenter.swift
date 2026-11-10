//
//  MediaCenter.swift
//  AndroLaunch
//
//  Now-playing state and transport controls for whatever is playing on the
//  phone. Owned by the phone-companion feature.
//
//  The companion holds notification-listener access, which is also the access
//  level `MediaSessionManager.getActiveSessions` needs, so no extra permission is
//  involved. Polling is 2 s — fast enough for a transport row, cheap enough for a
//  USB/Wi-Fi ADB tunnel. Artwork is fetched only when the track changes and is
//  kept in memory; nothing is written to disk.
//
//  Limits, stated plainly: apps that do not publish a media session (or that opt
//  out of notification-listener control) simply show nothing here. Transport is
//  best-effort; a refusal is reported instead of a fake "playing" state.
//

import AppKit
import Combine
import Foundation

struct NowPlaying: Equatable {
    var deviceID: String
    var title: String
    var artist: String
    var packageName: String
    var isPlaying: Bool
    var canSkip: Bool
    var canPrevious: Bool = false
    var album: String = ""

    /// Reversed so "Title — Artist" reads correctly in a menu row.
    var detailText: String {
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedArtist.isEmpty ? title : "\(title) — \(trimmedArtist)"
    }

    var trackIdentity: String { "\(packageName)|\(title)|\(artist)|\(album)" }
}

final class MediaCenter: ObservableObject {

    static let shared = MediaCenter()

    @Published private(set) var nowPlaying: NowPlaying?
    /// Album art for the current track, when the app exposes it. Memory-only.
    @Published private(set) var artwork: NSImage?
    @Published private(set) var lastError: String?

    private let companion: CompanionClient
    private let devicesProvider: () -> [AndroidDevice]
    private var timer: Timer?
    private var isRunning = false
    private var pollsInFlight: Set<String> = []
    private var artworkInFlightFor: String?
    private var artworkTrackIdentity: String?

    private static let pollInterval: TimeInterval = 2
    private static let maxPolledDevices = 3

    init(
        companion: CompanionClient = .shared,
        devicesProvider: @escaping () -> [AndroidDevice] = {
            DependencyContainer.shared.menuViewModel.devices
        }
    ) {
        self.companion = companion
        self.devicesProvider = devicesProvider
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        pollsInFlight.removeAll()
        nowPlaying = nil
        artwork = nil
    }

    // MARK: - Polling

    private func tick() {
        guard isRunning else { return }
        let devices = devicesProvider().filter { $0.isConnected }
        guard !devices.isEmpty else {
            clearNowPlaying()
            return
        }

        var polled = 0
        for device in devices {
            guard companion.isReady(device.id) else { continue }
            guard polled < Self.maxPolledDevices else { break }
            polled += 1
            poll(device)
        }
        if polled == 0 {
            clearNowPlaying()
        }
    }

    private func poll(_ device: AndroidDevice) {
        guard !pollsInFlight.contains(device.id) else { return }
        pollsInFlight.insert(device.id)

        companion.mediaState(deviceID: device.id, includeArtwork: false) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.pollsInFlight.remove(device.id)
                guard self.isRunning else { return }
                switch result {
                case .success(let state):
                    self.apply(state, for: device)
                case .failure:
                    // Silence is correct when nothing is ready; do not spam errors
                    // into the menu every 2 s.
                    if self.nowPlaying?.deviceID == device.id { self.clearNowPlaying() }
                }
            }
        }
    }

    private func apply(_ state: CompanionMediaState, for device: AndroidDevice) {
        guard state.available, !state.title.isEmpty else {
            if nowPlaying?.deviceID == device.id { clearNowPlaying() }
            return
        }
        let playing = NowPlaying(
            deviceID: device.id,
            title: state.title,
            artist: state.artist,
            packageName: state.packageName,
            isPlaying: state.isPlaying,
            canSkip: state.canNext,
            canPrevious: state.canPrevious,
            album: state.album)
        if nowPlaying != playing {
            nowPlaying = playing
        }
        lastError = nil
        if artworkTrackIdentity != state.trackIdentity {
            fetchArtwork(identity: state.trackIdentity, device: device)
        }
    }

    /// Artwork is requested once per track, not every poll.
    private func fetchArtwork(identity: String, device: AndroidDevice) {
        guard artworkInFlightFor != identity else { return }
        artworkInFlightFor = identity
        companion.mediaState(deviceID: device.id, includeArtwork: true) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.artworkInFlightFor = nil
                guard case .success(let state) = result else { return }
                self.artworkTrackIdentity = identity
                if let data = state.artworkPNG, let image = NSImage(data: data) {
                    self.artwork = image
                } else {
                    self.artwork = nil
                }
            }
        }
    }

    private func clearNowPlaying() {
        if nowPlaying != nil { nowPlaying = nil }
        if artwork != nil { artwork = nil }
        artworkTrackIdentity = nil
    }

    // MARK: - Transport

    func togglePlayPause() {
        guard let playing = nowPlaying else { return }
        transport(playing.isPlaying ? "pause" : "play", deviceID: playing.deviceID)
    }

    func next() {
        guard let playing = nowPlaying, playing.canSkip else { return }
        transport("next", deviceID: playing.deviceID)
    }

    func previous() {
        guard let playing = nowPlaying, playing.canPrevious else { return }
        transport("prev", deviceID: playing.deviceID)
    }

    private func transport(_ action: String, deviceID: String) {
        guard companion.isReady(deviceID) else {
            lastError = "Reconnect the device to control playback."
            return
        }
        companion.mediaTransport(deviceID: deviceID, action: action) { [weak self] success, message in
            guard let self else { return }
            DispatchQueue.main.async {
                if !success {
                    self.lastError = Self.friendlyMessage(message)
                }
                // Re-read state shortly after the command so the label catches up.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    guard let device = self.devicesProvider().first(where: { $0.id == deviceID })
                    else { return }
                    self.poll(device)
                }
            }
        }
    }

    private static func friendlyMessage(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "The phone did not respond to the media control." }
        switch raw {
        case "no_session": return "Nothing is playing on the phone now."
        case "permission_required":
            return "Allow notification access for AndroLaunch Comp on the phone."
        case "failed": return "The phone refused the media control."
        default: return raw
        }
    }
}
