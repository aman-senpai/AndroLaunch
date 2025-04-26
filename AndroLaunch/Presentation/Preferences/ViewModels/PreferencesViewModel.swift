//
//  PreferencesViewModel.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import Foundation
import Combine
import SwiftUI


// The repository instance must conform to DeviceRepositoryProtocol (which is ObservableObject)
final class PreferencesViewModel: ObservableObject {
    @Published var adbStatus: String = "Checking..."
    @Published var errorMessage: String?

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
                print("PreferencesViewModel: Received error update: \(error ?? "nil")")
                self?.adbStatus = error == nil ? "Connected" : "Error"
                self?.errorMessage = error
            }
            .store(in: &cancellables)


    }

    func checkAdbStatus() {
        print("PreferencesViewModel: Requesting refreshDevices to check status...")
        repository.refreshDevices()
    }
}
