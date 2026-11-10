//
//  AppsLogicTests.swift
//  CoreLogicTests
//
//  Deterministic cover for the Apps tab's pure logic: package container
//  detection, split selection, archive path safety, aapt2 discovery/badging
//  parsing, install-error copy, Meld Mode support and deep links.
//
//  Compiled by scripts/test-macos-logic.sh together with Foundation-only app
//  sources. Entry point: runAppsLogicTests().
//

import Foundation

func runAppsLogicTests() {
    packageFormatDetection()
    packageSplitSelection()
    archiveSafety()
    aaptBadgingParsing()
    aaptDiscovery()
    installErrorMessageMapping()
    meldModeSupport()
    appDeepLinks()
    shortcutNaming()
}

// MARK: - Package format

private func packageFormatDetection() {
    suite("PackageFormat.detect") {
        expect(PackageFormat.detect(fileName: "WhatsApp.apk") == .apk, "apk extension")
        expect(PackageFormat.detect(fileName: "bundle.APKS") == .apks, "apks is case-insensitive")
        expect(PackageFormat.detect(fileName: "app.apkm") == .apkm, "apkm extension")
        expect(PackageFormat.detect(fileName: "app.xapk") == .xapk, "xapk extension")
        expect(PackageFormat.detect(fileName: "app.zip") == .unknown, "zip is not a package")
        expect(PackageFormat.detect(fileName: "app").isBundle == false, "unknown is not a bundle")
        expect(PackageFormat.detect(fileName: "app.apks").isBundle, "apks needs install-multiple")
        expect(PackageFormat.detect(fileName: "app.apk").isBundle == false, "plain apk is single")

        expect(
            PackageFormat.detect(fileName: "download.zip", archiveEntries: ["base.apk", "split_config.en.apk"])
                == .apks,
            "renamed split archive is detected from contents")
        expect(
            PackageFormat.detect(
                fileName: "download.zip",
                archiveEntries: ["base.apk", "manifest.json"]) == .xapk,
            "manifest.json means XAPK")
        expect(
            PackageFormat.detect(fileName: "download.zip", archiveEntries: ["readme.txt"]) == .unknown,
            "no APK in archive stays unknown")
        expect(
            PackageFormat.detect(fileName: "app.apk", archiveEntries: ["manifest.json"]) == .apk,
            "extension wins when it is known")
    }
}

// MARK: - Splits

private func packageSplitSelection() {
    suite("PackageSplitSelector") {
        let apks = [
            "toc.pb",
            "base.apk",
            "split_config.arm64_v8a.apk",
            "split_config.en.apk",
        ]
        let selection = PackageSplitSelector.select(from: apks)
        expect(selection?.baseEntry == "base.apk", "base.apk is the base")
        expect(selection?.splitEntries == ["split_config.arm64_v8a.apk", "split_config.en.apk"], "splits sorted")
        expect(selection?.count == 3, "count includes base")

        let bundletool = [
            "splits/base-arm64_v8a.apk",
            "splits/base-master.apk",
            "splits/feature-installtime.apk",
            "toc.pb",
        ]
        let bundletoolSelection = PackageSplitSelector.select(from: bundletool)
        expect(bundletoolSelection?.baseEntry == "splits/base-master.apk", "bundletool base-master wins")
        expect(bundletoolSelection?.splitEntries.count == 2, "bundletool splits kept")

        let xapk = [
            "icon.png",
            "manifest.json",
            "com.example.game.apk",
            "config.arm64_v8a.apk",
        ]
        let xapkSelection = PackageSplitSelector.select(from: xapk, baseHint: "com.example.game.apk")
        expect(xapkSelection?.baseEntry == "com.example.game.apk", "XAPK manifest hint picks the base")
        expect(xapkSelection?.splitEntries == ["config.arm64_v8a.apk"], "XAPK split kept")

        let nested = ["nested/base.apk", "base.apk"]
        expect(
            PackageSplitSelector.select(from: nested)?.baseEntry == "base.apk",
            "root base beats a nested copy")

        expect(
            PackageSplitSelector.select(from: ["base.apk"])?.splitEntries.isEmpty == true,
            "single base has no splits")
        expect(
            PackageSplitSelector.select(from: ["readme.txt", "toc.pb"]) == nil,
            "archives without APKs return nil")
    }
}

// MARK: - Archive safety

private func archiveSafety() {
    suite("PackageArchivePath") {
        expect(PackageArchivePath.isSafeRelativePath("base.apk"), "flat file is safe")
        expect(PackageArchivePath.isSafeRelativePath("splits/config.en.apk"), "nested file is safe")
        expect(PackageArchivePath.isSafeRelativePath("a/../b.apk"), "internal parent reference is safe")
        expect(!PackageArchivePath.isSafeRelativePath("../escape.apk"), "leading parent is rejected")
        expect(!PackageArchivePath.isSafeRelativePath("a/../../escape.apk"), "escaping parent is rejected")
        expect(!PackageArchivePath.isSafeRelativePath("/absolute.apk"), "absolute path is rejected")
        expect(!PackageArchivePath.isSafeRelativePath("~home.apk"), "tilde path is rejected")
        expect(!PackageArchivePath.isSafeRelativePath("bad\u{0007}name.apk"), "control characters are rejected")
        expect(!PackageArchivePath.isSafeRelativePath(""), "empty path is rejected")
    }
}

// MARK: - aapt2 badging

private func aaptBadgingParsing() {
    suite("AaptBadgingParser") {
        let output = """
            package: name='com.whatsapp' versionCode='2618000' versionName='2.26.18.0'
            sdkVersion:'23'
            targetSdkVersion:'34'
            uses-permission: name='android.permission.CAMERA'
            uses-permission: name='android.permission.INTERNET'
            uses-permission: name='android.permission.CAMERA'
            application-label:'WhatsApp'
            launchable-activity: name='com.whatsapp.Main'  label='WhatsApp'
            """
        let badging = AaptBadgingParser.parse(output)
        expect(badging.packageName == "com.whatsapp", "package name parses")
        expect(badging.versionCode == "2618000", "versionCode parses")
        expect(badging.versionName == "2.26.18.0", "versionName parses")
        expect(badging.minSDK == "23", "minSdk parses")
        expect(badging.targetSDK == "34", "targetSdk parses")
        expect(badging.applicationLabel == "WhatsApp", "label parses")
        expect(badging.launchableActivity == "com.whatsapp.Main", "launch activity parses")
        expect(badging.permissions.count == 2, "permissions deduplicate")
        expect(badging.permissions.contains("android.permission.INTERNET"), "permissions kept")

        let empty = AaptBadgingParser.parse("not badging output")
        expect(empty.packageName == nil && empty.permissions.isEmpty, "unknown output yields no claims")
    }
}

// MARK: - aapt2 discovery

private func aaptDiscovery() {
    suite("AaptLocator") {
        expect(AaptLocator.versionRank("35.0.1") == [35, 0, 1], "version rank parses numbers")
        expect(AaptLocator.versionRank("9.0.0") == [9, 0, 0], "single digit rank parses")
        expect(AaptLocator.versionRank("junk") == [-1], "unparsable version sorts below")

        let root = NSTemporaryDirectory() + "androlaunch-aapt-\(UUID().uuidString)"
        for version in ["33.0.1", "35.0.0"] {
            let directory = root + "/build-tools/" + version
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let binary = directory + "/aapt2"
            FileManager.default.createFile(atPath: binary, contents: Data("#!/bin/sh\n".utf8))
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary)
        }
        let candidates = AaptLocator.candidatePaths(additionalSDKRoots: [root])
        expect(candidates.first?.contains("35.0.0") == true, "newest build-tools is preferred")
        expect(AaptLocator.aapt2Path(additionalSDKRoots: [root]) != nil, "aapt2 is discovered")
        try? FileManager.default.removeItem(atPath: root)
    }
}

// MARK: - Install errors

private func installErrorMessageMapping() {
    suite("PackageInstallErrorMapper") {
        let signature = PackageInstallErrorMapper.message(
            from: "Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match]",
            deviceName: "Pixel")
        expect(signature.contains("different key"), "signature mismatch is explained")

        let storage = PackageInstallErrorMapper.message(
            from: "Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]", deviceName: "Pixel")
        expect(storage.contains("out of storage"), "storage failure is explained")

        let restricted = PackageInstallErrorMapper.message(
            from: "Failure [INSTALL_FAILED_USER_RESTRICTED: Install canceled by user]")
        expect(restricted.contains("Install via USB"), "OEM restriction is actionable")

        let abi = PackageInstallErrorMapper.message(from: "INSTALL_FAILED_NO_MATCHING_ABIS")
        expect(abi.contains("CPU architecture"), "ABI mismatch is explained")

        let unknown = PackageInstallErrorMapper.message(from: "  some new device error  ")
        expect(unknown == "some new device error", "unknown failures keep the device's words")

        expect(PackageInstallErrorMapper.succeeded(output: "Performing Streamed Install\nSuccess"), "Success is success")
        expect(!PackageInstallErrorMapper.succeeded(output: "Failure [INSTALL_FAILED_INVALID_APK]"), "Failure is failure")
        expect(!PackageInstallErrorMapper.succeeded(output: ""), "empty output is not success")
    }
}

// MARK: - Meld Mode

private func meldModeSupport() {
    suite("MeldModeSupport") {
        expect(MeldModeSupport.behavior(apiLevel: "36").isVirtualDisplay, "Android 16 gets a virtual display")
        expect(MeldModeSupport.behavior(apiLevel: "34").isVirtualDisplay, "Android 14 is the minimum")
        expect(!MeldModeSupport.behavior(apiLevel: "33").isVirtualDisplay, "Android 13 falls back")
        expect(!MeldModeSupport.behavior(apiLevel: "31").isVirtualDisplay, "Android 12 falls back")
        expect(!MeldModeSupport.behavior(apiLevel: nil).isVirtualDisplay, "unknown version falls back")
        expect(MeldModeSupport.supportsVirtualDisplay(apiLevel: "35"), "supportsVirtualDisplay mirrors behavior")
        expect(MeldModeSupport.apiLevel(from: " 34 ") == 34, "api level parses whitespace")
        expect(MeldModeSupport.apiLevel(from: "thirty") == nil, "non-numeric level is unknown")

        expect(AppLaunchMode(queryValue: "meld") == .meldWindow, "meld query maps to Meld")
        expect(AppLaunchMode(queryValue: "MIRROR") == .mirror, "mirror query is case-insensitive")
        expect(AppLaunchMode(queryValue: "bogus") == nil, "unknown mode is rejected")
        expect(AppLaunchMode(queryValue: "  ") == nil, "blank mode is rejected")
    }
}

// MARK: - Deep links

private func appDeepLinks() {
    suite("AppDeepLink") {
        let url = AppDeepLink.makeURL(
            deviceID: "192.168.1.5:5555",
            packageID: "com.google.android.youtube",
            appName: "YouTube & Music",
            mode: .mirror)
        expect(url != nil, "link builds")
        let request = url.flatMap(AppDeepLink.parse)
        expect(request?.deviceID == "192.168.1.5:5555", "serial round-trips with a colon")
        expect(request?.packageID == "com.google.android.youtube", "package round-trips")
        expect(request?.appName == "YouTube & Music", "name round-trips with an ampersand")
        expect(request?.mode == .mirror, "mode round-trips")

        let minimal = AppDeepLink.makeURL(deviceID: "R58M", packageID: "com.example")
        let minimalRequest = minimal.flatMap(AppDeepLink.parse)
        expect(minimalRequest?.appName == nil, "name is optional")
        expect(minimalRequest?.mode == nil, "mode is optional")

        expect(AppDeepLink.parse(URL(string: "https://launch?serial=a&pkg=b")!) == nil, "wrong scheme is rejected")
        expect(AppDeepLink.parse(URL(string: "androlaunch://settings?serial=a&pkg=b")!) == nil, "wrong host is rejected")
        expect(AppDeepLink.parse(URL(string: "androlaunch://launch?serial=a")!) == nil, "missing package is rejected")
        expect(AppDeepLink.parse(URL(string: "androlaunch://launch?serial=&pkg=b")!) == nil, "empty serial is rejected")
        expect(
            AppDeepLink.makeURL(deviceID: "  ", packageID: "com.example") == nil,
            "empty device cannot build a link")

        let infoRequest = AppDeepLink.parse(userInfo: [
            "serial": "R58M123",
            "pkg": "com.example.app",
            "name": "Example",
            "mode": "mirror",
        ])
        expect(infoRequest?.packageID == "com.example.app", "userInfo parses package")
        expect(infoRequest?.mode == .mirror, "userInfo parses mode")
        expect(AppDeepLink.parse(userInfo: [:]) == nil, "empty userInfo is rejected")
    }
}

// MARK: - Shortcut naming

private func shortcutNaming() {
    suite("ShortcutNaming") {
        expect(
            ShortcutNaming.sanitizedComponent("WhatsApp: Business/Pro") == "WhatsApp Business Pro",
            "path separators become spaces")
        expect(
            ShortcutNaming.sanitizedComponent("  Notes   Pro  ") == "Notes Pro",
            "whitespace collapses")
        expect(
            ShortcutNaming.bundleName(appName: "WhatsApp", deviceName: "Pixel 9 Pro", packageID: "com.whatsapp")
                == "WhatsApp on Pixel 9 Pro",
            "bundle name combines app and phone")
        expect(
            ShortcutNaming.bundleName(appName: "  ", deviceName: nil, packageID: "com.example.app")
                == "com.example.app",
            "empty app name falls back to the package")
        expect(
            ShortcutNaming.uniqueBundleName(
                appName: "WhatsApp", deviceName: "Pixel", packageID: "com.whatsapp",
                existingNames: ["WhatsApp on Pixel.app"])
                == "WhatsApp on Pixel 2",
            "duplicate names get a numeric suffix")
        expect(
            ShortcutNaming.uniqueBundleName(
                appName: "WhatsApp", deviceName: "Pixel", packageID: "com.whatsapp",
                existingNames: ["WhatsApp on Pixel", "WhatsApp on Pixel 2"])
                == "WhatsApp on Pixel 3",
            "suffix keeps counting")
        expect(
            ShortcutNaming.identifierSuffix(deviceID: "A", packageID: "com.example")
                == ShortcutNaming.identifierSuffix(deviceID: "A", packageID: "com.example"),
            "identifier suffix is stable")
        expect(
            ShortcutNaming.identifierSuffix(deviceID: "A", packageID: "com.example")
                != ShortcutNaming.identifierSuffix(deviceID: "A", packageID: "com.other"),
            "identifier suffix differs per package")
    }
}
