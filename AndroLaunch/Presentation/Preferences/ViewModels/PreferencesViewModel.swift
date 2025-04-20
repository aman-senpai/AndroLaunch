//
//  PreferencesViewModel.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import Foundation // Import Foundation for DispatchQueue
import Combine
import SwiftUI // Import SwiftUI for ObservableObject

// Import the protocol from the Domain layer
// If not a module, you might need a specific import like:
// import YourModuleName.DeviceRepositoryProtocol


// The repository instance must conform to DeviceRepositoryProtocol (which is ObservableObject)
final class PreferencesViewModel: ObservableObject {
    @Published var adbStatus: String = "Checking..."
    @Published var errorMessage: String?

    // The repository must conform to DeviceRepositoryProtocol (which inherits ObservableObject)
    // This protocol needs to explicitly expose 'errorPublisher'.
    internal let repository: any DeviceRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()

    // Initialize with a repository that conforms to DeviceRepositoryProtocol
    init(deviceRepository: any DeviceRepositoryProtocol) {
        self.repository = deviceRepository
        setupObservers()
    }

    private func setupObservers() {
        // Observe the errorPublisher REQUIRED by DeviceRepositoryProtocol
        // This line REQUIRES DeviceRepositoryProtocol to define:
        // var errorPublisher: AnyPublisher<String?, Never> { get }
        repository.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (error: String?) in // Explicitly type the error parameter as String?
                print("PreferencesViewModel: Received error update: \(error ?? "nil")") // Added for debugging
                self?.adbStatus = error == nil ? "Connected" : "Error"
                self?.errorMessage = error
            }
            .store(in: &cancellables)

        // You might also want to observe the isLoadingPublisher if you want to show
        // a loading indicator in the preferences view.
        // This would require adding:
        // var isLoadingPublisher: AnyPublisher<Bool, Never> { get }
        // to the DeviceRepositoryProtocol.
        // repository.isLoadingPublisher
        //     .receive(on: DispatchQueue.main)
        //     .sink { [weak self] isLoading in
        //         print("PreferencesViewModel: Received isLoading update: \(isLoading)") // Added for debugging
        //         // Update a local @Published isLoading property if you have one
        //         // self?.isLoading = isLoading
        //     }
        //     .store(in: &cancellables)
    }

    // You might want methods here to trigger repository actions if needed by the preferences view,
    // e.g., a method to manually check ADB status.
    func checkAdbStatus() {
        print("PreferencesViewModel: Requesting refreshDevices to check status...") // Added for debugging
        repository.refreshDevices() // Refreshing devices often implies checking ADB status
    }
}
