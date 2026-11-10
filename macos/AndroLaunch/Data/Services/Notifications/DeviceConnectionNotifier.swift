//
//  DeviceConnectionNotifier.swift
//  AndroLaunch
//
//  Posts a macOS notification when a new phone becomes available, gated by both
//  the Devices switch ("Device connection notifications") and the Feature alerts
//  category. Reconnects are notifications; the first device snapshot at launch is
//  seeded silently so opening the app does not replay every connected phone.
//

import Combine
import Foundation

final class DeviceConnectionNotifier {
    static let shared = DeviceConnectionNotifier()

    private var cancellables = Set<AnyCancellable>()
    private var knownConnected: Set<String> = []
    private var seeded = false
    private var started = false
    private let startedAt = Date()

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        DependencyContainer.shared.menuViewModel.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.handle(devices)
            }
            .store(in: &cancellables)
    }

    private func handle(_ devices: [AndroidDevice]) {
        let connected = devices.filter(\.isConnected)
        let identities = Set(connected.map(\.stableID))

        guard seeded else {
            knownConnected = identities
            seeded = true
            return
        }

        // Do not replay every already-connected phone during app startup; only
        // a device that appears after the app settled is a "new connection".
        if Date().timeIntervalSince(startedAt) < 4 {
            knownConnected = identities
            return
        }

        let newIdentities = identities.subtracting(knownConnected)
        knownConnected = identities

        guard AppPreferences.shared.deviceConnectionNotifications else { return }
        for identity in newIdentities {
            guard let device = connected.first(where: { $0.stableID == identity }) else {
                continue
            }
            FeatureAlertCenter.shared.post(
                .deviceConnections,
                title: "\(device.name) connected",
                body: "\(device.name) is ready on this Mac.")
        }
    }
}
