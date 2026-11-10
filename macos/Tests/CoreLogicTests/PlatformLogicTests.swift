//
//  PlatformLogicTests.swift
//  CoreLogicTests
//
//  Plain-executable regression cover for the platform-extras surfaces:
//  trackpad gesture/scroll math and persistence, camera extension detection and
//  zoom bounds, and the Glance board's storage/quick-app logic.
//
//  Compile with the Foundation-only platform models (no AppKit, no ADB):
//    TrackpadModels.swift, GlanceModels.swift, CameraModels.swift,
//    PlatformLogicTests.swift, main.swift
//

import Foundation

func runPlatformLogicTests() {
    runTrackpadGestureTests()
    runTrackpadScrollTests()
    runTrackpadPreferenceTests()
    runCameraTests()
    runGlanceStorageTests()
    runGlanceQuickAppTests()
    runGlanceStateTests()
}

// MARK: - Trackpad gestures

private func runTrackpadGestureTests() {
    suite("TrackpadGestureClassifier") {
        let classifier = TrackpadGestureClassifier()
        let size = TrackpadSize(width: 300, height: 100)

        let back = classifier.classify(
            start: TrackpadPoint(x: 20, y: 50),
            end: TrackpadPoint(x: 160, y: 55),
            size: size)
        expect(back == .back, "left-edge swipe right is Back")

        let middleSwipe = classifier.classify(
            start: TrackpadPoint(x: 150, y: 50),
            end: TrackpadPoint(x: 290, y: 52),
            size: size)
        expect(middleSwipe == nil, "swiping right away from the edge is ignored")

        let forward = classifier.classify(
            start: TrackpadPoint(x: 280, y: 50),
            end: TrackpadPoint(x: 100, y: 50),
            size: size)
        expect(forward == nil, "forward swipe is not mapped to an Android gesture")

        let recents = classifier.classify(
            start: TrackpadPoint(x: 150, y: 85),
            end: TrackpadPoint(x: 152, y: 15),
            size: size)
        expect(recents == .recents, "swipe up is Recents")

        let notifications = classifier.classify(
            start: TrackpadPoint(x: 150, y: 10),
            end: TrackpadPoint(x: 150, y: 80),
            size: size)
        expect(notifications == .notifications, "swipe down from the top is Notifications")

        let middleDown = classifier.classify(
            start: TrackpadPoint(x: 150, y: 55),
            end: TrackpadPoint(x: 150, y: 98),
            size: size)
        expect(middleDown == nil, "swipe down in the middle is ignored")

        let tinyDrag = classifier.classify(
            start: TrackpadPoint(x: 20, y: 50),
            end: TrackpadPoint(x: 32, y: 51),
            size: size)
        expect(tinyDrag == nil, "a small drag never changes Android state")

        let zeroSize = classifier.classify(
            start: TrackpadPoint(x: 0, y: 0),
            end: TrackpadPoint(x: 50, y: 50),
            size: TrackpadSize(width: 0, height: 0))
        expect(zeroSize == nil, "zero-sized surfaces produce no gesture")

        // Sensitivity lowers the travel threshold, so a borderline drag can count.
        let shortDragStart = TrackpadPoint(x: 20, y: 50)
        let shortDragEnd = TrackpadPoint(x: 80, y: 50)
        let lowSensitivity = classifier.classify(
            start: shortDragStart, end: shortDragEnd, size: size, sensitivity: 0.1)
        let highSensitivity = classifier.classify(
            start: shortDragStart, end: shortDragEnd, size: size, sensitivity: 1.0)
        expect(lowSensitivity == nil, "low sensitivity needs more travel")
        expect(highSensitivity == .back, "high sensitivity accepts a shorter swipe")
    }

    suite("TrackpadGestureMapping") {
        expect(TrackpadGestureMapping.commands(for: .back) == [.keyEvent(4)], "Back is KEYCODE_BACK")
        expect(TrackpadGestureMapping.commands(for: .home) == [.keyEvent(3)], "Home is KEYCODE_HOME")
        expect(
            TrackpadGestureMapping.commands(for: .recents) == [.keyEvent(187)],
            "Recents is KEYCODE_APP_SWITCH")
        expect(
            TrackpadGestureMapping.commands(for: .notifications)
                == [.shell("cmd statusbar expand-notifications")],
            "Notifications opens the shade through the statusbar service")

        let scrollCommands = TrackpadGestureMapping.commands(
            for: .scrollUp, screen: TrackpadScreenSize(width: 1080, height: 2400))
        guard case .shell(let swipe)? = scrollCommands.first else {
            expect(false, "scroll gesture produces a swipe shell command")
            return
        }
        expect(swipe.contains("input swipe"), "scroll maps to an input swipe")
        expect(swipe.contains("swipe 540"), "swipe starts at the screen's horizontal center")

        expect(TrackpadCommand.keyEvent(4).arguments == ["input", "keyevent", "4"], "keyevent argv")
        expect(
            TrackpadCommand.shell("cmd statusbar expand-notifications").arguments
                == ["cmd", "statusbar", "expand-notifications"],
            "shell argv splits without user text")
    }

    suite("TrackpadScreenSize.parse") {
        let physical = TrackpadScreenSize.parse(
            wmSize: "Physical size: 1080x2400\n")
        expect(physical == TrackpadScreenSize(width: 1080, height: 2400), "physical size parsed")

        let override = TrackpadScreenSize.parse(
            wmSize: "Physical size: 1080x2400\nOverride size: 720x1600\n")
        expect(
            override == TrackpadScreenSize(width: 720, height: 1600),
            "override size wins over physical")

        expect(TrackpadScreenSize.parse(wmSize: "error: device offline") == nil, "garbage rejected")
        expect(TrackpadScreenSize.parse(wmSize: "Physical size: 0x2400") == nil, "zero rejected")
    }
}

// MARK: - Trackpad scrolling

private func runTrackpadScrollTests() {
    suite("TrackpadScrollAccumulator") {
        var accumulator = TrackpadScrollAccumulator()
        expect(
            accumulator.add(deltaY: 5, naturalScrolling: true, sensitivity: 0.6) == nil,
            "small deltas accumulate instead of firing")
        expect(
            accumulator.add(deltaY: 40, naturalScrolling: true, sensitivity: 0.6)?.direction
                == .contentUp,
            "positive delta scrolls content up")
        expect(accumulator.residual == 0, "residual resets after a swipe")

        var inverted = TrackpadScrollAccumulator()
        expect(
            inverted.add(deltaY: 40, naturalScrolling: false, sensitivity: 0.6)?.direction
                == .contentDown,
            "non-natural scrolling inverts direction")

        var big = TrackpadScrollAccumulator()
        let swipe = big.add(deltaY: 4000, naturalScrolling: true, sensitivity: 1.0)
        expect(swipe != nil, "large delta fires immediately")
        expect((swipe?.distance ?? 0) <= 900, "distance is clamped")
        expect((swipe?.distance ?? 0) >= 80, "distance has a usable minimum")

        expect(
            TrackpadScrollAccumulator.stepDistance(sensitivity: 1.0)
                < TrackpadScrollAccumulator.stepDistance(sensitivity: 0.2),
            "higher sensitivity needs less travel")
        expect(
            TrackpadScrollAccumulator.clampSensitivity(9) == 1
                && TrackpadScrollAccumulator.clampSensitivity(0) == 0.1,
            "sensitivity is bounded")
        expect(
            TrackpadScrollAccumulator.clampSensitivity(.nan) == 0.6,
            "non-finite sensitivity falls back")
    }

    suite("TrackpadScrollAccumulator.swipeArguments") {
        let screen = TrackpadScreenSize(width: 1080, height: 2400)
        let up = TrackpadScrollAccumulator.swipeArguments(
            direction: .contentUp, distance: 400, screen: screen)
        expect(up.count == 7, "swipe argv has seven fields")
        expect(up[0] == "input" && up[1] == "swipe", "starts with input swipe")
        let x = Int(up[2]) ?? -1
        let startY = Int(up[3]) ?? -1
        let endY = Int(up[5]) ?? -1
        expect(x == 540, "swipe is horizontally centered")
        expect(endY < startY, "content up swipes the finger upward")
        expect(startY <= 2400 && endY >= 0, "swipe stays inside the screen")

        let down = TrackpadScrollAccumulator.swipeArguments(
            direction: .contentDown, distance: 400, screen: screen)
        expect((Int(down[5]) ?? 0) > (Int(down[3]) ?? 0), "content down swipes downward")
    }
}

// MARK: - Trackpad preferences

private func runTrackpadPreferenceTests() {
    suite("TrackpadPreferences persistence") {
        let defaults = freshDefaults("trackpad")
        let initial = TrackpadPreferences.load(from: defaults)
        expect(
            initial.sensitivity == TrackpadPreferences.defaultSensitivity,
            "missing values use the default sensitivity")
        expect(initial.naturalScrolling, "natural scrolling defaults on")

        TrackpadPreferences(sensitivity: 0.9, naturalScrolling: false).save(to: defaults)
        let reloaded = TrackpadPreferences.load(from: defaults)
        expect(reloaded.sensitivity == 0.9, "sensitivity round-trips")
        expect(reloaded.naturalScrolling == false, "natural scrolling round-trips")

        defaults.set(7.0, forKey: TrackpadPreferences.Keys.sensitivity)
        expect(
            TrackpadPreferences.load(from: defaults).sensitivity == 1.0,
            "out-of-range stored sensitivity is clamped")
    }
}

// MARK: - Camera

private func runCameraTests() {
    suite("CameraZoom") {
        expect(CameraZoom.clamp(0.2) == CameraZoom.minimum, "zoom is floored")
        expect(CameraZoom.clamp(99) == CameraZoom.maximum, "zoom is capped")
        expect(CameraZoom.clamp(.nan) == CameraZoom.minimum, "non-finite zoom is safe")
        expect(CameraZoom.scrcpyValue(1.0) == nil, "no --camera-zoom at 1×")
        expect(CameraZoom.scrcpyValue(2.04) == 2.0, "zoom rounds to one decimal")
        expect(CameraZoom.label(1.5) == "1.5×", "zoom label")
        expect(CameraZoom.adjust(1.0, up: false) == CameraZoom.minimum, "zoom cannot go below 1×")
    }

    suite("CameraExtensionProbe") {
        let list = """
            1 extension(s)
            --- com.apple.system_extension.driver_extension
            enabled	active	teamID	bundleID (version)	name	[state]
            *	*	ABCDE12345	com.senpai.AndroLaunch.CameraExtension (1.0/1)	AndroLaunch Camera	[activated enabled]
            """
        expect(
            CameraExtensionProbe.extensionLabel(fromSystemExtensionList: list)
                == "com.senpai.AndroLaunch.CameraExtension",
            "a real AndroLaunch camera extension is detected by bundle id")

        let unrelated = """
            enabled	active	teamID	bundleID (version)	name	[state]
            *	*	ABCDE12345	com.apple.driver.Camera (1.0/1)	System Camera	[activated enabled]
            """
        expect(
            CameraExtensionProbe.extensionLabel(fromSystemExtensionList: unrelated) == nil,
            "Apple's camera extensions never count as AndroLaunch's")

        let androlaunchOnly = """
            *	*	ABCDE12345	com.senpai.AndroLaunch.Helper (1.0/1)	AndroLaunch Helper	[activated enabled]
            """
        expect(
            CameraExtensionProbe.extensionLabel(fromSystemExtensionList: androlaunchOnly) == nil,
            "a non-camera AndroLaunch extension is not a camera extension")

        expect(
            CameraExtensionProbe.extensionLabel(fromSystemExtensionList: "no extensions") == nil,
            "empty output means unknown, not installed")

        let emptyDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("androlaunch-no-ext-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: emptyDirectory, withIntermediateDirectories: true)
        expect(
            CameraExtensionProbe.bundledCameraExtensionName(in: [emptyDirectory]) == nil,
            "this build bundles no camera extension")
        try? FileManager.default.removeItem(at: emptyDirectory)
    }

    suite("CameraPreviewState honesty") {
        var state = CameraPreviewState()
        expect(!state.canPreview, "no device and no scrcpy means preview is unavailable")
        expect(
            state.statusSummary == "No device connected",
            "the header says there is no device")

        state.deviceID = "R58M12345"
        state.deviceName = "Pixel"
        state.isDeviceConnected = true
        expect(!state.canPreview, "a device alone is not enough without scrcpy")
        expect(
            state.statusSummary.contains("scrcpy"),
            "missing scrcpy is named in the status")

        state.isScrcpyAvailable = true
        expect(state.canPreview, "device plus scrcpy can preview")
        expect(state.primaryActionTitle == "Start preview", "primary action starts preview")
        state.isPreviewing = true
        expect(state.primaryActionTitle == "Stop preview", "primary action stops preview")
        expect(
            state.statusSummary.contains("Previewing"),
            "previewing state is stated in words")

        var front = CameraPreviewState()
        front.lens = .front
        expect(!front.torchAvailable, "the front lens has no torch")
        expect(front.torchSubtitle?.contains("back camera") == true, "torch limit is explained")

        expect(
            CameraExtensionStatus.unavailable("No signed camera extension is installed on this Mac.")
                .isInstalled == false,
            "unavailable extension is never reported as installed")
        expect(
            CameraExtensionStatus.unavailable("reason").detail.contains("signed"),
            "the extension detail explains the signing requirement")
        let installable = CameraExtensionStatus.installable("AndroLaunch Camera")
        expect(installable.canInstall, "a bundled local-signed extension is installable")
        expect(!installable.isInstalled, "installable is not active yet")
        expect(installable.badgeText == "Install", "installable badge offers install")
        expect(
            installable.detail.contains("System Settings"),
            "installable explains where to approve the extension")
    }
}

// MARK: - Glance storage

private func runGlanceStorageTests() {
    suite("GlanceStorageProbe.parseDataPartition") {
        let output = """
            Filesystem     1K-blocks     Used Available Use% Mounted on
            /dev/block/dm-7 115343360 78643200  36700160  69% /data
            """
        let usage = GlanceStorageProbe.parseDataPartition(dfOutput: output)
        expect(usage != nil, "a /data row parses")
        expect(usage?.totalBytes == 115343360 * 1024, "total is converted from KiB")
        expect(usage?.usedBytes == 78643200 * 1024, "used is converted from KiB")
        expect(usage?.freeBytes == 36700160 * 1024, "free is converted from KiB")
        expect(
            abs((usage?.usedFraction ?? 0) - 0.6819) < 0.002,
            "used fraction is computed")

        let noData = """
            Filesystem     1K-blocks     Used Available Use% Mounted on
            /dev/block/dm-1  1048576   524288    524288  50% /system
            """
        expect(
            GlanceStorageProbe.parseDataPartition(dfOutput: noData) == nil,
            "a df without /data is not guessed")

        expect(
            GlanceStorageProbe.parseDataPartition(dfOutput: "error: closed") == nil,
            "an adb error produces no storage usage")

        expect(
            GlanceStorageProbe.parseDataPartition(dfOutput: "/data 0 0 0 0% /data") == nil,
            "zero totals are rejected")
    }

    suite("GlanceStorageProbe.formatBytes") {
        expect(GlanceStorageProbe.formatBytes(0) == "0 GB", "zero bytes")
        expect(GlanceStorageProbe.formatBytes(174_000_000_000) == "174 GB", "gigabytes")
        expect(GlanceStorageProbe.formatBytes(2_500_000_000) == "2.5 GB" || GlanceStorageProbe.formatBytes(2_500_000_000) == "2 GB", "gigabyte rounding")
        expect(GlanceStorageProbe.formatBytes(120_000_000) == "120 MB", "megabytes")
        expect(GlanceStorageProbe.formatBytes(2_000) == "2 KB", "kilobytes")
    }

    suite("GlanceTransport") {
        expect(GlanceTransport.classify(deviceID: "R58M12345AB") == .usb, "serial is USB")
        expect(GlanceTransport.classify(deviceID: "192.168.1.5:5555") == .wireless, "LAN is Wi-Fi")
        expect(
            GlanceTransport.classify(deviceID: "adb-123-xyz._adb-tls-connect._tcp") == .wireless,
            "Bonjour is Wi-Fi")
        expect(GlanceTransport.classify(deviceID: "emulator-5554") == .usb, "emulator is USB")
    }
}

// MARK: - Glance quick apps

private func runGlanceQuickAppTests() {
    let apps = (1...12).map { index in
        GlanceAppShortcut(
            packageName: "app.\(index)", name: "App \(index)", iconName: "app")
    }

    suite("GlanceQuickApps") {
        expect(GlanceQuickApps.limit == 8, "the grid is 4 × 2")

        let ordered = GlanceQuickApps.ordered(apps: apps, pinned: ["app.5", "app.2"])
        expect(ordered.count == 8, "the grid is capped")
        expect(ordered.first?.packageName == "app.5", "most recent pin comes first")
        expect(ordered[1].packageName == "app.2", "second pin follows")
        expect(
            ordered.dropFirst(2).first?.packageName == "app.1",
            "remaining apps keep catalog order")

        let deduplicated = GlanceQuickApps.ordered(
            apps: apps, pinned: ["app.3", "app.3", "missing.app"])
        expect(
            deduplicated.filter { $0.packageName == "app.3" }.count == 1,
            "pins are deduplicated")
        expect(!deduplicated.contains { $0.packageName == "missing.app" }, "unknown pins are dropped")

        expect(GlanceQuickApps.ordered(apps: [], pinned: ["app.1"]).isEmpty, "no apps, no shortcuts")

        let recents = GlanceQuickApps.recordingUse("app.9", pinned: ["app.1", "app.9"])
        expect(recents.first == "app.9", "using an app moves it to the front")
        expect(recents.filter { $0 == "app.9" }.count == 1, "no duplicate entries")
        expect(
            GlanceQuickApps.recordingUse(
                "app.3", pinned: (1...8).map { "app.\($0)" }).count == 8,
            "the recents list is capped at the grid size")
        expect(
            GlanceQuickApps.recordingUse("", pinned: ["app.1"]) == ["app.1"],
            "an empty package name is ignored")
    }

    suite("GlanceShortcutStore persistence") {
        let defaults = freshDefaults("glance")
        let store = GlanceShortcutStore(defaults: defaults)
        expect(store.pinned.isEmpty, "starts empty")

        store.recordUse("com.whatsapp")
        store.recordUse("com.spotify.music")
        let reopened = GlanceShortcutStore(defaults: defaults)
        expect(
            reopened.pinned == ["com.spotify.music", "com.whatsapp"],
            "recent shortcuts persist in use order")

        store.recordUse("com.whatsapp")
        expect(
            GlanceShortcutStore(defaults: defaults).pinned.first == "com.whatsapp",
            "using an existing shortcut reorders it")

        store.reset()
        expect(store.pinned.isEmpty, "reset clears the shortcuts")
    }
}

// MARK: - Glance state

private func runGlanceStateTests() {
    suite("GlanceBoardState") {
        var state = GlanceBoardState()
        expect(state.statusText == "No device", "empty state names the missing device")
        expect(state.batteryText == "—", "no battery reads as a dash")
        expect(state.storageText == "—", "no storage reads as a dash")
        expect(state.quickAppsCaption.contains("appear"), "empty apps explain themselves")

        state.deviceID = "R58M12345"
        state.deviceName = "Pixel 9 Pro"
        state.isConnected = true
        state.transport = .usb
        state.batteryLevel = 82
        expect(state.statusText == "Connected", "connected is stated in words")
        expect(state.batteryText == "82%", "battery percentage")
        expect(state.chargingText == nil, "not charging means no pill")
        expect(state.batteryTone == "accent", "healthy battery is neutral")

        state.isCharging = true
        expect(state.chargingText == "Charging", "charging is stated in words")
        expect(state.batteryTone == "success", "charging is a success tone")

        state.isCharging = false
        state.batteryLevel = 12
        expect(state.batteryTone == "danger", "low battery is a danger tone")
        state.batteryLevel = 32
        expect(state.batteryTone == "warning", "near-low battery is a warning tone")

        state.storageSummary = "174 GB of 256 GB used"
        expect(state.storageText == "174 GB of 256 GB used", "storage summary is shown verbatim")
        state.storageSummary = nil
        state.isLoadingStorage = true
        expect(state.storageText.contains("Checking"), "loading storage is stated")
    }
}
