//
//  StorageLogicTests.swift
//  CoreLogicTests
//
//  Plain-executable regression cover for the storage feature:
//  df/du/diskstats parsing, category + donut math, and Finder-mirror path safety
//  and size caps.
//
//  Compile with Foundation-only sources:
//    PhoneProtocolModels.swift, StorageAnalyticsModels.swift,
//    FinderMirrorModels.swift, StorageLogicTests.swift, main.swift
//

import Foundation

func runStorageLogicTests() {
    runStorageDFParsingTests()
    runStorageDiskStatsTests()
    runStorageCategoryTests()
    runStorageDonutTests()
    runFinderMirrorPathTests()
    runFinderMirrorCapTests()
}

// MARK: - df

private func runStorageDFParsingTests() {
    let df = """
        Filesystem      1K-blocks      Used  Available Use% Mounted on
        /dev/block/dm-7 115343360  78643200   36700160  69% /data
        /dev/block/dm-8  32768000  18874368   13893632  58% /storage/1A2B-3C4D
        tmpfs             1966080         0    1966080   0% /dev
        /dev/fuse       115343360  78643200   36700160  69% /storage/emulated
        """

    suite("StorageAnalyticsParsers.parseAllDFMounts") {
        let mounts = StorageAnalyticsParsers.parseAllDFMounts(df)
        expect(mounts.count == 4, "every data row parses across all mounts")
        expect(!mounts.contains { $0.mountPath == "Mounted on" }, "the header row is skipped")
        expect(mounts.first?.mountPath == "/data", "first data row parses")
        expect(
            mounts.first?.totalBytes == 115343360 * 1024,
            "df KiB values convert to bytes")
        expect(
            mounts.contains { $0.mountPath == "/storage/1A2B-3C4D" },
            "removable mount parses")

        expect(StorageAnalyticsParsers.parseAllDFMounts(nil).isEmpty, "nil output is empty")
        expect(StorageAnalyticsParsers.parseAllDFMounts("").isEmpty, "empty output is empty")
        expect(
            StorageAnalyticsParsers.parseAllDFMounts("error: closed").isEmpty,
            "an adb error yields no mounts")

        let spaced = """
            Filesystem 1K-blocks Used Available Use% Mounted on
            /dev/block/dm-9 1000 400 600 40% /storage/My SD Card
            """
        expect(
            StorageAnalyticsParsers.parseAllDFMounts(spaced).first?.mountPath
                == "/storage/My SD Card",
            "mount paths with spaces survive")
    }

    suite("StorageAnalyticsParsers.internalMount") {
        let mounts = StorageAnalyticsParsers.parseAllDFMounts(df)
        expect(
            StorageAnalyticsParsers.internalMount(from: mounts)?.mountPath == "/data",
            "internal volume is /data")
        expect(
            StorageAnalyticsParsers.internalMount(from: []) == nil,
            "no mounts means no internal volume")

        let dataChild = """
            Filesystem 1K-blocks Used Available Use% Mounted on
            /dev/block/dm-7 1000 400 600 40% /data/user/0
            """
        expect(
            StorageAnalyticsParsers.internalMount(
                from: StorageAnalyticsParsers.parseAllDFMounts(dataChild))?.mountPath
                == "/data/user/0",
            "a /data child mount is accepted as a fallback")
    }

    suite("StorageAnalyticsParsers.removableMounts") {
        let mounts = StorageAnalyticsParsers.parseAllDFMounts(df)
        let removable = StorageAnalyticsParsers.removableMounts(from: mounts)
        expect(removable.count == 1, "only the SD mount is removable")
        expect(removable.first?.mountPath == "/storage/1A2B-3C4D", "SD path is kept")

        let noisy = """
            Filesystem 1K-blocks Used Available Use% Mounted on
            /dev/fuse 1000 400 600 40% /storage/emulated
            /dev/fuse 1000 400 600 40% /storage/emulated/0
            /dev/block/dm-1 1000 400 600 40% /storage/self/primary
            /dev/block/dm-2 1000 400 600 40% /storage/ABCD-1234
            /dev/block/dm-3 1000 400 600 40% /storage/ABCD-1234
            /dev/block/dm-4 0 0 0 0% /storage/EMPTY-0000
            """
        let filtered = StorageAnalyticsParsers.removableMounts(
            from: StorageAnalyticsParsers.parseAllDFMounts(noisy))
        expect(filtered.count == 1, "emulated, self, duplicates and empty volumes are skipped")
        expect(filtered.first?.mountPath == "/storage/ABCD-1234", "real SD volume survives")
    }
}

// MARK: - diskstats

private func runStorageDiskStatsTests() {
    suite("StorageAnalyticsParsers.parseDiskStats") {
        let output = """
            Latency: 12ms [512B Data Write]
            App Size: 49,123,456
            App Data Size: 23,456,789
            Cache Size: 1,234,567
            System Size: 9,876,543
            Data-Free: 55,803,300 K / 115,343,360 K total = 51% free
            """
        let stats = StorageAnalyticsParsers.parseDiskStats(output)
        expect(stats?.appBytes == 49_123_456, "app size parses with thousands separators")
        expect(stats?.appDataBytes == 23_456_789, "app data size parses")
        expect(stats?.appsTotal == 72_580_245, "Apps = app size + app data")
        expect(stats?.systemBytes == 9_876_543, "system size parses")
        expect(stats?.cacheBytes == 1_234_567, "cache size parses")
        expect(stats?.systemTotal == 11_111_110, "System = system + cache")

        expect(
            StorageAnalyticsParsers.parseDiskStats(nil) == nil,
            "nil output is unknown")
        expect(
            StorageAnalyticsParsers.parseDiskStats("Latency: 4ms") == nil,
            "output without size keys is unknown")

        let partial = "App Size: 1000\n"
        let partialStats = StorageAnalyticsParsers.parseDiskStats(partial)
        expect(partialStats?.appsTotal == 1000, "partial output keeps what it can")
        expect(partialStats?.systemTotal == nil, "missing system stays unknown")

        let tabs = "App Size:\t2,048\nCache Size:\t512\n"
        expect(
            StorageAnalyticsParsers.parseDiskStats(tabs)?.appsTotal == 2048,
            "tab-separated values parse")
    }
}

// MARK: - Categories

private func runStorageCategoryTests() {
    suite("StorageAnalyticsParsers.computeInternalCategories") {
        let categories = StorageAnalyticsParsers.computeInternalCategories(
            usedBytes: 1000, appsBytes: 400, userFilesBytes: 300,
            userFilesIsPartial: false)
        expect(categories.count == 3, "Apps, User files and System & Others are all present")
        expect(categories[0].role == .apps && categories[0].bytes == 400, "apps measured")
        expect(categories[1].role == .userFiles && categories[1].bytes == 300, "user files measured")
        expect(categories[2].role == .system && categories[2].bytes == 300, "system is the remainder")
        expect(categories.reduce(Int64(0)) { $0 + $1.bytes } == 1000, "categories sum to used")

        let noApps = StorageAnalyticsParsers.computeInternalCategories(
            usedBytes: 1000, appsBytes: nil, userFilesBytes: 300,
            userFilesIsPartial: false)
        expect(noApps.count == 2, "unknown app sizes fold into System & Others")
        expect(noApps[1].role == .system && noApps[1].bytes == 700, "system includes apps")
        expect(noApps[1].isPartial, "unseparated apps are marked partial")

        let noUserFiles = StorageAnalyticsParsers.computeInternalCategories(
            usedBytes: 1000, appsBytes: 400, userFilesBytes: nil,
            userFilesIsPartial: true)
        expect(noUserFiles[1].bytes == 0, "missing user files measure as zero, not invented")
        expect(noUserFiles[1].isPartial, "missing user files are partial")
        expect(noUserFiles.reduce(Int64(0)) { $0 + $1.bytes } == 1000, "remainder still sums")

        let overshoot = StorageAnalyticsParsers.computeInternalCategories(
            usedBytes: 1000, appsBytes: 5000, userFilesBytes: 5000,
            userFilesIsPartial: false)
        expect(overshoot[0].bytes == 1000, "app bytes clamp to used")
        expect(overshoot[1].bytes == 0, "user files clamp to remaining space")
        expect(overshoot[2].bytes == 0, "system never goes negative")

        expect(
            StorageAnalyticsParsers.computeInternalCategories(
                usedBytes: 0, appsBytes: 1, userFilesBytes: 1, userFilesIsPartial: false
            ).isEmpty,
            "a zero used volume has no categories")
    }

    suite("StorageAnalyticsParsers.computeRemovableCategories") {
        let categories = StorageAnalyticsParsers.computeRemovableCategories(
            usedBytes: 1000, userFilesBytes: 600, userFilesIsPartial: false)
        expect(categories.count == 2, "SD card has User files and System & Others")
        expect(categories[0].bytes == 600, "SD user files measured")
        expect(categories[1].bytes == 400, "SD remainder is System & Others")
        expect(categories[1].isPartial, "SD remainder is always approximate")

        let unknown = StorageAnalyticsParsers.computeRemovableCategories(
            usedBytes: 1000, userFilesBytes: nil, userFilesIsPartial: true)
        expect(unknown[0].bytes == 0 && unknown[0].isPartial, "unknown user files are partial")
        expect(unknown[1].bytes == 1000, "all used space is the remainder")
    }

    suite("StorageAnalyticsParsers helpers") {
        let folders = [
            StorageFolder(name: "DCIM", bytes: 300),
            StorageFolder(name: "Download", bytes: 200),
        ]
        expect(StorageAnalyticsParsers.sumFolders(folders) == 500, "folder bytes sum")
        expect(StorageAnalyticsParsers.sumFolders([]) == 0, "no folders sum to zero")
        expect(StorageAnalyticsParsers.clampBytes(900, to: 500) == 500, "clamp to limit")
        expect(StorageAnalyticsParsers.clampBytes(-4, to: 500) == 0, "negative clamps to zero")
        expect(StorageAnalyticsParsers.folderName(fromPath: "/sdcard/DCIM/") == "DCIM", "folder names trim slashes")
        expect(StorageAnalyticsParsers.folderName(fromPath: "/sdcard") == "sdcard", "leaf folder name")
    }
}

// MARK: - Donut math

private func runStorageDonutTests() {
    suite("StorageDonutMath") {
        expect(
            StorageDonutMath.usedFraction(usedBytes: 0, totalBytes: 0) == 0,
            "zero total has no used fraction")
        expect(
            StorageDonutMath.usedFraction(usedBytes: 2000, totalBytes: 1000) == 1,
            "over-full volumes clamp to one")
        expect(
            StorageDonutMath.usedFraction(usedBytes: 500, totalBytes: 1000) == 0.5,
            "half used")
        expect(
            StorageDonutMath.freeFraction(usedBytes: 250, totalBytes: 1000) == 0.75,
            "free fraction is the complement")

        let categories = [
            StorageCategory(role: .apps, bytes: 400),
            StorageCategory(role: .userFiles, bytes: 300),
            StorageCategory(role: .system, bytes: 300),
        ]
        let arcs = StorageDonutMath.arcs(
            categories: categories, usedBytes: 1000, totalBytes: 2000)
        expect(arcs.count == 3, "one arc per non-empty category")
        expect(arcs.map(\.role) == [.apps, .userFiles, .system], "arc order matches legend order")
        let covered = arcs.reduce(0.0) { $0 + $1.span }
        // Small visual gaps sit between arcs, so coverage is slightly under half.
        expect(abs(covered - 0.5) < 0.03, "arcs cover the used half of the ring")
        expect(arcs.allSatisfy { $0.start >= 0 && $0.end <= 0.5001 }, "arcs stay in the used sector")
        expect(arcs[0].end <= arcs[1].start + 0.0001, "arcs do not overlap")

        let empty = StorageDonutMath.arcs(
            categories: [], usedBytes: 500, totalBytes: 1000)
        expect(empty.isEmpty, "no categories means no arcs")

        let zeroUsed = StorageDonutMath.arcs(
            categories: categories, usedBytes: 0, totalBytes: 1000)
        expect(zeroUsed.isEmpty, "an unused volume has no arcs")

        let zeroTotal = StorageDonutMath.arcs(
            categories: categories, usedBytes: 100, totalBytes: 0)
        expect(zeroTotal.isEmpty, "a volume without capacity has no arcs")

        let tiny = StorageDonutMath.arcs(
            categories: [
                StorageCategory(role: .apps, bytes: 1),
                StorageCategory(role: .system, bytes: 999),
            ],
            usedBytes: 1000,
            totalBytes: 1000)
        expect(tiny.count == 2, "a tiny category is still drawn")
        expect(tiny[0].span > 0, "tiny arc keeps a positive span")
        expect(tiny[0].span < 0.01, "tiny arc is small")

        let zeroCategory = StorageDonutMath.arcs(
            categories: [
                StorageCategory(role: .apps, bytes: 0),
                StorageCategory(role: .userFiles, bytes: 100),
            ],
            usedBytes: 100,
            totalBytes: 100)
        expect(zeroCategory.count == 1, "zero-byte categories are omitted")
    }
}

// MARK: - Finder mirror paths

private func runFinderMirrorPathTests() {
    suite("FinderMirrorLogic.sanitizedDeviceFolderName") {
        expect(
            FinderMirrorLogic.sanitizedDeviceFolderName("Pixel 9 Pro") == "Pixel 9 Pro",
            "a normal name is unchanged")
        expect(
            FinderMirrorLogic.sanitizedDeviceFolderName("a/b:c\\d") == "abcd",
            "path separators and colons are stripped")
        expect(
            FinderMirrorLogic.sanitizedDeviceFolderName("  ") == "Android device",
            "blank names use the fallback")
        expect(
            FinderMirrorLogic.sanitizedDeviceFolderName("...") == "Android device",
            "dot-only names use the fallback")
        expect(
            FinderMirrorLogic.sanitizedDeviceFolderName("..") == "Android device",
            "parent path is never a folder name")
        expect(
            FinderMirrorLogic.sanitizedDeviceFolderName("  Galaxy   S25  ")
                == "Galaxy S25",
            "whitespace collapses")
        expect(
            FinderMirrorLogic.sanitizedDeviceFolderName("bad\u{0007}name") == "badname",
            "control characters are stripped")
        let long = String(repeating: "A", count: 200)
        expect(
            FinderMirrorLogic.sanitizedDeviceFolderName(long).count
                == FinderMirrorLimits.maxDeviceFolderNameLength,
            "long names are capped")
        expect(
            FinderMirrorLogic.sanitizedDeviceFolderName("ok", fallback: "fallback") == "ok",
            "fallback is unused for valid names")
    }

    suite("FinderMirrorLogic locations") {
        let home = "/Users/tester"
        let root = FinderMirrorLogic.mirrorLibraryRoot(homeDirectory: home)
        expect(
            root == "/Users/tester/Library/Application Support/AndroLaunch/Finder",
            "mirror library lives in Application Support")
        expect(
            FinderMirrorLogic.sidebarRoot(homeDirectory: home) == "/Users/tester/AndroLaunch",
            "sidebar root is ~/AndroLaunch")

        let location = FinderMirrorLogic.location(
            deviceName: "Pixel 9 Pro", deviceID: "R58M", scope: .camera,
            homeDirectory: home)
        expect(location.deviceFolderName == "Pixel 9 Pro", "device folder name is safe")
        expect(
            location.scopeDirectory
                == "/Users/tester/Library/Application Support/AndroLaunch/Finder/Pixel 9 Pro/Camera",
            "scope folder is namespaced under the device")
        expect(
            FinderMirrorLogic.location(
                deviceName: nil, deviceID: "192.168.1.5:5555", scope: .sdCard,
                homeDirectory: home
            ).deviceFolderName == "192.168.1.55555",
            "a transport id is sanitized when there is no name")

        let names = Set(
            FinderMirrorScope.allCases.map {
                FinderMirrorLogic.location(
                    deviceName: "Phone", deviceID: "id", scope: $0, homeDirectory: home
                ).scopeDirectory
            })
        expect(names.count == FinderMirrorScope.allCases.count, "scope folders are unique")
    }

    suite("FinderMirrorLogic containment") {
        expect(FinderMirrorLogic.isContained("/a/b/c", within: "/a/b"), "child is contained")
        expect(FinderMirrorLogic.isContained("/a/b", within: "/a/b"), "same path is contained")
        expect(!FinderMirrorLogic.isContained("/a/bc", within: "/a/b"), "prefix trap is rejected")
        expect(!FinderMirrorLogic.isContained("/a", within: "/a/b"), "parent is not contained")
        expect(!FinderMirrorLogic.isContained("/etc/passwd", within: "/a/b"), "outside is rejected")
        expect(
            FinderMirrorLogic.isContained("/a/b/../b/c", within: "/a/b"),
            "standardized traversal inside the root is allowed")
    }

    suite("FinderMirrorLogic.isSafeComponent") {
        expect(FinderMirrorLogic.isSafeComponent("DCIM"), "normal folder is safe")
        expect(FinderMirrorLogic.isSafeComponent("My Folder"), "spaces are safe")
        expect(!FinderMirrorLogic.isSafeComponent(""), "empty is unsafe")
        expect(!FinderMirrorLogic.isSafeComponent("."), "dot is unsafe")
        expect(!FinderMirrorLogic.isSafeComponent(".."), "dot-dot is unsafe")
        expect(!FinderMirrorLogic.isSafeComponent(".hidden"), "hidden is unsafe")
        expect(!FinderMirrorLogic.isSafeComponent("a/b"), "slash is unsafe")
        expect(!FinderMirrorLogic.isSafeComponent("a\\b"), "backslash is unsafe")
        expect(!FinderMirrorLogic.isSafeComponent("a:b"), "colon is unsafe")
        expect(!FinderMirrorLogic.isSafeComponent("tab\tname"), "control chars are unsafe")

        expect(
            FinderMirrorSafeFolders.filtered(
                fromListing: "DCIM\nDownload\nAndroid\n.metadata\nnot-owned\n")
                == ["DCIM", "Download"],
            "listings keep only safe user folders")
    }
}

// MARK: - Finder mirror caps

private func runFinderMirrorCapTests() {
    suite("FinderMirrorLogic caps and progress") {
        let limit: Int64 = 1024
        expect(FinderMirrorLogic.fitsCap(estimatedBytes: 1024, limit: limit), "exact cap fits")
        expect(!FinderMirrorLogic.fitsCap(estimatedBytes: 1025, limit: limit), "over cap is refused")
        expect(!FinderMirrorLogic.fitsCap(estimatedBytes: -1, limit: limit), "negative estimate refused")
        expect(!FinderMirrorLogic.fitsCap(estimatedBytes: 10, limit: 0), "zero limit refuses")

        let description = FinderMirrorLogic.capDescription(bytes: 4096, limit: 1024)
        expect(description.contains("4.0 KB"), "cap message names the size")
        expect(description.contains("1.0 KB"), "cap message names the limit")

        expect(
            FinderMirrorLogic.progressFraction(completedBytes: 50, totalBytes: 100) == 0.5,
            "progress fraction")
        expect(
            FinderMirrorLogic.progressFraction(completedBytes: 200, totalBytes: 100) == 1,
            "progress clamps at one")
        expect(
            FinderMirrorLogic.progressFraction(completedBytes: 0, totalBytes: 0) == 0,
            "unknown totals report zero")

        expect(
            FinderMirrorLogic.pullProgressPercent(from: "[ 42%] /sdcard/DCIM/Camera/a.jpg")
                == 42,
            "adb pull progress parses")
        expect(
            FinderMirrorLogic.pullProgressPercent(from: "no progress here") == nil,
            "non-progress output is ignored")
        expect(
            FinderMirrorLogic.pullProgressPercent(from: "[ 140%] file") == nil,
            "out-of-range progress is ignored")

        expect(
            FinderMirrorLogic.estimatedBytes(fromDU: "1024\t/sdcard/DCIM\n2048\t/sdcard/Download\n")
                == 3072 * 1024,
            "du output sums to bytes")
        expect(
            FinderMirrorLogic.estimatedBytes(fromDU: "garbage") == nil,
            "unparsable du is unknown")
        expect(FinderMirrorLogic.estimatedBytes(fromDU: "") == nil, "empty du is unknown")
    }
}
