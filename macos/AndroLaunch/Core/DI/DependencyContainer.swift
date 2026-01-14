//
//  DependencyContainer.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//
import Foundation
import Combine
 // Replace 'AndroLaunch' with your project's main module name

protocol DependencyContainerProtocol {
    var adbService: any ADBServiceProtocol { get }
    var adbPairingService: any ADBPairingServiceProtocol { get }
    var scrcpyService: any ScrcpyServiceProtocol { get }
    var deviceRepository: any DeviceRepositoryProtocol { get }

    var menuViewModel: MenuViewModel { get }
    var preferencesViewModel: PreferencesViewModel { get }
}

final class DependencyContainer: DependencyContainerProtocol {
    static let shared = DependencyContainer()

    // MARK: - Private Properties
    private let commandExecutor: any CommandExecutorProtocol
    private let adbServiceInstance: any ADBServiceProtocol
    private let adbPairingServiceInstance: any ADBPairingServiceProtocol
    private let scrcpyServiceInstance: any ScrcpyServiceProtocol
    private let deviceRepositoryInstance: any DeviceRepositoryProtocol

    private let menuViewModelInstance: MenuViewModel
    private let preferencesViewModelInstance: PreferencesViewModel

    // MARK: - Initialization
    private init() {
        let commandExecutor = CommandExecutor()
        self.commandExecutor = commandExecutor

        self.adbServiceInstance = ADBService()
        self.adbPairingServiceInstance = ADBPairingService(commandExecutor: commandExecutor, adbService: adbServiceInstance)
        self.scrcpyServiceInstance = ScrcpyService()
        
        self.deviceRepositoryInstance = DeviceRepository(
            adbService: adbServiceInstance,
            scrcpyService: scrcpyServiceInstance
        )
        self.menuViewModelInstance = MenuViewModel(
            deviceRepository: deviceRepositoryInstance
        )
        self.preferencesViewModelInstance = PreferencesViewModel(
            deviceRepository: deviceRepositoryInstance
        )
    }

    // MARK: - Public Properties
    var adbService: any ADBServiceProtocol { adbServiceInstance }
    var adbPairingService: any ADBPairingServiceProtocol { adbPairingServiceInstance }
    var scrcpyService: any ScrcpyServiceProtocol { scrcpyServiceInstance }
    var deviceRepository: any DeviceRepositoryProtocol { deviceRepositoryInstance }

    var menuViewModel: MenuViewModel { menuViewModelInstance }
    var preferencesViewModel: PreferencesViewModel { preferencesViewModelInstance }
}
