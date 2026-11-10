# AndroLaunch feature build notes

This document records how the macOS dashboard, the phone features and the Android
companion fit together. It is implementation documentation, not a changelog.

## Product surface

The menu bar is the primary surface. Left-click opens the dashboard, a
native window with three tabs:

| Tab | What it contains |
| --- | --- |
| **Devices** | Live USB rows, Wi-Fi QR / pairing-code / IP-address connection, companion installation and emulator access. |
| **Apps** | Phone app catalog, search, pinning, APK/APKS/APKM/XAPK inspection and installation, drag-to-send, Frame Mode windows, desktop shortcuts and Spotlight indexing. |
| **Settings** | Fusion mode, hardware support (camera, trackpad, Glance), Android Use (MCP), device/notification/clipboard preferences, storage and About. |

The menu bar contributes calls, media, ring, storage, clipboard and platform
sections through `MenuSectionProviding`; it never rebuilds itself from feature
files.

## Architecture

```
macos/AndroLaunch/
  App/                       AppMain, AppDelegate — lifecycle, deep links, MCP/stdin modes
  Presentation/Hub/
    DesignSystem/            HubTheme (palette/type/metrics) + HubComponents
    MenuBarPanel/            One Liquid Glass dashboard panel (only main surface)
    HubStore                 Shared device/app selection
    Devices/                 USB, Wi-Fi, companion, emulator surface
    Apps/                    App grid, package inspector, Meld windows
    Settings/                Settings sections and sheets
    Dashboard/               Device Dashboard, storage analytics, file management
    HubSnapshotRenderer      DEBUG ImageRenderer snapshots
  Data/Services/
    Connection/              Wireless pairing / connect state
    Companion/               CompanionClient + per-install auth token
    Phone/                   Calls, media, ring, storage, image clipboard
    Notifications/           Mirror, categories, privacy filter, feature alerts
    Packages/                Package format detection and inspection
    Windows/                 Per-app window registry
    Shortcuts/               Desktop shortcuts + CoreSpotlight
    Camera/ Trackpad/        Camera preview and gesture panel
    Widgets/                 Glance desktop board
    MCP/                     Local stdio MCP server, tool catalog, activity log
    Finder/                  Finder mirror (pull + reveal, bounded)
    Mirror/                  Mirror controls state and scrcpy options
    AppIcons/                Real launcher icon cache and batching
    MenuBarPanel/            Liquid Glass dashboard panel and geometry
  Presentation/Overlays/     Call banner, trackpad panel, Glance panel
  Presentation/MenuBar/      Existing menu + feature sections
  android/app/               AndroLaunch Comp (protocol v3)
```

- **Shared state:** `HubStore` owns the device feed, selected phone, app catalog
  and current tab. Feature services are separate `ObservableObject` singletons so
  they can be probed and tested in isolation.
- **Menu contributions:** one `MenuSectionRegistry`; each section owns retained
  `NSMenuItem`s and updates them in place. `rebuildMenu` detaches retained items
  before re-inserting them (AppKit rejects an item that still belongs to another
  menu).
- **Wire protocol:** line-based, base64 arguments. v3 adds notification actions
  and reply, media transport, ring, storage information and image clipboard.
  Unknown commands return an error without closing the connection.
- **Companion auth:** the Mac stores a per-install token, passes it as a
  foreground-service extra, and includes it in the request id
  (`t.<token>.<random>`). Older companions echo the id; newer ones validate it.
- **Local only:** no account, no cloud, no telemetry. The MCP server is stdio-only.

## Build and verify

```bash
./scripts/build-macos.sh Debug
./scripts/build-macos.sh Release
./scripts/test-macos-logic.sh        # 1011 pure-logic checks
cd android && ./build.sh             # protocol v3 APK
./scripts/render-hub-snapshots.sh    # surface PNGs in build/hub-snapshots
./scripts/verify-milestone.sh        # all of the above + app/MCP smoke
```

The app target uses filesystem-synchronized groups, so new files under
`macos/AndroLaunch/` are picked up automatically. Do not edit `project.pbxproj`.

## Honest limits

- No relay cloud: remote use means a user-managed LAN/VPN `adb connect` endpoint.
- Cellular call audio stays on the phone; there is no public macOS API for it.
- This unsigned build does not include a signed CMIO camera extension or a
  WidgetKit extension. The in-app camera preview and the Glance desktop board are
  the working surfaces.
- Finder integration is the Finder Service / file browser today, not a FileProvider
  mount.
- Frame Mode virtual displays require Android 14+; Android 12–13 use a main-display
  mirror with a visible explanation.
- Device-dependent paths need a physical phone for end-to-end verification.
