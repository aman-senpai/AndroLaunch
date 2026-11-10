//
//  HubSnapshotRenderer.swift
//  AndroLaunch
//
//  DEBUG-only visual verification: renders the real Hub views with ImageRenderer
//  so design review does not need Screen Recording permission or a visible window.
//
//  Usage: AndroLaunch --render-hub-snapshots <output-directory>
//

import AppKit
import SwiftUI

enum HubSnapshotRenderer {
    @MainActor
    static func render(to directoryPath: String) {
        let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        let store = HubStore(previewDevices: HubPreviewData.devices)

        store.tab = .devices
        render(
            HubView(store: store),
            size: CGSize(width: 480, height: 800),
            name: "01-devices.png", in: directory)

        // Explicit expanded states for design review. Feature views may read
        // `\.hubPreviewScenario` to open the relevant cards deterministically.
        render(
            HubView(store: store),
            size: CGSize(width: 480, height: 1100),
            name: "01b-devices-expanded.png", in: directory,
            scenario: "devices-expanded")
        render(
            HubView(store: store),
            size: CGSize(width: 480, height: 1100),
            name: "01c-devices-wifi.png", in: directory,
            scenario: "wifi-expanded")

        store.tab = .apps
        render(
            HubView(store: store),
            size: CGSize(width: 480, height: 0),
            name: "02-apps.png", in: directory, naturalHeight: true)
        render(
            HubView(store: store),
            size: CGSize(width: 480, height: 0),
            name: "02b-apps-list.png", in: directory,
            scenario: "apps-list", naturalHeight: true)

        store.tab = .settings
        render(
            HubView(store: store),
            size: CGSize(width: 480, height: 0),
            name: "03-settings.png", in: directory, naturalHeight: true)

        render(
            StorageAnalyticsView(
                previewSnapshot: StorageSnapshot.preview, deviceName: "Pixel 9 Pro"),
            size: CGSize(width: 560, height: 1420),
            name: "15-storage-analytics.png", in: directory)

        render(
            StorageAnalyticsView(
                previewSnapshot: StorageSnapshot.preview, deviceName: "Pixel 9 Pro",
                focusedCategory: .userFiles),
            size: CGSize(width: 560, height: 900),
            name: "16-storage-folders.png", in: directory)

        render(
            StorageOverviewCard(
                previewSnapshot: StorageSnapshot.preview, deviceName: "Pixel 9 Pro")
                .padding(20)
                .background(HubColor.background),
            size: CGSize(width: 400, height: 460),
            name: "17-storage-card.png", in: directory)

        render(
            MirrorControlsView(preview: MirrorControlsPreview.state)
                .padding(20)
                .background(HubColor.background),
            size: CGSize(width: 340, height: 0),
            name: "09-mirror-controls.png", in: directory, naturalHeight: true)

        // Compact device dashboard tabs (fixed-size preview data).
        for (index, tab) in DeviceDashboardTab.allCases.enumerated() {
            render(
                DeviceDashboardView(previewTab: tab),
                size: CGSize(width: 380, height: 0),
                name: String(format: "%02d-dashboard-%@.png", index + 10, tab.rawValue),
                in: directory, naturalHeight: true)
        }

        for (index, tab) in WiFiConnectionTab.allCases.enumerated() {
            let content = WiFiConnectionView(store: store, initialTab: tab)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(HubColor.background)
            render(
                content,
                size: CGSize(width: 480, height: 640),
                name: String(format: "%02d-wifi-%@.png", index + 5, tab.rawValue),
                in: directory)
        }
    }

    @MainActor
    private static func render<V: View>(
        _ view: V, size: CGSize, name: String, in directory: URL,
        scenario: String? = nil, naturalHeight: Bool = false
    ) {
        let renderer = ImageRenderer(
            content: view
                .frame(width: size.width, height: naturalHeight ? nil : size.height)
                .environment(\.colorScheme, .dark)
                .environment(\.dynamicTypeSize, .large)
                .environment(\.hubSnapshotMode, true)
                .environment(\.hubPreviewScenario, scenario)
        )
        renderer.scale = 2
        renderer.isOpaque = true
        guard let cgImage = renderer.cgImage else {
            FileHandle.standardError.write(Data("snapshot failed: \(name)\n".utf8))
            return
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("png encode failed: \(name)\n".utf8))
            return
        }
        do {
            try data.write(to: directory.appendingPathComponent(name))
            print("rendered \(name)")
        } catch {
            FileHandle.standardError.write(
                Data("write failed for \(name): \(error.localizedDescription)\n".utf8))
        }
    }
}
