//
//  EmulatorManagerViewModel.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 16/1/26.
//

import Combine
import Foundation
import SwiftUI

final class EmulatorManagerViewModel: ObservableObject {
    @Published var availableImages: [SystemImage] = []
    @Published var existingAVDs: [AVD] = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var errorMessage: String?
    @Published var isLoadingImages: Bool = false
    @Published var isLoadingAVDs: Bool = false
    @Published var isCreatingAVD: Bool = false
    @Published var selectedImageIds: Set<String> = []
    @Published var hardwareProfiles: [HardwareProfile] = []
    
    var commandLineToolsPath: String {
        get { repository.commandLineToolsPath ?? "" }
        set { repository.setCommandLineToolsPath(newValue) }
    }
    
    private let repository: any DeviceRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()
    private var pollingTimer: AnyCancellable?
    
    // Transient state tracking for immediate UI feedback
    private var startingAVDs: Set<String> = []
    private var stoppingAVDs: Set<String> = []
    
    init(repository: any DeviceRepositoryProtocol) {
        self.repository = repository
        setupBindings()
        startPolling()
    }
    
    deinit {
        stopPolling()
    }
    
    private func setupBindings() {
        repository.imagesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] images in
                self?.availableImages = images
                self?.isLoadingImages = false
            }
            .store(in: &cancellables)
            
        repository.avdsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] avds in
                guard let self else { return }
                
                // Merge real state with transient state
                var displayAVDs = avds
                
                // 1. Clean up transient states based on real state updates
                for avd in avds {
                    if avd.isRunning {
                        // If it's running, it's no longer starting
                        self.startingAVDs.remove(avd.name)
                    } else {
                        // If it's not running, it's no longer stopping
                        self.stoppingAVDs.remove(avd.name)
                    }
                }
                
                // 2. Apply transient states to display models
                for i in 0..<displayAVDs.count {
                    let name = displayAVDs[i].name
                    if self.startingAVDs.contains(name) {
                        displayAVDs[i].isStarting = true
                    }
                    if self.stoppingAVDs.contains(name) {
                        displayAVDs[i].isStopping = true
                    }
                }
                
                self.existingAVDs = displayAVDs
                self.isLoadingAVDs = false
                self.isCreatingAVD = false
            }
            .store(in: &cancellables)
            
        repository.downloadProgressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (imagePath, progress) in
                self?.objectWillChange.send()
                if progress >= 1.0 {
                    self?.downloadProgress.removeValue(forKey: imagePath)
                } else {
                    self?.downloadProgress[imagePath] = progress
                }
            }
            .store(in: &cancellables)
            
        repository.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.errorMessage = error
                self?.isLoadingImages = false
                self?.isLoadingAVDs = false
                self?.isCreatingAVD = false
            }
            .store(in: &cancellables)
    }
    
    func refresh() {
        errorMessage = nil
        isLoadingImages = true
        isLoadingAVDs = true
        repository.listAvailableImages()
        repository.listAVDs()
        repository.listHardwareProfiles { [weak self] profiles in
            self?.hardwareProfiles = profiles
        }
    }
    
    func downloadImage(_ imagePath: String) {
        repository.downloadImage(imagePath: imagePath)
    }
    
    func toggleSelection(_ imageId: String) {
        if selectedImageIds.contains(imageId) {
            selectedImageIds.remove(imageId)
        } else {
            selectedImageIds.insert(imageId)
        }
    }
    
    func downloadSelected() {
        let ids = Array(selectedImageIds)
        selectedImageIds.removeAll()
        for id in ids {
            repository.downloadImage(imagePath: id)
        }
    }
    
    func cancelDownload(_ imageId: String) {
        repository.cancelDownload(imagePath: imageId)
        // Optimistically remove progress so UI updates immediately
        DispatchQueue.main.async {
            self.downloadProgress.removeValue(forKey: imageId)
        }
    }
    
    func deleteSelectedImages(_ ids: Set<String>) {
        isLoadingImages = true
        for id in ids {
            repository.deleteImage(imagePath: id)
        }
    }
    
    func createAVD(name: String, imagePath: String, device: String? = nil, options: AVDOptions) {
        isCreatingAVD = true
        repository.createAVD(name: name, imagePath: imagePath, device: device, options: options)
    }
    
    func deleteAVD(name: String) {
        isLoadingAVDs = true
        repository.deleteAVD(name: name)
    }
    
    func renameAVD(oldName: String, newName: String) {
        isLoadingAVDs = true
        repository.renameAVD(oldName: oldName, newName: newName)
    }
    
    func startEmulator(avdName: String) {
        startingAVDs.insert(avdName)
        // Force update to show spinner immediately
        refreshDisplayAVDs()
        
        repository.startEmulator(avdName: avdName)
        
        // Polling status: check more frequently while starting
        pollEmulatorStatus(avdName: avdName, retryCount: 0)
    }
    
    private func pollEmulatorStatus(avdName: String, retryCount: Int) {
        // Max 30 retries (approx 60-90 seconds)
        guard retryCount < 30 else {
            startingAVDs.remove(avdName)
            refreshDisplayAVDs()
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + (retryCount < 5 ? 2.0 : 5.0)) { [weak self] in
            guard let self = self else { return }
            
            // If it's already running, stop polling
            if self.existingAVDs.first(where: { $0.name == avdName })?.isRunning == true {
                self.startingAVDs.remove(avdName)
                self.refreshDisplayAVDs()
                return
            }
            
            // Still starting, refresh and poll again
            self.repository.listAVDs()
            
            if self.startingAVDs.contains(avdName) {
                self.pollEmulatorStatus(avdName: avdName, retryCount: retryCount + 1)
            }
        }
    }
    
    func stopEmulator(avdName: String) {
        stoppingAVDs.insert(avdName)
        // Force update to show spinner immediately
        refreshDisplayAVDs()
        
        repository.stopEmulator(avdName: avdName)
        // Instant feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.repository.listAVDs()
        }
    }
    
    // Helper to refresh the existingAVDs list with current transient states
    // This is useful when we want to update the UI without waiting for a repository fetch
    private func refreshDisplayAVDs() {
        var displayAVDs = existingAVDs
        for i in 0..<displayAVDs.count {
            let name = displayAVDs[i].name
            if startingAVDs.contains(name) {
                displayAVDs[i].isStarting = true
            }
            if stoppingAVDs.contains(name) {
                displayAVDs[i].isStopping = true
            }
        }
        self.existingAVDs = displayAVDs
    }

    private func startPolling() {
        pollingTimer = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // Only refresh AVDs status, not the full image list
                self?.repository.listAVDs()
            }
    }

    private func stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }
}
