//
//  QuickActionsView.swift
//  AndroLaunch
//
//  Created by Aman Raj on 27/11/25.
//

import SwiftUI

struct QuickActionsView: View {
    @StateObject var viewModel: QuickActionsViewModel
    
    @State private var showRebootConfirmation = false
    @State private var selectedRebootMode: RebootMode = .normal
    
    private func confirmReboot(mode: RebootMode) {
        selectedRebootMode = mode
        showRebootConfirmation = true
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "bolt.fill")
                Text("Quick Actions")
                    .font(.headline)
                Spacer()
                Text(viewModel.deviceID)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 100)
            }
            .padding(.bottom, 4)
            
            Divider()
            
            // Reboot Options
            VStack(alignment: .leading, spacing: 8) {
                Text("Reboot Options")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    ActionButton(icon: "power", label: "Reboot", color: .red) {
                        confirmReboot(mode: .normal)
                    }
                    
                    ActionButton(icon: "laptopcomputer", label: "Bootloader", color: .orange) {
                        confirmReboot(mode: .bootloader)
                    }
                    
                    ActionButton(icon: "wrench.and.screwdriver", label: "Recovery", color: .blue) {
                        confirmReboot(mode: .recovery)
                    }
                }
            }
            
            Divider()
            
            // Toggles
            VStack(alignment: .leading, spacing: 8) {
                Text("System Toggles")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Row 1
                HStack(spacing: 12) {
                    ToggleButtonStyle(
                        icon: "wifi",
                        label: "Wi-Fi",
                        isOn: $viewModel.isWifiEnabled,
                        action: viewModel.toggleWifi
                    )
                    
                    ToggleButtonStyle(
                        icon: "wave.3.right",
                        label: "Bluetooth",
                        isOn: $viewModel.isBluetoothEnabled,
                        action: viewModel.toggleBluetooth
                    )
                    
                    ToggleButtonStyle(
                        icon: "moon.fill",
                        label: "Dark Mode",
                        isOn: $viewModel.isDarkModeEnabled,
                        action: viewModel.toggleDarkMode
                    )
                }
                
                // Row 2
                HStack(spacing: 12) {
                    ToggleButtonStyle(
                        icon: "airplane",
                        label: "Airplane",
                        isOn: $viewModel.isAirplaneModeEnabled,
                        action: viewModel.toggleAirplaneMode
                    )
                    
                    ToggleButtonStyle(
                        icon: "antenna.radiowaves.left.and.right",
                        label: "Mobile Data",
                        isOn: $viewModel.isMobileDataEnabled,
                        action: viewModel.toggleMobileData
                    )
                    
                    ToggleButtonStyle(
                        icon: "location.fill",
                        label: "Location",
                        isOn: $viewModel.isLocationEnabled,
                        action: viewModel.toggleLocation
                    )
                }
                
                // Row 3
                HStack(spacing: 12) {
                    ToggleButtonStyle(
                        icon: "bell.slash.fill",
                        label: "DND",
                        isOn: $viewModel.isDoNotDisturbEnabled,
                        action: viewModel.toggleDoNotDisturb
                    )
                    
                    ToggleButtonStyle(
                        icon: "arrow.triangle.2.circlepath",
                        label: "Rotate",
                        isOn: $viewModel.isAutoRotateEnabled,
                        action: viewModel.toggleAutoRotate
                    )
                    
                    ToggleButtonStyle(
                        icon: "sun.max.fill",
                        label: "Adaptive",
                        isOn: $viewModel.isAdaptiveBrightnessEnabled,
                        action: viewModel.toggleAdaptiveBrightness
                    )
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 340, height: 420)
        .onAppear {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .alert(isPresented: $showRebootConfirmation) {
            Alert(
                title: Text("Confirm Reboot"),
                message: Text("Are you sure you want to reboot the device into \(selectedRebootMode.rawValue.isEmpty ? "System" : selectedRebootMode.rawValue.capitalized) mode?"),
                primaryButton: .destructive(Text("Reboot")) {
                    viewModel.reboot(mode: selectedRebootMode)
                },
                secondaryButton: .cancel()
            )
        }
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ToggleButtonStyle: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isOn ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.1))
            .foregroundColor(isOn ? .accentColor : .primary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isOn ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
