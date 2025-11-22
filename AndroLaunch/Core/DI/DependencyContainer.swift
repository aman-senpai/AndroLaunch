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
    var adbService: ADBServiceProtocol { get }
    var adbPairingService: ADBPairingServiceProtocol { get }
    var scrcpyService: ScrcpyServiceProtocol { get }
    var deviceRepository: DeviceRepositoryProtocol { get }
    var menuViewModel: MenuViewModel { get }
}

final class DependencyContainer: DependencyContainerProtocol {
    static let shared = DependencyContainer()

    // MARK: - Private Properties
    private let commandExecutor: CommandExecutorProtocol
    private let adbServiceInstance: ADBServiceProtocol
    private let adbPairingServiceInstance: ADBPairingServiceProtocol
    private let scrcpyServiceInstance: ScrcpyServiceProtocol
    private let deviceRepositoryInstance: DeviceRepositoryProtocol
    private let menuViewModelInstance: MenuViewModel

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
    }

    // MARK: - Public Properties
    var adbService: ADBServiceProtocol { adbServiceInstance }
    var adbPairingService: ADBPairingServiceProtocol { adbPairingServiceInstance }
    var scrcpyService: ScrcpyServiceProtocol { scrcpyServiceInstance }
    var deviceRepository: DeviceRepositoryProtocol { deviceRepositoryInstance }
    var menuViewModel: MenuViewModel { menuViewModelInstance }
}
