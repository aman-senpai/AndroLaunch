//
//  MenuBarPanelSnapshotRenderer.swift
//  AndroLaunch
//
//  DEBUG-only visual verification for the menu-bar glass panel. Renders the
//  panel on a deterministic wallpaper in both appearances with ImageRenderer, so
//  light/dark Liquid Glass can be reviewed without Screen Recording permission.
//
//  Entry point: `AndroLaunch --render-menu-bar-panel-snapshots <directory>`
//  handled by StatusMenuController before the menu bar item is configured.
//

#if DEBUG
    import AppKit
    import SwiftUI

    enum MenuBarPanelSnapshotRenderer {
        /// Returns true when the process was launched in snapshot mode.
        @MainActor
        static func renderIfRequested(arguments: [String] = CommandLine.arguments) -> Bool {
            guard
                let index = arguments.firstIndex(of: "--render-menu-bar-panel-snapshots")
            else { return false }
            let output = arguments.indices.contains(index + 1)
                ? arguments[index + 1]
                : NSTemporaryDirectory() + "androlaunch-panel-snapshots"
            render(to: output)
            return true
        }

        @MainActor
        static func render(to directoryPath: String) {
            let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)

            for appearance in [ColorScheme.dark, .light] {
                let label = appearance == .dark ? "dark" : "light"
                // Stable convenience names for the primary Apps tab.
                render(
                    appearance: appearance,
                    tab: .apps,
                    name: "menubar-panel-\(label).png",
                    in: directory)
                for tab in DeviceDashboardTab.allCases {
                    render(
                        appearance: appearance,
                        tab: tab,
                        name: "menubar-panel-\(label)-\(tab.rawValue).png",
                        in: directory)
                }
                render(
                    appearance: appearance,
                    tab: .apps,
                    showsTools: true,
                    name: "menubar-panel-\(label)-tools.png",
                    in: directory)
                render(
                    appearance: appearance,
                    tab: .apps,
                    hoveredTab: .notifications,
                    name: "menubar-panel-\(label)-hover.png",
                    in: directory)
            }
        }

        @MainActor
        private static func render(
            appearance: ColorScheme,
            tab: DeviceDashboardTab,
            showsTools: Bool = false,
            hoveredTab: DeviceDashboardTab? = nil,
            name: String,
            in directory: URL
        ) {
            let view = MenuBarDashboardPreview(
                appearance: appearance,
                initialTab: tab,
                showsTools: showsTools,
                hoveredTab: hoveredTab)
                .environment(\.colorScheme, appearance)
                .environment(\.dynamicTypeSize, .large)
                .environment(\.hubSnapshotMode, true)
                .environment(\.hubGlassMode, true)

            // `HubColor` resolves through dynamic NSColor providers, so the
            // drawing appearance has to match the requested scheme or a light
            // render keeps dark-mode text.
            var pngData: Data?
            if let nsAppearance = NSAppearance(
                named: appearance == .dark ? .darkAqua : .aqua)
            {
                nsAppearance.performAsCurrentDrawingAppearance {
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    renderer.isOpaque = true
                    if let cgImage = renderer.cgImage {
                        pngData = NSBitmapImageRep(cgImage: cgImage)
                            .representation(using: .png, properties: [:])
                    }
                }
            }

            guard let data = pngData else {
                FileHandle.standardError.write(
                    Data("panel snapshot failed: \(name)\n".utf8))
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
#endif
