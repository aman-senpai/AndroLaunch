# AndroLaunch - Android Device Management Suite

<p align="center">
  <img src="https://github.com/user-attachments/assets/542a6e2b-d7f3-450b-89a3-cd5e110a765e" width="90%" />
</p>

<p align="center">
  <img alt="menu" src="https://github.com/user-attachments/assets/49159179-50b4-462d-a16f-97d0db7d102e" width="28%"/>
  <img src="https://github.com/user-attachments/assets/746c4b02-cdf1-4d9e-b28b-72d185a9aa6b" width="28%" />
  <img src="https://github.com/user-attachments/assets/679d98b6-05d9-4802-a987-4afe14720e22" width="28%" />
  <img alt="" src="https://github.com/user-attachments/assets/b1a7954e-3c37-4f6f-99a6-37a37359a390" width="28%"/>


</p>

![Swift Version](https://img.shields.io/badge/Swift-5.7+-orange.svg)
![Platform](https://img.shields.io/badge/macOS-12+-blue.svg)

A professional macOS menu bar application for managing Android devices through ADB and Scrcpy, built with modern Swift architecture patterns.

## Features ✨

- **Device Management**:
  - List connected Android devices
  - Refresh device list in real-time
  - Display device status (connected/unauthorized)
- **Quick Actions**:
  - Toggle WiFi, Bluetooth, Mobile Data, etc.
  - Reboot device (System/Bootloader/Recovery)
  - Adjust brightness and volume
- **App Management**:
  - List installed apps per device
  - Launch apps directly from menu
  - **New**: Uninstall apps with confirmation
  - **New**: Install APKs directly from file
  - Refresh app list dynamically
- **Device Mirroring**:
  - Full device screen mirroring via Scrcpy
  - Launch apps in dedicated windows
  - Custom display resolutions
  - **New**: Audio toggle and camera controls
  - **New**: Low latency audio buffering
- **ADB Management**:
  - Automatic ADB path discovery
  - **New**: Open ADB Shell terminal
  - **New**: Wireless pairing with QR code
  - Daemon management
  - Error handling and recovery
- **Preferences**:
  - ADB status monitoring
  - Error display and recovery guidance

## Architecture 🏛️

The project follows Clean Architecture principles with the following layers:

### Core Layer

- **Services**: Core services like ADB service, device management
- **DI**: Dependency injection container
- **Constants**: App-wide constants and configurations

### Data Layer

- **Repositories**: Implementation of repository interfaces
- **Parsers**: Data parsing and transformation
- **Services**: Data-related services

### Domain Layer

- **Models**: Business models and entities
- **UseCases**: Business logic and use cases
- **Repositories**: Repository interfaces

### Presentation Layer

- **MenuBar**: Menu bar UI components
- **Preferences**: Settings and preferences UI

## Key Components 🔑

### Service Layer

| Service           | Protocol                | Implementation  | Description                                         |
| ----------------- | ----------------------- | --------------- | --------------------------------------------------- |
| ADB Manager       | `ADBServiceProtocol`    | `ADBService`    | Handles all ADB operations and device communication |
| Scrcpy Controller | `ScrcpyServiceProtocol` | `ScrcpyService` | Manages device mirroring and app launching          |

### Repository Pattern

```swift
protocol DeviceRepositoryProtocol {
    func refreshDevices()
    func fetchApps(for deviceID: String)
    func launchApp(packageID: String, deviceID: String)
    func mirrorDevice(deviceID: String)
}
```

### ViewModel Structure

```mermaid
graph TD
    A[StatusMenuController] --> B[MenuViewModel]
    B --> C[DeviceRepository]
    C --> D[ADBService]
    C --> E[ScrcpyService]
    F[PreferencesView] --> G[PreferencesViewModel]
    G --> C
```

## Data Flow 🔄

1. **User Action** (e.g., Refresh Devices)
2. **ViewModel** receives action
3. **Repository** coordinates services
4. **Service** executes platform-specific operations
5. **Combine Publishers** propagate changes back
6. **UI** updates automatically

## Setup

1. Clone the repository
2. Install dependencies:
   ```bash
   brew install android-platform-tools
   ```
3. Open `AndroLaunch.xcodeproj` in Xcode
4. Build and run the project

## Development

### Prerequisites

- Xcode 15.0+
- macOS 13.0+
- Android SDK
- ADB (Android Debug Bridge)

### Building

1. Open the project in Xcode
2. Select your target device
3. Build and run (⌘R)

### Testing

- Unit tests are located in the `Tests` directory
- UI tests are located in the `UITests` directory

## Contributing 🤝

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes
4. Push to branch
5. Open Pull Request

## License 📄

This project is licensed under the MIT License.

---

**Powered By**:
[<img src="https://github.com/Genymobile/scrcpy/raw/master/app/data/icon.svg" width=25>](https://github.com/Genymobile/scrcpy)
