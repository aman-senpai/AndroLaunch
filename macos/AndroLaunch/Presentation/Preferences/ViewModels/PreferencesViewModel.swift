//
//  PreferencesViewModel.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import Combine
import Foundation
import SwiftUI

// The repository instance must conform to DeviceRepositoryProtocol (which is ObservableObject)
final class PreferencesViewModel: ObservableObject {
    @Published var adbStatus: String = "Checking..."

    var commandLineToolsPath: String {
        get { repository.commandLineToolsPath ?? "" }
        set { repository.setCommandLineToolsPath(newValue) }
    }

    var adbPath: String? { repository.adbPath }

    internal let repository: any DeviceRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()

    // Initialize with a repository that conforms to DeviceRepositoryProtocol
    init(deviceRepository: any DeviceRepositoryProtocol) {
        self.repository = deviceRepository
        setupObservers()
    }

    private func setupObservers() {
        repository.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (error: String?) in
                self?.adbStatus = error == nil ? "Connected" : "Error"
            }
            .store(in: &cancellables)

    }

    func checkAdbStatus() {
        repository.refreshDevices()
    }
}
