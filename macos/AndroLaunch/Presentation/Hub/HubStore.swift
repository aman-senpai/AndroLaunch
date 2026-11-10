//
//  HubStore.swift
//  AndroLaunch
//
//  Small, shared state for the Hub window: which tab is visible, the device
//  feed, and the selected device's app catalog. Feature services stay separate
//  singletons so parallel features never fight over one stored-property bag.
//

import Combine
import Foundation
import SwiftUI

final class HubStore: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case devices
        case apps
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .devices: return "Devices"
            case .apps: return "Apps"
            case .settings: return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .devices: return "iphone.gen3"
            case .apps: return "square.grid.2x2.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    static let shared = HubStore()

    @Published var tab: Tab = .devices
    @Published var devices: [AndroidDevice] = []
    @Published var selectedDeviceID: String?
    @Published var apps: [AndroidApp] = []
    @Published var isLoadingApps: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var statusMessage: String?

    /// Snapshot/preview mode: never talks to ADB and never starts services.
    let isPreview: Bool

    private let repository: DeviceRepositoryProtocol?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(repository: DeviceRepositoryProtocol = DependencyContainer.shared.deviceRepository) {
        self.repository = repository
        self.isPreview = false
        bind()
        refresh()
    }

    /// Deterministic data for `ImageRenderer` snapshots and SwiftUI previews.
    init(previewDevices: [AndroidDevice], apps: [AndroidApp] = HubPreviewData.apps) {
        self.repository = nil
        self.isPreview = true
        self.devices = previewDevices
        self.apps = apps
        self.selectedDeviceID = previewDevices.first?.id
    }

    private func bind() {
        guard let repository else { return }
        repository.devicesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                guard let self else { return }
                self.devices = devices
                if let selected = self.selectedDeviceID,
                    !devices.contains(where: { $0.id == selected })
                {
                    self.selectedDeviceID = devices.first?.id
                } else if self.selectedDeviceID == nil {
                    self.selectedDeviceID = devices.first?.id
                }
                if let id = self.selectedDeviceID {
                    self.loadApps(for: id)
                }
                self.isRefreshing = false
            }
            .store(in: &cancellables)

        repository.appsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] apps in self?.apps = apps }
            .store(in: &cancellables)

        repository.isLoadingAppsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in self?.isLoadingApps = loading }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    func refresh() {
        guard let repository else { return }
        isRefreshing = true
        repository.refreshDevices()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.isRefreshing = false
        }
    }

    func select(_ device: AndroidDevice) {
        guard selectedDeviceID != device.id else { return }
        selectedDeviceID = device.id
        if let repository {
            repository.fetchApps(for: device.id)
        }
    }

    func loadApps(for deviceID: String) {
        guard let repository, !isPreview else { return }
        // Device updates (battery/transport) can re-enter this path several
        // times in one runloop; concurrent scrcpy --list-apps processes fight
        // over the server and return no apps. Keep one fetch in flight.
        guard !isLoadingApps else { return }
        repository.fetchApps(for: deviceID)
    }

    // MARK: - Derived

    var selectedDevice: AndroidDevice? {
        if let selectedDeviceID,
            let match = devices.first(where: { $0.id == selectedDeviceID })
        {
            return match
        }
        return devices.first
    }

    var connectedDevices: [AndroidDevice] { devices.filter(\.isConnected) }

    /// Up to five simultaneous devices are supported (reference product limit).
    var deviceLimitReached: Bool { devices.count >= 5 }
}
