//
//  AppPins.swift
//  AndroLaunch
//
//  Pinned ("favorite") apps for the Apps tab. Stored by package name so the pin
//  survives transport changes and App refresh. In snapshot/preview mode a fixed
//  set is used so design review sees the pinned state deterministically.
//

import Combine
import Foundation

final class AppPinsStore: ObservableObject {
    static let shared = AppPinsStore()

    /// Deterministic pins for `HubStore` previews and the snapshot renderer.
    static let previewPins: [String] = ["com.whatsapp", "com.google.android.youtube"]

    @Published private(set) var pinnedPackageIDs: [String]

    private let defaults: UserDefaults
    private let key = "apps.pinnedPackages"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.pinnedPackageIDs = defaults.stringArray(forKey: key) ?? []
    }

    func isPinned(packageID: String) -> Bool {
        pinnedPackageIDs.contains(packageID)
    }

    func togglePin(packageID: String) {
        if let index = pinnedPackageIDs.firstIndex(of: packageID) {
            pinnedPackageIDs.remove(at: index)
        } else {
            pinnedPackageIDs.append(packageID)
        }
        defaults.set(pinnedPackageIDs, forKey: key)
    }

    func unpin(packageID: String) {
        guard pinnedPackageIDs.contains(packageID) else { return }
        pinnedPackageIDs.removeAll { $0 == packageID }
        defaults.set(pinnedPackageIDs, forKey: key)
    }
}
