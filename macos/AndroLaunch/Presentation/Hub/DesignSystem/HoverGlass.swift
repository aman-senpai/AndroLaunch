//
//  HoverGlass.swift
//  AndroLaunch
//
//  Reusable hover treatment for the monochrome glass surfaces: a small spring
//  scale, a Liquid Glass highlight (interactive `glassEffect` on macOS 26+,
//  thin-material fallback) and an optional lift shadow. Reduce Motion is
//  respected — hover still highlights, it just does not scale.
//
//  The glass backdrops use concrete shapes (rounded rectangle / capsule)
//  because SwiftUI's availability + generic-Shape combination currently trips a
//  compiler diagnostic in this project.
//

import SwiftUI

// MARK: - Backdrops

private struct RoundedHoverGlassBackdrop: View {
    let cornerRadius: CGFloat
    let isActive: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if isActive {
                if #available(macOS 26.0, *) {
                    shape
                        .fill(Color.clear)
                        .glassEffect(.regular.interactive(), in: shape)
                } else {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay(
                            shape.strokeBorder(HubColor.hoverHighlight, lineWidth: 1))
                }
            }
        }
    }
}

private struct CapsuleHoverGlassBackdrop: View {
    let isActive: Bool

    var body: some View {
        let shape = Capsule()
        Group {
            if isActive {
                if #available(macOS 26.0, *) {
                    shape
                        .fill(Color.clear)
                        .glassEffect(.regular.interactive(), in: shape)
                } else {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay(
                            shape.strokeBorder(HubColor.hoverHighlight, lineWidth: 1))
                }
            }
        }
    }
}

private struct ShapeHoverGlassBackdrop: View {
    let shape: AnyShape
    let isActive: Bool

    var body: some View {
        if isActive {
            Rectangle()
                .fill(.ultraThinMaterial)
                .clipShape(shape)
                .overlay(
                    shape.stroke(HubColor.hoverHighlight, lineWidth: 1))
        }
    }
}

// MARK: - Modifiers

private struct RoundedHoverGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var enabled: Bool
    var hoverScale: CGFloat
    var liftShadow: Bool

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isActive: Bool { enabled && isHovering }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                RoundedHoverGlassBackdrop(
                    cornerRadius: cornerRadius, isActive: isActive)
            }
            .contentShape(shape)
            .scaleEffect(isActive && !reduceMotion ? hoverScale : 1)
            .shadow(
                color: .black.opacity(isActive && liftShadow ? 0.22 : 0),
                radius: isActive && liftShadow ? 12 : 0,
                y: isActive && liftShadow ? 4 : 0)
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.28, dampingFraction: 0.82),
                value: isActive)
            .onHover { isHovering = $0 }
    }
}

private struct CapsuleHoverGlassModifier: ViewModifier {
    var enabled: Bool
    var hoverScale: CGFloat
    var liftShadow: Bool

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isActive: Bool { enabled && isHovering }

    func body(content: Content) -> some View {
        content
            .background {
                CapsuleHoverGlassBackdrop(isActive: isActive)
            }
            .contentShape(Capsule())
            .scaleEffect(isActive && !reduceMotion ? hoverScale : 1)
            .shadow(
                color: .black.opacity(isActive && liftShadow ? 0.22 : 0),
                radius: isActive && liftShadow ? 12 : 0,
                y: isActive && liftShadow ? 4 : 0)
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.28, dampingFraction: 0.82),
                value: isActive)
            .onHover { isHovering = $0 }
    }
}

private struct ShapeHoverGlassModifier: ViewModifier {
    var shape: AnyShape
    var enabled: Bool
    var hoverScale: CGFloat
    var liftShadow: Bool

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isActive: Bool { enabled && isHovering }

    func body(content: Content) -> some View {
        content
            .background {
                ShapeHoverGlassBackdrop(shape: shape, isActive: isActive)
            }
            .contentShape(shape)
            .scaleEffect(isActive && !reduceMotion ? hoverScale : 1)
            .shadow(
                color: .black.opacity(isActive && liftShadow ? 0.22 : 0),
                radius: isActive && liftShadow ? 12 : 0,
                y: isActive && liftShadow ? 4 : 0)
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.28, dampingFraction: 0.82),
                value: isActive)
            .onHover { isHovering = $0 }
    }
}

// MARK: - Public API

extension View {
    /// Arbitrary-shape hover glass (material fallback; used by call sites that
    /// pass a pre-built shape).
    func hoverGlass(
        shape: AnyShape,
        enabled: Bool = true,
        scale: CGFloat = 1.015,
        liftShadow: Bool = true
    ) -> some View {
        modifier(
            ShapeHoverGlassModifier(
                shape: shape,
                enabled: enabled,
                hoverScale: scale,
                liftShadow: liftShadow))
    }

    /// Rounded-rectangle hover glass.
    func hoverGlass(
        cornerRadius: CGFloat = HubMetric.rowRadius,
        enabled: Bool = true,
        scale: CGFloat = 1.015,
        liftShadow: Bool = true
    ) -> some View {
        modifier(
            RoundedHoverGlassModifier(
                cornerRadius: cornerRadius,
                enabled: enabled,
                hoverScale: scale,
                liftShadow: liftShadow))
    }

    /// Capsule hover glass for buttons and pills.
    func hoverGlassCapsule(
        enabled: Bool = true,
        scale: CGFloat = 1.02,
        liftShadow: Bool = true
    ) -> some View {
        modifier(
            CapsuleHoverGlassModifier(
                enabled: enabled,
                hoverScale: scale,
                liftShadow: liftShadow))
    }
}
