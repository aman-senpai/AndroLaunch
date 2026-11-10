//
//  MenuBarDashboardView.swift
//  AndroLaunch
//
//  Root SwiftUI view of the menu-bar glass panel. Live it hosts the existing
//  DeviceDashboardView in glass mode; the `MenuBarDashboardPreview` wrapper adds
//  a deterministic desktop backdrop so `ImageRenderer` can review light and
//  dark Liquid Glass without a window server.
//

import SwiftUI

struct MenuBarDashboardView: View {
    var initialTab: DeviceDashboardTab = .apps
    var actions: MenuBarPanelActions = .preview

    var body: some View {
        DeviceDashboardView(
            deviceID: nil,
            initialTab: initialTab,
            panelActions: actions)
            .environment(\.hubGlassMode, true)
    }
}

// MARK: - Snapshot preview

/// Panel rendered on a synthetic desktop wallpaper. Used only by the DEBUG
/// snapshot renderer; never by the live panel.
struct MenuBarDashboardPreview: View {
    let appearance: ColorScheme
    var initialTab: DeviceDashboardTab = .apps
    var showsTools: Bool = false
    var hoveredTab: DeviceDashboardTab? = nil

    var body: some View {
        ZStack {
            MenuBarPanelWallpaper(appearance: appearance)

            panel
                .frame(width: MenuBarPanelGeometry.panelWidth, height: MenuBarPanelGeometry.panelHeight)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            appearance == .dark
                                ? Color.white.opacity(0.16) : Color.black.opacity(0.12),
                            lineWidth: 1))
                .shadow(
                    color: .black.opacity(appearance == .dark ? 0.55 : 0.28),
                    radius: 30, y: 14)
        }
        .frame(width: 460, height: 840)
        .environment(\.colorScheme, appearance)
    }

    private var panel: some View {
        ZStack {
            // Stand-in for the NSPanel's behind-window NSVisualEffectView: the
            // wallpaper colours are blurred inside the panel, then a thin
            // material and tint give the Liquid Glass body.
            MenuBarPanelWallpaper(appearance: appearance)
                .blur(radius: appearance == .dark ? 34 : 26)
                .opacity(1)
            // Light glass is a bright frosted sheet; the ultra-thin material alone
            // turns grey over a light desktop, so add a regular-material base plus
            // a white lift. Dark keeps the thinner, deeper treatment.
            Rectangle()
                .fill(.regularMaterial)
                .opacity(appearance == .dark ? 0.0 : 0.18)
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(appearance == .dark ? 0.66 : 0.10)
            Rectangle()
                .fill(
                    appearance == .dark
                        ? Color.black.opacity(0.20) : Color.white.opacity(0.50))
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(appearance == .dark ? 0.03 : 0.10),
                            Color.black.opacity(appearance == .dark ? 0.08 : 0.03),
                            Color.clear,
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(appearance == .dark ? 0.08 : 0.26),
                            Color.clear,
                        ],
                        startPoint: .top, endPoint: .init(x: 0.5, y: 0.3)))

            DeviceDashboardView(
                previewTab: initialTab,
                panelActions: .preview,
                showsTools: showsTools,
                hoveredTab: hoveredTab)
                .environment(\.hubGlassMode, true)
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.white.opacity(appearance == .dark ? 0.22 : 0.55))
                .frame(width: 150, height: 1)
                .padding(.top, 1)
        }
    }
}

// MARK: - Wallpaper

private struct MenuBarPanelWallpaper: View {
    let appearance: ColorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: appearance == .dark
                    ? [Color(hex: 0x24262B), Color(hex: 0x090A0C)]
                    : [Color(hex: 0xE9EAEE), Color(hex: 0xB4B7BE)],
                startPoint: .topLeading, endPoint: .bottomTrailing)

            Circle()
                .fill(Color.white.opacity(appearance == .dark ? 0.10 : 0.38))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -150, y: -280)

            Circle()
                .fill(Color.black.opacity(appearance == .dark ? 0.22 : 0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 180, y: -180)

            Circle()
                .fill(Color.white.opacity(appearance == .dark ? 0.06 : 0.22))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: 120, y: 300)

            LinearGradient(
                colors: [.black.opacity(appearance == .dark ? 0.28 : 0.06), .clear],
                startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }
}
