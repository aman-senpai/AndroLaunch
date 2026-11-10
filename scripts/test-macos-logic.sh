#!/bin/bash
# Compiles the Foundation-only continuity layer together with its tests and runs them.
# There is no XCTest target in macos/AndroLaunch.xcodeproj, so these are plain executables.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/macos/AndroLaunch"
OUT="${TMPDIR:-/tmp}/androlaunch-core-logic-tests"

swiftc -O \
  "$SRC/Core/Constants/AppConstants.swift" \
  "$SRC/Domain/Models/AndroidDevice.swift" \
  "$SRC/Domain/Models/AndroidDevice+Identity.swift" \
  "$SRC/Domain/Models/DeviceEndpoint.swift" \
  "$SRC/Data/Persistence/DeviceScopedPreferences.swift" \
  "$SRC/Data/Persistence/EndpointStore.swift" \
  "$SRC/Data/Services/Notifications/NotificationDumpParser.swift" \
  "$SRC/Data/Services/Notifications/NotificationPrivacy.swift" \
  "$SRC/Data/Services/Phone/PhoneProtocolModels.swift" \
  "$SRC/Data/Services/Connection/WirelessConnectionLogic.swift" \
  "$SRC/Data/Services/Packages/PackageFormat.swift" \
  "$SRC/Data/Services/Packages/PackageInspectionEngine.swift" \
  "$SRC/Data/Services/Windows/AppLaunchMode.swift" \
  "$SRC/Data/Services/Shortcuts/AppDeepLink.swift" \
  "$SRC/Data/Services/Shortcuts/ShortcutNaming.swift" \
  "$SRC/Data/Services/Companion/CompanionAuth.swift" \
  "$SRC/Data/Services/AppIcons/AppIconModels.swift" \
  "$SRC/Data/Services/StorageAccess/StorageAccessModels.swift" \
  "$SRC/Presentation/MenuBarPanel/MenuBarPanelGeometry.swift" \
  "$SRC/Presentation/Dashboard/NotificationGroupingLogic.swift" \
  "$SRC/Presentation/Dashboard/DeviceDashboardLogic.swift" \
  "$SRC/Data/Services/Mirror/MirrorOptions.swift" \
  "$SRC/Data/Services/Phone/StorageAnalyticsModels.swift" \
  "$SRC/Data/Services/Finder/FinderMirrorModels.swift" \
  "$SRC/Data/Services/MCP/MCPProtocol.swift" \
  "$SRC/Data/Services/MCP/MCPToolCatalog.swift" \
  "$SRC/Data/Services/MCP/MCPToolPlanner.swift" \
  "$SRC/Data/Services/MCP/MCPActivityLog.swift" \
  "$SRC/Data/Services/MCP/MCPADB.swift" \
  "$SRC/Data/Services/MCP/MCPToolExecutor.swift" \
  "$SRC/Data/Services/Trackpad/TrackpadModels.swift" \
  "$SRC/Data/Services/Widgets/GlanceModels.swift" \
  "$SRC/Data/Services/Camera/CameraModels.swift" \
  "$ROOT/macos/Tests/CoreLogicTests/main.swift" \
  "$ROOT/macos/Tests/CoreLogicTests/NotificationParserTests.swift" \
  "$ROOT/macos/Tests/CoreLogicTests/SDKToolsDetectionTests.swift" \
  "$ROOT/macos/Tests/CoreLogicTests/PhoneLogicTests.swift" \
  "$ROOT/macos/Tests/CoreLogicTests/ConnectionLogicTests.swift" \
  "$ROOT/macos/Tests/CoreLogicTests/AppsLogicTests.swift" \
  "$ROOT/macos/Tests/CoreLogicTests/MCPLogicTests.swift" \
  "$ROOT/macos/Tests/CoreLogicTests/DashboardLogicTests.swift" \
  "$ROOT/macos/Tests/CoreLogicTests/MirrorControlsLogicTests.swift" \
  "$ROOT/macos/Tests/CoreLogicTests/StorageLogicTests.swift" \
  "$ROOT/macos/Tests/CoreLogicTests/AppIconLogicTests.swift" \
  "$ROOT/macos/Tests/CoreLogicTests/StoragePermissionLogicTests.swift" \
  "$ROOT/macos/Tests/CoreLogicTests/MenuBarPanelLogicTests.swift" \
  "$ROOT/macos/Tests/CoreLogicTests/NotificationGroupingLogicTests.swift" \
  "$ROOT/macos/Tests/CoreLogicTests/PlatformLogicTests.swift" \
  -o "$OUT"

"$OUT"
