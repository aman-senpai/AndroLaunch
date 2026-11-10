//
//  StorageSnapshotPreview.swift
//  AndroLaunch
//
//  Deterministic storage fixture + the DEBUG `ImageRenderer` harness for the
//  storage card and analytics window. The Lead-owned Hub snapshot renderer can
//  call these initializers directly; the harness here is platform-extras' own
//  visual check.
//

import AppKit
import SwiftUI

// MARK: - Deterministic preview

/// Fixture used by the DEBUG snapshot renderer and SwiftUI previews so the storage
/// card and analytics window can be reviewed without a phone attached.
///
/// Kept outside `StorageService` (and outside `#if DEBUG`) so the snapshot
/// renderer can use `StorageSnapshot.preview` from either configuration.
extension StorageSnapshot {
    static var preview: StorageSnapshot {
        let gigabyte: Int64 = 1024 * 1024 * 1024
        let megabyte: Int64 = 1024 * 1024

        let internalTotal: Int64 = 128 * gigabyte
        let internalUsed: Int64 = 115 * gigabyte + 205 * megabyte
        let apps: Int64 = 49 * gigabyte + 102 * megabyte
        let userFiles: Int64 = 23 * gigabyte + 717 * megabyte
        let system = max(0, internalUsed - apps - userFiles)

        let sharedFolders = [
            StorageFolder(name: "DCIM", bytes: 8 * gigabyte + 205 * megabyte),
            StorageFolder(name: "Pictures", bytes: 5 * gigabyte + 102 * megabyte),
            StorageFolder(name: "Movies", bytes: 4 * gigabyte + 11 * megabyte),
            StorageFolder(name: "Download", bytes: 3 * gigabyte + 410 * megabyte),
            StorageFolder(name: "Documents", bytes: 2 * gigabyte + 614 * megabyte),
            StorageFolder(name: "Android", bytes: 76 * megabyte),
            StorageFolder(name: "Music", bytes: 410 * megabyte),
        ]

        let internalVolume = StorageVolume(
            id: "internal-/data",
            kind: .internalStorage,
            title: "Internal storage",
            mountPath: "/data",
            totalBytes: internalTotal,
            usedBytes: internalUsed,
            freeBytes: internalTotal - internalUsed,
            categories: [
                StorageCategory(role: .apps, bytes: apps),
                StorageCategory(role: .userFiles, bytes: userFiles),
                StorageCategory(role: .system, bytes: system, isPartial: true),
            ],
            folders: sharedFolders,
            isPartial: true)

        let sharedStorage = StorageVolume(
            id: "shared-/storage/emulated/0",
            kind: .sharedStorage,
            title: "Shared storage",
            mountPath: "/storage/emulated/0",
            totalBytes: 0,
            usedBytes: userFiles,
            freeBytes: 0,
            categories: [StorageCategory(role: .userFiles, bytes: userFiles)],
            folders: sharedFolders,
            isPartial: false)

        let sdTotal: Int64 = 32 * gigabyte
        let sdSystem: Int64 = 24 * megabyte + 200 * 1024
        let sdUsed: Int64 = 18 * gigabyte
        let sdUserFiles = max(0, sdUsed - sdSystem)
        let sdVolume = StorageVolume(
            id: "removable-/storage/1A2B-3C4D",
            kind: .removable,
            title: "Samsung SD card",
            mountPath: "/storage/1A2B-3C4D",
            totalBytes: sdTotal,
            usedBytes: sdUsed,
            freeBytes: sdTotal - sdUsed,
            categories: [
                StorageCategory(role: .userFiles, bytes: sdUserFiles),
                StorageCategory(role: .system, bytes: sdSystem, isPartial: true),
            ],
            folders: [
                StorageFolder(name: "Memory Box", bytes: sdUserFiles - 300 * megabyte),
                StorageFolder(name: "Wanted", bytes: 204 * megabyte),
                StorageFolder(name: "Android", bytes: 76 * megabyte),
            ],
            isPartial: false)

        let largestItems = [
            StorageItem(name: "VID_20260914_4K.mp4", path: "/sdcard/DCIM/Camera/VID_20260914_4K.mp4", bytes: 1_204 * megabyte),
            StorageItem(name: "IMG_20260901.jpg", path: "/sdcard/DCIM/Camera/IMG_20260901.jpg", bytes: 48 * megabyte),
            StorageItem(name: "backup-2026.zip", path: "/sdcard/Download/backup-2026.zip", bytes: 33 * megabyte),
        ]

        return StorageSnapshot(
            deviceID: "R58M12PREVIEW",
            totalBytes: internalTotal,
            usedBytes: internalUsed,
            freeBytes: internalTotal - internalUsed,
            folders: sharedFolders,
            largestItems: largestItems,
            scannedAt: Date(timeIntervalSince1970: 1_781_000_000),
            source: .adb,
            folderListComplete: false,
            internalVolume: internalVolume,
            sharedStorage: sharedStorage,
            removableVolumes: [sdVolume],
            partialReasons: [
                "App sizes are approximate: `dumpsys diskstats` reports rounded categories.",
                "Shared-storage folders are measured over adb; Android hides some app data from every scan.",
            ])
    }
}



#if DEBUG
    /// Renders the storage card and analytics window to PNG without a phone or a
    /// window-server session.
    enum StorageSnapshotPreview {
        @MainActor
        static func render(to directoryPath: String) {
            let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)

            render(
                StorageOverviewCard(previewSnapshot: .preview, deviceName: "Pixel 9 Pro")
                    .padding(20)
                    .frame(width: 400),
                size: CGSize(width: 400, height: 430),
                name: "storage-card.png", in: directory)

            // The live window scrolls at 560×760; the snapshot renders the full
            // content so every section can be reviewed at once.
            render(
                StorageAnalyticsView(previewSnapshot: .preview, deviceName: "Pixel 9 Pro"),
                size: CGSize(width: 560, height: 1420),
                name: "storage-analytics.png", in: directory)

            render(
                StorageAnalyticsView(
                    previewSnapshot: .preview,
                    deviceName: "Pixel 9 Pro",
                    focusedCategory: .userFiles),
                size: CGSize(width: 560, height: 900),
                name: "storage-analytics-folders.png", in: directory)
        }

        @MainActor
        private static func render<V: View>(
            _ view: V, size: CGSize, name: String, in directory: URL
        ) {
            let renderer = ImageRenderer(
                content: view
                    .frame(width: size.width, height: size.height)
                    .background(HubColor.background)
                    .environment(\.colorScheme, .dark)
                    .environment(\.dynamicTypeSize, .large)
                    .environment(\.hubSnapshotMode, true)
            )
            renderer.scale = 2
            guard let cgImage = renderer.cgImage else {
                FileHandle.standardError.write(Data("snapshot failed: \(name)\n".utf8))
                return
            }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            do {
                try data.write(to: directory.appendingPathComponent(name))
                print("rendered \(name)")
            } catch {
                FileHandle.standardError.write(
                    Data("write failed for \(name): \(error.localizedDescription)\n".utf8))
            }
        }
    }
#endif
