//
//  MirrorControlsLogicTests.swift
//  CoreLogicTests
//
//  Deterministic cover for the Mirror Controls layer: option → scrcpy argument
//  mapping, keyboard/frame/navigation mapping and capture-file naming safety.
//
//  Compiled by scripts/test-macos-logic.sh together with the Foundation-only
//  `Data/Services/Mirror/MirrorOptions.swift`. Entry point: runMirrorControlsLogicTests().
//

import Foundation

func runMirrorControlsLogicTests() {
    mirrorArgumentMapping()
    mirrorKeyboardMapping()
    mirrorFrameMapping()
    mirrorNavigationMapping()
    mirrorCaptureNaming()
    mirrorOptionsState()
}

// MARK: - Arguments

private func mirrorArgumentMapping() {
    suite("MirrorScrcpyArguments.build") {
        let quality = MirrorQuality(
            maxSize: 1024, maxFPS: 60, bitRate: 8, orientation: "0", flexDisplay: false)
        let options = MirrorOptions(
            audioForwarding: false,
            alwaysOnTop: true,
            screenOff: true,
            borderless: true,
            clipboard: false,
            recording: false,
            macKeyboard: false)
        let args = MirrorScrcpyArguments.build(
            deviceID: "R58M12345AB",
            deviceName: "Pixel 9 Pro",
            quality: quality,
            options: options,
            recordPath: nil)

        expect(args.contains("--serial"), "serial flag present")
        expect(args.firstIndex(of: "--serial").map { args[$0 + 1] } == "R58M12345AB", "serial is the device id")
        expect(args.firstIndex(of: "--window-title").map { args[$0 + 1] } == "Pixel 9 Pro", "window title uses the device name")
        expect(args.contains("1024"), "-m keeps the quality preset")
        expect(args.firstIndex(of: "--max-fps").map { args[$0 + 1] } == "60", "FPS preset preserved")
        expect(args.firstIndex(of: "--video-bit-rate").map { args[$0 + 1] } == "8M", "bitrate preset preserved")
        expect(args.firstIndex(of: "--capture-orientation").map { args[$0 + 1] } == "0", "orientation preset preserved")
        expect(args.contains("--always-on-top"), "pin adds --always-on-top")
        expect(args.contains("--turn-screen-off"), "screen off adds --turn-screen-off")
        expect(args.contains("--window-borderless"), "without frame adds --window-borderless")
        expect(args.contains("--no-audio"), "audio forwarding off adds --no-audio")
        expect(args.contains("--no-clipboard-autosync"), "clipboard off adds --no-clipboard-autosync")
        expect(args.contains("--keyboard=disabled"), "Mac keyboard off maps to --keyboard=disabled")
        expect(!args.contains("--record"), "no record path means no --record")

        let defaults = MirrorScrcpyArguments.build(
            deviceID: "R58M",
            deviceName: nil,
            quality: MirrorQuality(),
            options: MirrorOptions(
                audioForwarding: true, alwaysOnTop: false, screenOff: false,
                borderless: false, clipboard: true, recording: false, macKeyboard: true),
            recordPath: nil)
        expect(!defaults.contains("--no-audio"), "audio on does not add --no-audio")
        expect(!defaults.contains("--no-clipboard-autosync"), "clipboard on does not disable autosync")
        expect(!defaults.contains("--always-on-top"), "unpinned adds no always-on-top")
        expect(!defaults.contains("--turn-screen-off"), "screen-on adds no turn-screen-off")
        expect(!defaults.contains("--window-borderless"), "framed window adds no borderless")
        expect(defaults.contains("--keyboard=sdk"), "Mac keyboard on maps to --keyboard=sdk")
        expect(defaults.firstIndex(of: "--window-title").map { defaults[$0 + 1] } == "R58M", "falls back to device id for the title")

        let flex = MirrorScrcpyArguments.build(
            deviceID: "R58M",
            deviceName: "Pixel",
            quality: MirrorQuality(maxSize: 1024, flexDisplay: true),
            options: MirrorOptions(),
            recordPath: nil)
        expect(!flex.contains("1024"), "flex display skips the -m cap")

        let zeroQuality = MirrorScrcpyArguments.build(
            deviceID: "R58M",
            deviceName: "Pixel",
            quality: MirrorQuality(maxSize: 0, maxFPS: 0, bitRate: 0, orientation: "Auto"),
            options: MirrorOptions(),
            recordPath: nil)
        expect(!zeroQuality.contains("-m"), "zero max size is omitted")
        expect(!zeroQuality.contains("--max-fps"), "zero FPS is omitted")
        expect(!zeroQuality.contains("--video-bit-rate"), "zero bitrate is omitted")
        expect(!zeroQuality.contains("--capture-orientation"), "Auto orientation is omitted")

        let recording = MirrorScrcpyArguments.build(
            deviceID: "R58M",
            deviceName: "Pixel",
            quality: MirrorQuality(),
            options: MirrorOptions(),
            recordPath: "/Users/me/Movies/AndroLaunch-2026-11-06-211502.mp4")
        expect(recording.contains("--record"), "record path adds --record")
        expect(
            recording.firstIndex(of: "--record").map { recording[$0 + 1] }
                == "/Users/me/Movies/AndroLaunch-2026-11-06-211502.mp4",
            "record path value is passed through")

        let blankRecord = MirrorScrcpyArguments.build(
            deviceID: "R58M", deviceName: "Pixel", quality: MirrorQuality(),
            options: MirrorOptions(), recordPath: "   ")
        expect(!blankRecord.contains("--record"), "blank record path is ignored")

        expect(args.filter { $0 == "--serial" }.count == 1, "serial appears once")
    }
}

// MARK: - Keyboard

private func mirrorKeyboardMapping() {
    suite("MirrorKeyboardMode") {
        expect(MirrorKeyboardMode.fromMacKeyboard(true) == .sdk, "Mac keyboard on uses SDK injection")
        expect(MirrorKeyboardMode.fromMacKeyboard(false) == .disabled, "Mac keyboard off disables injection")
        expect(MirrorKeyboardMode.uhid.argument == "--keyboard=uhid", "UHID argument")
        expect(MirrorKeyboardMode.sdk.argument == "--keyboard=sdk", "SDK argument")
        expect(MirrorKeyboardMode.disabled.argument == "--keyboard=disabled", "disabled argument")
        expect(MirrorKeyboardMode.allCases.count == 3, "all three scrcpy keyboard modes are represented")
        expect(
            MirrorOptions(macKeyboard: false).keyboardMode == .disabled,
            "options expose the mapped keyboard mode")
    }
}

// MARK: - Frame

private func mirrorFrameMapping() {
    suite("MirrorFrameChoice") {
        expect(MirrorFrameChoice.withoutFrame.borderless, "Without Frame means borderless")
        expect(!MirrorFrameChoice.includeFrame.borderless, "Include Frame keeps the frame")
        expect(MirrorFrameChoice(borderless: true) == .withoutFrame, "borderless maps to Without Frame")
        expect(MirrorFrameChoice(borderless: false) == .includeFrame, "framed maps to Include Frame")
        expect(
            MirrorOptions(borderless: true).frameChoice == .withoutFrame,
            "options expose the mapped frame choice")
        expect(MirrorFrameChoice.withoutFrame.title == "Without Frame", "reference copy kept")
        expect(MirrorFrameChoice.includeFrame.title == "Include Frame", "reference copy kept")
    }
}

// MARK: - Navigation

private func mirrorNavigationMapping() {
    suite("MirrorNavKey") {
        expect(MirrorNavKey.back.keycode == 4, "Back is KEYCODE_BACK (4)")
        expect(MirrorNavKey.home.keycode == 3, "Home is KEYCODE_HOME (3)")
        expect(MirrorNavKey.recents.keycode == 187, "Recents is KEYCODE_APP_SWITCH (187)")
        expect(MirrorNavKey.allCases.count == 3, "all three navigation keys exist")
        expect(MirrorNavKey.allCases.allSatisfy { !$0.icon.isEmpty }, "every nav key has an icon")
        expect(MirrorNavKey.allCases.allSatisfy { !$0.title.isEmpty }, "every nav key has a label")
    }
}

// MARK: - Capture naming

private func mirrorCaptureNaming() {
    suite("MirrorCaptureNaming") {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 6
        components.hour = 21
        components.minute = 15
        components.second = 2
        components.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let utc = TimeZone(identifier: "UTC")!

        expect(
            MirrorCaptureNaming.timestamp(date, timeZone: utc) == "2026-11-06-211502",
            "timestamp is sortable and second-precise")
        expect(
            MirrorCaptureNaming.fileName(
                prefix: "AndroLaunch", date: date, fileExtension: "png",
                existingNames: [], timeZone: utc)
                == "AndroLaunch-2026-11-06-211502.png",
            "screenshot name is timestamped")
        expect(
            MirrorCaptureNaming.fileName(
                prefix: "AndroLaunch", date: date, fileExtension: "mp4",
                existingNames: [], timeZone: utc)
                == "AndroLaunch-2026-11-06-211502.mp4",
            "recording name is timestamped")

        expect(
            MirrorCaptureNaming.sanitizedPrefix("My Phone: 12/Pro") == "My-Phone-12-Pro",
            "unsafe path characters are removed from prefixes")
        expect(MirrorCaptureNaming.sanitizedPrefix("   ") == "AndroLaunch", "blank prefix falls back")
        expect(
            MirrorCaptureNaming.sanitizedPrefix(String(repeating: "A", count: 80)).count == 40,
            "prefix is bounded")
        expect(
            MirrorCaptureNaming.sanitizedExtension("../PNG") == "png",
            "extension is sanitised and lowercased")
        expect(
            MirrorCaptureNaming.sanitizedExtension("") == "dat",
            "empty extension falls back")

        let screenshotName = "AndroLaunch-2026-11-06-211502.png"
        expect(
            MirrorCaptureNaming.fileName(
                prefix: "AndroLaunch", date: date, fileExtension: "png",
                existingNames: [screenshotName], timeZone: utc)
                == "AndroLaunch-2026-11-06-211502-2.png",
            "existing capture gets a numeric suffix before the extension")
        expect(
            MirrorCaptureNaming.fileName(
                prefix: "AndroLaunch", date: date, fileExtension: "png",
                existingNames: [screenshotName, "AndroLaunch-2026-11-06-211502-2.png"],
                timeZone: utc)
                == "AndroLaunch-2026-11-06-211502-3.png",
            "suffix keeps counting")

        expect(
            MirrorCaptureNaming.displayPath(
                URL(fileURLWithPath: NSHomeDirectory() + "/Desktop/shot.png"))
                == "~/Desktop/shot.png",
            "home paths are abbreviated")
        expect(
            MirrorCaptureNaming.displayPath(URL(fileURLWithPath: "/Volumes/External/shot.png"))
                == "/Volumes/External/shot.png",
            "other paths stay absolute")
    }
}

// MARK: - Option state

private func mirrorOptionsState() {
    suite("MirrorOptions") {
        let options = MirrorOptions(
            audioForwarding: true, alwaysOnTop: true, screenOff: false,
            borderless: true, clipboard: false, recording: false, macKeyboard: true)
        let summary = options.summary
        expect(summary.contains("Audio on"), "summary names audio")
        expect(summary.contains("Clipboard off"), "summary names clipboard")
        expect(summary.contains("Pinned"), "summary names pin state")
        expect(summary.contains("Mac keyboard"), "summary names keyboard state")

        expect(
            options.differsFrom(
                MirrorOptions(
                    audioForwarding: true, alwaysOnTop: true, screenOff: false,
                    borderless: true, clipboard: false, recording: false,
                    macKeyboard: true)) == false,
            "identical options do not report a restart need")
        expect(
            options.differsFrom(
                MirrorOptions(
                    audioForwarding: true, alwaysOnTop: false, screenOff: false,
                    borderless: true, clipboard: false, recording: false,
                    macKeyboard: true)),
            "pin change requires a restart")
        expect(
            options.differsFrom(
                MirrorOptions(
                    audioForwarding: true, alwaysOnTop: true, screenOff: true,
                    borderless: true, clipboard: false, recording: false,
                    macKeyboard: true)),
            "screen-off change requires a restart")

        expect(MirrorControlsPreview.state.options.alwaysOnTop, "preview shows the pinned state")
        expect(MirrorControlsPreview.state.isMirroring, "preview shows a running mirror")
        expect(
            MirrorControlsPreview.state.recordingElapsedSeconds != nil,
            "preview shows recording status")
        expect(
            MirrorControlsPreview.state.lastCapturePath?.contains("Desktop") == true,
            "preview shows a saved capture path")
    }
}
