//
//  HubTheme.swift
//  AndroLaunch
//
//  The Hub design system. Dark-first, semantic, and dependency-free so
//  every screen uses one set of surfaces, tones and metrics.
//

import AppKit
import SwiftUI

// MARK: - Palette

enum HubColor {
    // Surfaces
    static let windowTop = dynamic(light: 0xF4F4F7, dark: 0x1A1A1D)
    static let windowBottom = dynamic(light: 0xECECF1, dark: 0x0F0F11)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x202023)
    static let cardElevated = dynamic(light: 0xF3F3F6, dark: 0x2A2A2E)
    static let cardHover = dynamic(light: 0xEBEBF0, dark: 0x303034)
    static let stroke = dynamic(light: 0x000000, dark: 0xFFFFFF, alpha: 0.08)
    static let strokeStrong = dynamic(light: 0x000000, dark: 0xFFFFFF, alpha: 0.14)

    // Text
    static let textPrimary = dynamic(light: 0x1C1C1E, dark: 0xF5F5F7)
    static let textSecondary = dynamic(light: 0x64646A, dark: 0x9B9BA1)
    static let textTertiary = dynamic(light: 0x8E8E93, dark: 0x6E6E73)

    // Accents (monochrome: charcoal in light, silver in dark)
    static let accent = dynamic(light: 0x3A3A3E, dark: 0xD6D6DB)
    static let accentSoft = dynamic(light: 0x3A3A3E, dark: 0xD6D6DB, alpha: 0.14)
    static let success = dynamic(light: 0x248A3D, dark: 0x30D158)
    static let successSoft = dynamic(light: 0x248A3D, dark: 0x30D158, alpha: 0.14)
    static let warning = dynamic(light: 0xC93400, dark: 0xFF9F0A)
    static let warningSoft = dynamic(light: 0xC93400, dark: 0xFF9F0A, alpha: 0.14)
    static let danger = dynamic(light: 0xD70015, dark: 0xFF375F)
    static let dangerSoft = dynamic(light: 0xD70015, dark: 0xFF375F, alpha: 0.14)
    static let controlTrack = dynamic(light: 0x000000, dark: 0xFFFFFF, alpha: 0.10)
    /// Historical names kept so existing call sites compile; both are neutral.
    static let purpleWash = dynamic(light: 0x000000, dark: 0xFFFFFF, alpha: 0.05)
    static let greenWash = dynamic(light: 0x000000, dark: 0xFFFFFF, alpha: 0.04)

    // Monochrome controls
    static let buttonPrimaryTop = dynamic(light: 0x3A3A3E, dark: 0xF2F2F5)
    static let buttonPrimaryBottom = dynamic(light: 0x1D1D20, dark: 0xC4C4CA)
    static let buttonPrimaryForeground = dynamic(light: 0xFFFFFF, dark: 0x111114)
    static let switchKnob = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let hoverHighlight = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, alpha: 0.12)

    // Glass mode text — stronger than the window tertiary/secondary values so
    // text stays legible on the translucent, colourful panel backdrop.
    static let glassTextPrimary = dynamic(light: 0x141418, dark: 0xF7F7FA)
    static let glassTextSecondary = dynamic(light: 0x3D3D45, dark: 0xC7C7CE)
    static let glassTextTertiary = dynamic(light: 0x565660, dark: 0xA5A5AD)

    // Brand (monochrome graphite/silver, no colour wash)
    static let brandGreen = Color(hex: 0xC7C7CC)
    static let brandGreenDark = Color(hex: 0x6E6E74)
    static let logoTop = dynamic(light: 0x5A5A60, dark: 0xD8D8DD)
    static let logoBottom = dynamic(light: 0x26262A, dark: 0x86868C)

    // Background composition
    static var background: some View {
        ZStack {
            LinearGradient(
                colors: [windowTop, windowBottom],
                startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [accent.opacity(0.045), .clear],
                center: .init(x: 0.02, y: 0.0),
                startRadius: 0, endRadius: 380)
            RadialGradient(
                colors: [Color.white.opacity(0.03), .clear],
                center: .init(x: 1.0, y: 1.0),
                startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha)
    }
}

private func dynamic(light: UInt32, dark: UInt32, alpha: Double = 1) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(srgbRed: red(isDark ? dark : light),
                       green: green(isDark ? dark : light),
                       blue: blue(isDark ? dark : light),
                       alpha: alpha)
    })
}

private func red(_ value: UInt32) -> CGFloat { CGFloat((value >> 16) & 0xFF) / 255 }
private func green(_ value: UInt32) -> CGFloat { CGFloat((value >> 8) & 0xFF) / 255 }
private func blue(_ value: UInt32) -> CGFloat { CGFloat(value & 0xFF) / 255 }

// MARK: - Typography

extension Font {
    static let hubWindowTitle = Font.system(size: 22, weight: .bold)
    static let hubWindowSubtitle = Font.system(size: 12, weight: .regular)
    static let hubCardTitle = Font.system(size: 15, weight: .semibold)
    static let hubCardSubtitle = Font.system(size: 11.5, weight: .regular)
    static let hubRowTitle = Font.system(size: 13.5, weight: .medium)
    static let hubRowSubtitle = Font.system(size: 11.5, weight: .regular)
    static let hubBody = Font.system(size: 12.5, weight: .regular)
    static let hubCaption = Font.system(size: 11, weight: .regular)
    static let hubSectionLabel = Font.system(size: 10.5, weight: .semibold)
    static let hubTabLabel = Font.system(size: 12, weight: .semibold)
    static let hubButton = Font.system(size: 12.5, weight: .semibold)
    static let hubMono = Font.system(size: 11.5, design: .monospaced)
}

// MARK: - Metrics

enum HubMetric {
    static let cardRadius: CGFloat = 14
    static let rowRadius: CGFloat = 10
    static let cardPadding: CGFloat = 15
    static let rowPaddingH: CGFloat = 13
    static let rowPaddingV: CGFloat = 11
    static let cardGap: CGFloat = 10
    static let sectionGap: CGFloat = 18
    static let pagePadding: CGFloat = 20
    static let windowWidth: CGFloat = 480
    static let windowHeight: CGFloat = 800
    static let minWindowWidth: CGFloat = 440
    static let minWindowHeight: CGFloat = 640
}

// MARK: - Glass mode

/// Set for surfaces that sit on top of the menu-bar panel's `NSVisualEffectView`
/// backdrop. Windows leave it off, so their opaque cards are unchanged.
private struct HubGlassModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var hubGlassMode: Bool {
        get { self[HubGlassModeKey.self] }
        set { self[HubGlassModeKey.self] = newValue }
    }
}

/// Liquid Glass surface helper with a pre-26 fallback.
///
/// The panel uses this for every layered surface (cards, tab bars, search
/// fields). On macOS 26+ SwiftUI draws real Liquid Glass; on older systems a
/// thin material plus a stroke is the closest stable rendering. Text and
/// strokes stay semantic (`HubColor`), so both light and dark appearances work.
extension View {
    @ViewBuilder
    func hubGlassSurface(
        cornerRadius: CGFloat = HubMetric.cardRadius,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            let glass: Glass =
                tint.map { Glass.regular.tint($0.opacity(0.12)) } ?? .regular
            self
                .glassEffect(interactive ? glass.interactive() : glass, in: shape)
                .overlay(
                    shape.strokeBorder(HubColor.stroke, lineWidth: 1)
                )
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape.strokeBorder(HubColor.stroke, lineWidth: 1)
                )
        }
    }
}

// MARK: - Snapshot mode

/// `ImageRenderer` does not lay out `ScrollView` content. In snapshot mode the
/// page renders its content directly at full height so visual review is faithful.
private struct HubSnapshotModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var hubSnapshotMode: Bool {
        get { self[HubSnapshotModeKey.self] }
        set { self[HubSnapshotModeKey.self] = newValue }
    }
}

/// Lets feature views expose deterministic states to the snapshot renderer
/// without hard-coding a renderer import into the feature.
private struct HubPreviewScenarioKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var hubPreviewScenario: String? {
        get { self[HubPreviewScenarioKey.self] }
        set { self[HubPreviewScenarioKey.self] = newValue }
    }
}
