//
//  DependencyContainer.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//
import Foundation
import Combine
 // Replace 'AndroLaunch' with your project's main module name

final class DependencyContainer {
    static let shared = DependencyContainer()

    // Services
    private lazy var adbService: ADBServiceProtocol = ADBService()
    private lazy var scrcpyService: ScrcpyServiceProtocol = ScrcpyService() // Correct initialization
    
    // Repositories
    private lazy var deviceRepository: any DeviceRepositoryProtocol = DeviceRepository(
        adbService: adbService,
        scrcpyService: scrcpyService // Pass scrcpyService
    )

    lazy var menuViewModel: MenuViewModel = MenuViewModel(
        deviceRepository: deviceRepository
    )
}
