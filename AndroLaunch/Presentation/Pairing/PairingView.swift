//
//  PairingView.swift
//  AndroLaunch
//
//  Created by Aman Raj on 22/11/25.
//

import SwiftUI

struct PairingView: View {
    @StateObject private var viewModel = PairingViewModel()
    
    var body: some View {
        VStack(spacing: 20) {            
            if let qrImage = viewModel.qrCodeImage {
                Image(nsImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 200, height: 200)
                    .overlay(Text("Generating QR..."))
            }
            
            VStack(spacing: 8) {
                Text("Scan this QR code with your device")
                    .font(.subheadline)
                Text("Settings > Developer Options > Wireless Debugging > Pair device with QR code")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
                    .padding(.horizontal)
            }
            
            Divider()
            
            VStack(spacing: 4) {
                Text("Status")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(viewModel.statusMessage)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
                    .padding(.horizontal)
            }
            
            if !viewModel.pairingCode.isEmpty {
                Text(viewModel.pairingCode)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.bottom)
            }
        }
        .padding()
        .frame(width: 350, height: 450)
        .onAppear {
            viewModel.startPairing()
        }
        .onDisappear {
            viewModel.stopPairing()
        }
    }
}
