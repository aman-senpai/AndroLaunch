# Feature expansion plan — dashboard, storage, mirror controls, Finder access

This milestone adds the workflows shown in the new reference screenshots to the
open **AndroLaunch** app. Every capability ships in the same app.

## 1. What the screenshots ask for

| Reference | Capability to build | Approach |
| --- | --- | --- |
| Narrow device window with tabs, device name, Frame Mode toggle, app search and app grid | **Device Dashboard** window | New compact window with Apps / Notifications / Storage / Device / Settings tabs. Uses the existing app catalog, companion and device feed. |
| Notification groups, “Sync to Mac”, Open/Stop, hidden group | **Dashboard notifications** | Group by app, show visible/hidden sections from `NotificationMirror`, per-device sync toggle, open app on phone, dismiss, reply where supported. |
| App grid with search and “Copy to Android” result | **Dashboard apps + text actions** | Reuse app catalog; when the query is text/URL, offer “Copy to Android” through the companion clipboard. |
| Install helper card | **Companion install card** | Show when the companion is missing; install the bundled APK over ADB from the dashboard. |
| Mirror window with side controls (Audio Forwarding, Pin, Screen Off, Clipboard, Screenshot, Record, Mac Keyboard) and nav buttons | **Mirror Controls panel** | Floating panel attached to the selected device; toggle scrcpy options by restarting the mirror with the new flags; nav/screenshot/clipboard via ADB. |
| File management card with storage use, Camera / SD Card / Root, Open and Mount | **File management + Finder access** | Storage card in the dashboard and a dedicated storage detail window; “Open”/“Mount” materializes a local Finder mirror of the selected phone folders. |
| Storage analytics donut, category legend, per-folder breakdown | **Storage Analytics** | New `StorageService` breakdown by category and volume (internal + SD), plus folder drill-down. |
| Android 14 Frame Mode tooltip | **Requirement disclosure** | Tooltip/popover explaining Frame Mode needs Android 14; fallback remains visible. |
| System Settings camera extension | **Camera extension status** | Existing honest status remains: a signed CMIO extension is required; in-app preview is the working surface. |
| System Settings File Provider / Quick Look / Sharing extensions | **Finder and share surfaces** | Finder mirror + Finder Service + “Copy to Android” Services item ship in this build. Signed extension targets are documented as separate distribution work. |

## 2. New architecture

```
Presentation/Dashboard/
  DeviceDashboardWindowController.swift   window shell (380×760)
  DeviceDashboardView.swift               header, tabs, content
  DashboardAppsView.swift                 search, grid, Copy to Android, install helper
  DashboardNotificationsView.swift        grouped notifications, sync
  DashboardStorageView.swift              storage summary + file management card
  DashboardDeviceView.swift               device details
  StorageAnalyticsWindowController.swift
  StorageAnalyticsView.swift              donut charts, legend, folder drill-down
Presentation/Overlays/
  MirrorControlsPanel.swift               floating controls panel
Data/Services/
  Finder/FinderMirrorService.swift        local Finder mirror (pull + reveal)
  Mirror/MirrorControlsController.swift   state + actions for the panel
  Share/CopyToAndroidService.swift        text/URL → phone clipboard
  Phone/StorageService.swift              expanded categories, volumes, folders
```

### Contracts

```swift
enum DeviceDashboardTab { case apps, notifications, storage, device, settings }

final class DeviceDashboardWindowController {
    static let shared
    func show(deviceID: String?, tab: DeviceDashboardTab)
}

struct DeviceDashboardView: View {
    init(deviceID: String?, initialTab: DeviceDashboardTab)
}

final class StorageAnalyticsWindowController {
    static let shared
    func show(deviceID: String)
}

struct StorageAnalyticsView: View { init(deviceID: String) }

final class FinderMirrorService: ObservableObject {
    static let shared
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing: Bool
    func open(deviceID: String, scope: FinderMirrorScope)   // materialize + reveal
    func refresh(deviceID: String, scope: FinderMirrorScope)
}

enum FinderMirrorScope { case camera, sdCard, root, userFiles }

final class MirrorControlsController: ObservableObject {
    static let shared
    func show(deviceID: String); func hide()
}
```

## 3. Data and privacy

- Storage reads use `df`, `du`, `dumpsys diskstats` and `find` over the existing ADB
  authorization. Outputs are summarized; file names stay local.
- Finder mirrors are written under
  `~/Library/Application Support/AndroLaunch/Finder/<device>/` and are never
  uploaded anywhere.
- Notifications keep the existing privacy filter; the dashboard uses the same
  grouped records and never logs text.
- MCP and clipboard payloads remain unchanged.

## 4. Implementation order

1. Shared stubs, menu routes, and the plan (Lead).
2. Device Dashboard (dashboard agent).
3. Storage service + analytics + file management + Finder mirror (storage agent).
4. Mirror controls panel + ADB/scrcpy restart plumbing (mirror agent).
5. “Copy to Android” Services menu + URL/deep-link action (Lead).
6. Integration, snapshots, builds, tests, final review (Lead).

## 5. Verification

- Debug and Release builds.
- Pure-logic tests for storage parsing, group parsing, Finder mirror path safety
  and mirror option mapping.
- Rendered snapshots for the dashboard tabs, storage analytics and mirror controls.
- App/MCP smoke test.
- Device-dependent paths (live ADB) verified by code and tests unless a phone is
  attached.

## 6. Known constraints

- A system **File Provider** extension, **Quick Look** extension, **Share**
  extension and **CMIO camera** extension each require a separately signed app
  extension target and distribution identity. This milestone ships working Finder
  mirror access, the Finder Service and a Services “Copy to Android” item instead;
  the signed extension targets remain a packaging task.
- Frame Mode virtual displays require Android 14+; older devices mirror the main
  display with an explanation.
- Mirror option changes restart the active scrcpy session; the panel names this
  behavior instead of pretending the stream mutates in place.


## 7. Implementation status

| Surface | Status |
| --- | --- |
| Device Dashboard (Apps / Notifications / Storage / Device / Settings) | Implemented; snapshot previews for every tab. |
| App search, Copy to Android, companion install helper | Implemented. |
| Notification Showing/Hidden groups + Sync to Mac | Implemented on top of `NotificationMirror`. |
| Storage Analytics (internal + SD donuts, categories, folder drill-down, largest media) | Implemented with partial-value disclosure. |
| File management card (Camera / SD Card / Root, Open/Mount, capacity) | Implemented; Finder mirror, not a system File Provider mount. |
| Finder mirror + `~/AndroLaunch` sidebar link | Implemented (`adb pull`, bounded, safe paths). |
| Mirror Controls (audio, pin, screen off, clipboard, screenshot, record, keyboard, frame, nav) | Implemented; live-tested against an attached Android 12 device. |
| Copy to Android (Services + dashboard search) | Implemented. |
| Signed File Provider / Quick Look / Share / CMIO camera extensions | Not shipped; require separately signed extension targets. |
| Frame Mode Android-14 requirement disclosure | Tooltip/popover + disabled fallback. |
| Menu-bar Liquid Glass dashboard (single surface) | Implemented; light/dark snapshots. Legacy NSMenu removed. |
| Real launcher app icons via companion v4 | Implemented; disk cache + SF fallback. |
| Hidden scrollbars across dashboard/settings/storage | Implemented. |

Verification: macOS Debug + Release builds succeed; `./scripts/test-macos-logic.sh`
reports 1011 pure-logic checks; Android companion builds; the snapshot renderer
produces 19 images covering every new surface; app and MCP launch smoke tests pass.

## 8. Menu-bar Liquid Glass dashboard (follow-up)

- Left-clicking the status item opens a floating 380×760 glass dashboard instead
  of the classic NSMenu list. It hosts the same
  Apps / Notifications / Storage / Device / Settings dashboard plus a Tools sheet
  for Mirror Controls, Storage Analytics, Finder Mirror, Copy Clipboard to
  Android.
- **Liquid Glass:** a behind-window `NSVisualEffectView` backdrop plus SwiftUI
  `glassEffect(.regular, in:)` on macOS 26+ (thin-material fallback below), with
  dedicated glass text tokens for light and dark. Light and dark snapshots were
  rendered and reviewed; the panel follows live appearance changes.
- **No scrollbars:** every SwiftUI scroll surface (dashboard, settings,
  storage, package inspector) hides indicators while keeping wheel/trackpad
  scrolling.
- **Real app icons:** companion `v4` adds the additive `app-icons` command
  (`{"c":"app-icons","icons":[{"package","label","pngBase64"}]}`) with 96×96
  launcher PNGs; the Mac batch-loads and caches them in
  `~/Library/Application Support/AndroLaunch/AppIcons/<device>/<package>.png`.
  Older companions / no companion fall back to `AppIconMapper` symbols. The
  multi-chunk companion response path was fixed so batches larger than 64 KB are
  read to their newline terminator.

Status: implemented, live-verified against the attached Android 12 phone
(real icons, panel window, screenshot/record paths) and covered by 1011 pure-logic
checks plus 14 light/dark panel snapshots.


## 9. Monochrome + inline-settings redesign (follow-up)

- **Monochrome:** the purple/magenta accent is gone. The palette is charcoal /
  silver / white, with semantic green/amber/red reserved for status dots. Every
  panel surface, button, switch, selected tab, hover highlight and icon is
  neutral.
- **Tabs:** the five tabs are a compact centred pill row (collapsed 40 pt,
  selected/hovered 64 pt) with a spring label expansion and an interactive
  Liquid Glass highlight on hover; Reduce Motion disables the expansion.
- **Inline Settings:** the Settings tab now renders the complete Settings surface
  in place (Fusion, Hardware, AI/MCP, Devices, Notifications, Storage, About) —
  no “Open full Settings” row and no Hub window.
- **Notifications:** “Showing N”/“Hidden N” groups, real app icons, sender and
  subject shaping, group counts, expand chevrons, and Delete / Mark as read /
  Reply / Open actions backed by companion v5.
- **Storage permission:** when the companion reports no folder-tree access, the
  Storage tab shows an **Allow storage access** card that opens Android’s
  All-files settings and re-reads the grant.
- **Device tab / Tools:** Mirror, camera (back/front), Frame Mode, Screenshot,
  Ring, Storage, Wi-Fi QR/pairing/IP/companion, AVD manager + count, saved
  commands + manager, Trackpad, Glance, camera extension and the legacy right-click
  menu are all reachable from the panel.
- **Hub removed:** there is no Hub window, Hub menu item or Hub button. The
  menu-bar panel is the one main surface; onboarding, Dock reopen, Trackpad and
  Glance all route to it.
- **Frame Mode:** every user-facing legacy “Meld Mode” string is now “Frame Mode”.
- **Companion v5:** storage access + `notif.action`; APK hash
  `300690754b707ecc65afc709b487a8623211c9c5539377696438b9af5eed383a`.
- Verified by 1011 pure-logic checks, 16 light/dark panel snapshots and live phone
  checks for storage permission and Mark-as-read.

## 10. Local-signed camera extension

- Added a real CMIO system-extension target (`macos/CameraExtension/`) with a
  1280×720@30 test-pattern stream, local self-signed signing
  (`scripts/bootstrap-local-signing.sh`), build/embed/sign
  (`scripts/build-camera-extension.sh`), install
  (`scripts/install-local-camera-extension.sh`), and diagnostics.
- The host carries `com.apple.developer.system-extension.install` only in the
  locally-signed install; normal Xcode builds stay ad-hoc and show Install/Not
  available honestly.
- Self-signed activation requires the SIP developer lane and
  `systemextensionsctl developer on`; see `docs/camera-extension-local-signing.md`.

## 11. Panel-only stability/polish pass

- **No footer:** the bottom status strip was removed; context lives in the
  header and refresh moved into Tools.
- **Header:** the rounded menu-bar icon is reused inside the expanded panel and
  the “Device Dashboard” subtitle was removed.
- **Notifications actually populate:** per-device notifications default on;
  polling is decoupled from the macOS Notification Center permission prompt;
  the companion is given a short readiness window before the dumpsys fallback;
  mail is no longer hidden by default; and system security/connectivity rows
  stay visible. Live groups now include AndroLaunch Comp, Gmail and Security.
- **Multi-device Device tab:** every connected device is listed; tapping a row
  selects it and expands its model/Android/API/battery details.
- **Inline feature pages:** Wi-Fi pairing, saved commands, AVDs and Mirror
  Controls open inside the panel (back/close header), not in NSWindows. Storage
  Analytics expands under the Storage card. The full Settings surface is inline.
- **Companion defaults:** after ADB install the app now grants notification,
  media/storage and notification-listener access (and All-files via appops);
  phone/call permissions remain opt-in. A Bluetooth quick action can enable the
  phone radio from Tools.
- **Crash fix:** `CompanionClient.port(for:)` no longer calls `queue.sync` while
  already on the companion queue; this was the EXC_BREAKPOINT crash. App-icon
  batch responses also read every chunk to the newline terminator.
- **Applications fetch:** single-flight guard prevents concurrent
  `scrcpy --list-apps` processes from racing and returning no apps.
- Verified by **1011** pure-logic checks, 16 light/dark panel snapshots, live
  notifications, live companion permission grants, and a Release launch.
