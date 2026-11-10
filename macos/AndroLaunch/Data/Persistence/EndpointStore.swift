//
//  EndpointStore.swift
//  AndroLaunch
//
//  Remembers every transport that ever reached a device so the connection layer
//  can race them instead of guessing one address. Keyed by device identity.
//

import Foundation

final class EndpointStore {
    static let shared = EndpointStore()

    private let defaults: UserDefaults
    private let storageKey = "device_endpoints_v1"
    private let writeQueue = DispatchQueue(label: "com.senpai.AndroLaunch.endpoints")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Reading

    func endpoints(for identity: String) -> [DeviceEndpoint] {
        (all()[identity] ?? []).sorted(by: Self.ordering)
    }

    /// Endpoints worth racing, best first. Very old repeated failures are dropped.
    func candidates(for identity: String) -> [DeviceEndpoint] {
        endpoints(for: identity).filter { !$0.isStale }
    }

    func endpoint(address: String, for identity: String) -> DeviceEndpoint? {
        endpoints(for: identity).first { $0.address == address }
    }

    // MARK: - Writing

    func upsert(_ endpoint: DeviceEndpoint, for identity: String) {
        guard !identity.isEmpty, !endpoint.address.isEmpty else { return }
        mutate { all in
            var list = all[identity] ?? []
            if let index = list.firstIndex(where: { $0.address == endpoint.address }) {
                var merged = endpoint
                merged.successfulConnections = max(
                    endpoint.successfulConnections, list[index].successfulConnections)
                merged.lastConnected = endpoint.lastConnected ?? list[index].lastConnected
                list[index] = merged
            } else {
                list.append(endpoint)
            }
            all[identity] = list
        }
    }

    func recordSuccess(address: String, for identity: String) {
        mutate { all in
            var list = all[identity] ?? []
            if let index = list.firstIndex(where: { $0.address == address }) {
                list[index].successfulConnections += 1
                list[index].failedAttempts = 0
                list[index].lastConnected = Date()
                list[index].lastSeen = Date()
            } else {
                list.append(
                    DeviceEndpoint(
                        address: address, lastConnected: Date(), successfulConnections: 1))
            }
            all[identity] = list
        }
    }

    func recordFailure(address: String, for identity: String) {
        mutate { all in
            guard var list = all[identity],
                let index = list.firstIndex(where: { $0.address == address })
            else { return }
            list[index].failedAttempts += 1
            list[index].lastSeen = Date()
            all[identity] = list
        }
    }

    func remove(address: String, for identity: String) {
        mutate { all in
            guard var list = all[identity] else { return }
            list.removeAll { $0.address == address }
            all[identity] = list.isEmpty ? nil : list
        }
    }

    func removeAll(for identity: String) {
        mutate { all in all[identity] = nil }
    }

    /// Import the last known host of a legacy `PreviousDevice` record.
    func migrate(legacyHost: String, for identity: String) {
        guard !legacyHost.isEmpty, !identity.isEmpty else { return }
        guard endpoint(address: legacyHost, for: identity) == nil else { return }
        upsert(DeviceEndpoint(address: legacyHost, isUserAdded: false), for: identity)
    }

    // MARK: - Ordering

    private static func ordering(_ lhs: DeviceEndpoint, _ rhs: DeviceEndpoint) -> Bool {
        if lhs.kind.raceRank != rhs.kind.raceRank {
            return lhs.kind.raceRank < rhs.kind.raceRank
        }
        if lhs.isTrusted != rhs.isTrusted { return lhs.isTrusted }
        let lhsDate = lhs.lastConnected ?? lhs.lastSeen
        let rhsDate = rhs.lastConnected ?? rhs.lastSeen
        return lhsDate > rhsDate
    }

    // MARK: - Storage

    private func all() -> [String: [DeviceEndpoint]] {
        guard let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([String: [DeviceEndpoint]].self, from: data)
        else { return [:] }
        return decoded
    }

    private func mutate(_ body: (inout [String: [DeviceEndpoint]]) -> Void) {
        writeQueue.sync {
            var current = all()
            body(&current)
            guard let data = try? JSONEncoder().encode(current) else { return }
            defaults.set(data, forKey: storageKey)
        }
    }
}
