# Continuity layer — architecture contract

AndroLaunch's next milestone is *continuity*: the app should stop caring which
transport a phone is on, and the everyday loops (paste, send a file, see a
notification) should work without opening a panel. This document is the contract
that the macOS feature work builds against. Read it before touching the code.

## 1. Identity: one device, many transports

ADB identifies a device by its current transport, so the same phone is
`R58M…` over USB and `192.168.1.5:5555` over Wi-Fi. Anything that must survive a
transport change is keyed by **hardware serial**, never by transport ID.

```swift
device.stableID          // serialNumber when known, else transport ID
device.transportKind     // .usb / .wireless / .mdns / .manual
device.isWirelessTransport
```

- `AndroidDevice+Identity.swift` — the extension above.
- `DeviceScopedPreferences` — UserDefaults store keyed by `stableID`. Legacy
  dictionaries keyed by transport ID are migrated through
  `migrateLegacyDictionaries()` once the device list is known.
- `DeviceEndpoint` / `TransportKind` — a reachable address plus its quality
  history. `TransportKind.raceRank` is the preference order when racing.

**Rule:** new persistent state is written through `DeviceScopedPreferences` with
`device.stableID`. Never persist a raw `device.id`.

## 2. Endpoints: race, don't guess

`EndpointStore` (shared, UserDefaults-backed) records every transport that ever
reached a device:

```swift
EndpointStore.shared.candidates(for: identity)   // best first, stale failures dropped
EndpointStore.shared.recordSuccess(address:for:)
EndpointStore.shared.recordFailure(address:for:)
EndpointStore.shared.upsert(DeviceEndpoint(...), for:)
```

USB is preferred, then Bonjour service names (stable across DHCP), then a
remembered IP, then a user-added/VPN address. Racing means: start the candidates
concurrently, take the first success, cancel the rest.

## 3. Menu contributions

The status menu is one ordered list. Features do **not** edit
`StatusMenuController.rebuildMenu`; they implement `MenuSectionProviding` in their
own file, and `MenuSectionRegistry` is the only place that lists them.

```swift
protocol MenuSectionProviding: AnyObject {
    var sectionID: String { get }
    var topLevelOrder: Int { get }
    func topLevelItems() -> [NSMenuItem]          // after the device list
    func deviceItems(for: AndroidDevice) -> [NSMenuItem]  // in a device submenu
    func menuWillOpen()                            // update retained items in place
}
```

Top-level items are rebuilt with the menu; per-device items are rebuilt with the
submenu. Anything that changes while the menu is open (a toggle's state, a
progress line) must update retained `NSMenuItem` references inside
`menuWillOpen()`.

## 4. Services and DI

`DependencyContainer.shared` is the single container:

```swift
DependencyContainer.shared.adb              // concrete ADBService (feature hooks)
DependencyContainer.shared.adbService       // protocol surface
DependencyContainer.shared.deviceRepository // DeviceRepositoryProtocol
DependencyContainer.shared.menuViewModel    // MenuViewModel
```

`ADBService.executeADBCommand(arguments:completion:)` and `findScrcpyPath()` are
internal so feature extensions can reuse them. New ADB work belongs in an
extension file (`ADBService+Feature.swift`), not in `ADBService.swift`, unless
you are replacing an existing implementation.

## 5. Design rules (non-negotiable)

Mac-only, native, quiet. This is a menu bar utility, not a dashboard.

- **Menu, not windows.** New UI is `NSMenuItem` + SF Symbol at 16 pt, with
  `secondaryLabelColor` + `menuFont(ofSize: 11)` for section headers. Only use a
  window when the task genuinely needs a form (`NSAlert` for a single text field
  is enough).
- **Template images only** (`isTemplate = true`), so the menu bar stays correct in
  light, dark and tinted modes.
- **Opt-in for anything that reads private data.** Clipboard, notifications and
  file pushes are off until the user turns them on, per device.
- **Never block the main thread.** ADB calls go through `executeADBCommand`;
  UI updates hop to `DispatchQueue.main`.
- **Fail visibly but quietly.** Use `AlertPresenter.showWarning` for actionable
  errors, a disabled menu row for states ("Companion app not installed").
- **No telemetry, no network egress** other than ADB itself.

## 6. Build

The Xcode project uses filesystem-synchronized groups, so new files under
`macos/AndroLaunch/` are picked up automatically — never edit `project.pbxproj`.

```bash
xcodebuild -project macos/AndroLaunch.xcodeproj -scheme AndroLaunch \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/dd-<yourname> build
```

A clean build of the app target is the definition of "compiles".

## 7. File ownership

| Area | Owner | Files |
| --- | --- | --- |
| Identity + preferences | identity | `DeviceRepository.swift`, `DeviceRepositoryProtocol.swift` |
| Clipboard | clipboard | `ADBService.swift` clipboard region, `ClipboardMenuSection.swift`, `StatusMenuController+ConfigMenu.swift` clipboard block |
| Connection | connection | `ADBService.swift` listing/connect region, `AppDelegate.swift`, `ConnectionMenuSection.swift`, `Data/Services/Connection/` |
| Transfers | transfer | `FileExplorer*`, `TransferMenuSection.swift`, `Info.plist`, `Data/Services/Transfer/` |
| Notifications | notifications | `NotificationMenuSection.swift`, `PreferencesView.swift`, `Data/Services/Notifications/`, `ADBService+Notifications.swift` |

Shared files (`StatusMenuController.swift`, `MenuViewModel.swift`,
`MenuSectionRegistry.swift`, the models in `Domain/`) belong to the Lead.
