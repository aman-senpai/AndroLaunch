//
//  PairingViewModel.swift
//  AndroLaunch
//
//  Created by Aman Raj on 22/11/25.
//

import Foundation
import Combine
import CoreImage.CIFilterBuiltins
import AppKit

final class PairingViewModel: ObservableObject {
    @Published var qrCodeImage: NSImage?
    @Published var statusMessage: String = "Initializing..."
    @Published var isPairing: Bool = false
    @Published var pairingCode: String = ""
    
    private let pairingService: ADBPairingServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(pairingService: ADBPairingServiceProtocol = DependencyContainer.shared.adbPairingService) {
        self.pairingService = pairingService
        bindService()
    }
    
    func startPairing() {
        // This generates a NEW password and QR string every time it's called
        let (qrString, password) = pairingService.startPairing()
        self.pairingCode = password
        generateQRCode(from: qrString)
    }
    
    func stopPairing() {
        pairingService.stopPairing()
    }
    
    private func bindService() {
        pairingService.pairingStatus
            .receive(on: DispatchQueue.main)
            .assign(to: \.statusMessage, on: self)
            .store(in: &cancellables)
            
        pairingService.isPairing
            .receive(on: DispatchQueue.main)
            .assign(to: \.isPairing, on: self)
            .store(in: &cancellables)
        
        // NEW: Listen for successful connection and loop
        pairingService.pairingComplete
            .receive(on: DispatchQueue.main)
            .delay(for: .seconds(3.0), scheduler: DispatchQueue.main) // Delay to show "Connected" status
            .sink { [weak self] in
                print("PairingViewModel: Device connected. Restarting pairing for next device...")
                self?.startPairing() // Generate new QR and restart process
            }
            .store(in: &cancellables)
    }
    
    private func generateQRCode(from string: String) {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        
        if let outputImage = filter.outputImage {
            // Scale up the image
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                self.qrCodeImage = NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
            }
        }
    }
}