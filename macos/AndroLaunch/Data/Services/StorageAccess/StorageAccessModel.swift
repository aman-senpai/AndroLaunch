//
//  StorageAccessModel.swift
//  AndroLaunch
//
//  Observable wrapper around protocol v5's storage-permission handshake.
//
//  No UI here: the storage sheet, dashboard or settings surface reads `state`
//  and calls `refresh` / `requestAccess`. The grant itself always happens in
//  Android Settings, so `requestAccess` re-reads the state afterwards instead of
//  assuming the tap succeeded.
//

import Combine
import Foundation

final class StorageAccessModel: ObservableObject {

    static let shared = StorageAccessModel()

    /// Last successfully decoded state, or nil before the first check.
    @Published private(set) var state: StorageAccessState?
    /// Device the current state belongs to.
    @Published private(set) var deviceID: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRequesting = false
    @Published private(set) var lastError: String?

    private let companion: CompanionClient
    private var refreshToken = UUID()

    init(companion: CompanionClient = .shared) {
        self.companion = companion
    }

    // MARK: - Derived state

    var isGranted: Bool { state?.granted == true }

    /// True once a check has run and the phone needs the user to grant access.
    var needsGrant: Bool { state?.needsGrant == true }

    var summary: String { state?.summary ?? "Storage access" }

    /// One sentence for a row subtitle; never empty.
    var detailText: String {
        if let state { return state.detail }
        if let lastError { return lastError }
        return "Storage access has not been checked yet."
    }

    // MARK: - Actions

    /// Reads the current permission state from the phone. Safe to call often; the
    /// newest request wins and stale answers are dropped.
    func refresh(deviceID: String) {
        guard !deviceID.isEmpty else { return }
        let token = UUID()
        refreshToken = token
        isRefreshing = true

        companion.storageAccess(deviceID: deviceID) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.refreshToken == token else { return }
                self.isRefreshing = false
                self.deviceID = deviceID
                switch result {
                case .success(let state):
                    self.state = state
                    self.lastError = nil
                case .failure(let error):
                    self.lastError = StorageAccessLogic.friendlyError(error.localizedDescription)
                }
            }
        }
    }

    /// Opens the Android screen that grants storage access, then re-reads state
    /// once the user has had time to toggle it.
    func requestAccess(deviceID: String, completion: ((Bool) -> Void)? = nil) {
        guard !deviceID.isEmpty else {
            completion?(false)
            return
        }
        guard !isRequesting else {
            completion?(false)
            return
        }
        isRequesting = true

        companion.requestStorageAccess(deviceID: deviceID) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isRequesting = false
                self.deviceID = deviceID
                switch result {
                case .success(let opened):
                    if opened {
                        self.lastError = nil
                        completion?(true)
                        // The user is on a Settings screen on the phone now; check
                        // again shortly so a grant shows up without a manual reload.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            self.refresh(deviceID: deviceID)
                        }
                    } else {
                        self.lastError = StorageAccessLogic.friendlyError("failed")
                        completion?(false)
                    }
                case .failure(let error):
                    self.lastError = StorageAccessLogic.friendlyError(error.localizedDescription)
                    completion?(false)
                }
            }
        }
    }

    /// Clears cached state (device switched or disconnected).
    func reset() {
        refreshToken = UUID()
        state = nil
        deviceID = nil
        isRefreshing = false
        isRequesting = false
        lastError = nil
    }
}
