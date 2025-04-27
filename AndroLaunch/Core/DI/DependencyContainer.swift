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
    var scrcpyService: ScrcpyServiceProtocol { get }
    var deviceRepository: DeviceRepositoryProtocol { get }
    var menuViewModel: MenuViewModel { get }
}

final class DependencyContainer: DependencyContainerProtocol {
    static let shared = DependencyContainer()

    // MARK: - Private Properties
    private let adbServiceInstance: ADBServiceProtocol
    private let scrcpyServiceInstance: ScrcpyServiceProtocol
    private let deviceRepositoryInstance: DeviceRepositoryProtocol
    private let menuViewModelInstance: MenuViewModel

    // MARK: - Initialization
    init(
        adbService: ADBServiceProtocol = ADBService(),
        scrcpyService: ScrcpyServiceProtocol = ScrcpyService()
    ) {
        self.adbServiceInstance = adbService
        self.scrcpyServiceInstance = scrcpyService
        self.deviceRepositoryInstance = DeviceRepository(
            adbService: adbService,
            scrcpyService: scrcpyService
        )
        self.menuViewModelInstance = MenuViewModel(
            deviceRepository: deviceRepositoryInstance
        )
    }

    // MARK: - Public Properties
    var adbService: ADBServiceProtocol { adbServiceInstance }
    var scrcpyService: ScrcpyServiceProtocol { scrcpyServiceInstance }
    var deviceRepository: DeviceRepositoryProtocol { deviceRepositoryInstance }
    var menuViewModel: MenuViewModel { menuViewModelInstance }
}
