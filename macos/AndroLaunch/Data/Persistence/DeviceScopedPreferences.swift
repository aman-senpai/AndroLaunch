//
//  DeviceScopedPreferences.swift
//  AndroLaunch
//
//  Preferences that belong to a *physical device*, not to one ADB transport.
//  Values are stored under the device's hardware serial, so unplugging the cable
//  and reconnecting over Wi-Fi keeps mirror quality, clipboard opt-in and camera
//  settings intact.
//

import Foundation

/// UserDefaults-backed store keyed by device identity.
///
/// The legacy layout kept one dictionary per preference, keyed by the ADB
/// transport ID (`"mirror_max_size": ["192.168.1.5:5555": 1024]`). Those entries
/// are migrated lazily through `migrateLegacyDictionaries()` once the identity of
/// a connected device is known.
final class DeviceScopedPreferences {
    static let shared = DeviceScopedPreferences()

    private let defaults: UserDefaults
    private let namespace = "device_pref."
    private let transportMapKey = "device_transport_map_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Transport → identity mapping

    /// Records that `transportID` currently resolves to `identity` (hardware serial).
    func register(transportID: String, identity: String) {
        guard !transportID.isEmpty, !identity.isEmpty, transportID != identity else { return }
        var map = transportMap()
        guard map[transportID] != identity else { return }
        map[transportID] = identity
        defaults.set(map, forKey: transportMapKey)
    }

    /// Identity for a transport ID: the hardware serial when known, else the ID itself.
    func identity(forTransportID id: String) -> String {
        transportMap()[id] ?? id
    }

    private func transportMap() -> [String: String] {
        defaults.dictionary(forKey: transportMapKey) as? [String: String] ?? [:]
    }

    // MARK: - Scalar access

    func bool(_ name: String, for identity: String, default fallback: Bool) -> Bool {
        guard let stored = rawValue(name, identity: identity) as? NSNumber else { return fallback }
        return stored.boolValue
    }

    func setBool(_ value: Bool, _ name: String, for identity: String) {
        write(NSNumber(value: value), name: name, identity: identity)
    }

    func integer(_ name: String, for identity: String, default fallback: Int) -> Int {
        guard let stored = rawValue(name, identity: identity) as? NSNumber else { return fallback }
        return stored.intValue
    }

    func setInteger(_ value: Int, _ name: String, for identity: String) {
        write(NSNumber(value: value), name: name, identity: identity)
    }

    func string(_ name: String, for identity: String, default fallback: String) -> String {
        rawValue(name, identity: identity) as? String ?? fallback
    }

    func setString(_ value: String, _ name: String, for identity: String) {
        write(value, name: name, identity: identity)
    }

    func removeValue(_ name: String, for identity: String) {
        guard var dict = defaults.dictionary(forKey: storageKey(name)) else { return }
        dict.removeValue(forKey: identity)
        defaults.set(dict, forKey: storageKey(name))
    }

    func removeAll(for identity: String) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(namespace) {
            guard var dict = defaults.dictionary(forKey: key) else { continue }
            dict.removeValue(forKey: identity)
            defaults.set(dict, forKey: key)
        }
    }

    // MARK: - Legacy migration

    /// Legacy keys and the preference name they migrate to.
    private var legacyMappings: [(legacyKey: String, name: String)] {
        [
            ("mirror_max_size", "maxSize"),
            ("mirror_max_fps", "maxFPS"),
            ("mirror_bit_rate", "bitRate"),
            ("mirror_flex_display", "flexDisplay"),
        ]
    }

    /// Copies legacy transport-keyed dictionaries onto identity keys.
    /// Safe to call repeatedly; already-migrated values are never overwritten.
    func migrateLegacyDictionaries() {
        for mapping in legacyMappings {
            guard let legacy = defaults.dictionary(forKey: mapping.legacyKey), !legacy.isEmpty else {
                continue
            }
            for (transportID, value) in legacy {
                let identity = identity(forTransportID: transportID)
                guard rawValue(mapping.name, identity: identity) == nil else { continue }
                write(value, name: mapping.name, identity: identity)
            }
        }
    }

    // MARK: - Storage

    private func storageKey(_ name: String) -> String { namespace + name }

    private func rawValue(_ name: String, identity: String) -> Any? {
        defaults.dictionary(forKey: storageKey(name))?[identity]
    }

    private func write(_ value: Any, name: String, identity: String) {
        var dict = defaults.dictionary(forKey: storageKey(name)) ?? [:]
        dict[identity] = value
        defaults.set(dict, forKey: storageKey(name))
    }
}
