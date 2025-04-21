# AndroLaunch - Android Device Management Suite 🚀

![Swift Version](https://img.shields.io/badge/Swift-5.7+-orange.svg)
![Platform](https://img.shields.io/badge/macOS-12+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)

A professional macOS menu bar application for managing Android devices through ADB and Scrcpy, built with modern Swift architecture patterns.

## Features ✨
- **Device Management**:
  - List connected Android devices
  - Refresh device list in real-time
  - Display device status (connected/unauthorized)
- **App Management**:
  - List installed apps per device
  - Launch apps directly from menu
  - Refresh app list dynamically
- **Device Mirroring**:
  - Full device screen mirroring via Scrcpy
  - Launch apps in dedicated windows
  - Custom display resolutions
- **ADB Management**:
  - Automatic ADB path discovery
  - Daemon management
  - Error handling and recovery
- **Preferences**:
  - ADB status monitoring
  - Error display and recovery guidance

## Architecture 🏛️
![Clean Architecture Diagram](https://via.placeholder.com/800x400.png?text=Clean+Architecture+Diagram)

### Core Principles
- **Clean Architecture** with strict layer separation
- **MVVM** pattern for UI management
- **Reactive Programming** with Combine
- **Protocol-Oriented** design
- **Dependency Injection** through centralized container

### Layer Structure
| Layer | Components | Responsibility |
|-------|------------|-----------------|
| **Presentation** | `StatusMenuController`, `PreferencesView` | UI rendering, user interactions |
| **Domain** | `AndroidDevice`, `AndroidApp`, Protocols | Business logic, data models |
| **Data** | `ADBService`, `ScrcpyService`, `DeviceRepository` | Service implementations, data access |
| **Core** | `DependencyContainer`, `AppConstants` | DI, configuration, utilities |

## Key Components 🔑

### Service Layer
| Service | Protocol | Implementation | Description |
|---------|----------|-----------------|-------------|
| ADB Manager | `ADBServiceProtocol` | `ADBService` | Handles all ADB operations and device communication |
| Scrcpy Controller | `ScrcpyServiceProtocol` | `ScrcpyService` | Manages device mirroring and app launching |

### Repository Pattern
```swift
protocol DeviceRepositoryProtocol {
    func refreshDevices()
    func fetchApps(for deviceID: String)
    func launchApp(packageID: String, deviceID: String)
    func mirrorDevice(deviceID: String)
}
