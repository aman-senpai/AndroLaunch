//
//  HubComponents.swift
//  AndroLaunch
//
//  Shared components used by every Hub screen. Keep these small,
//  semantic and content-first: a card is a surface, not decoration.
//

import AppKit
import SwiftUI

// MARK: - Surfaces

struct HubCard<Content: View>: View {
    var padding: CGFloat = HubMetric.cardPadding
    var elevated: Bool = false
    var tint: Color? = nil
    /// Cards that behave like a single control opt into the hover lift + glass
    /// highlight. Informational cards stay calm.
    var interactive: Bool = false
    @ViewBuilder var content: () -> Content

    @Environment(\.hubGlassMode) private var glassMode

    var body: some View {
        if glassMode {
            content()
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hubGlassSurface(cornerRadius: HubMetric.cardRadius, tint: tint)
                .hoverGlass(
                    cornerRadius: HubMetric.cardRadius,
                    enabled: interactive,
                    scale: 1.006)
        } else {
            content()
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: HubMetric.cardRadius, style: .continuous)
                        .fill(elevated ? HubColor.cardElevated : HubColor.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: HubMetric.cardRadius, style: .continuous)
                                .fill((tint ?? .clear).opacity(tint == nil ? 0 : 0.045)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: HubMetric.cardRadius, style: .continuous)
                        .strokeBorder(HubColor.stroke, lineWidth: 1))
        }
    }
}

struct HubSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.hubGlassMode) private var glassMode

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .font(.hubSectionLabel)
                .tracking(0.9)
                .foregroundStyle(
                    glassMode ? HubColor.glassTextSecondary : HubColor.textTertiary)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.leading, 2)
    }
}

struct HubDivider: View {
    var body: some View {
        Rectangle()
            .fill(HubColor.stroke)
            .frame(height: 1)
            .padding(.leading, 44)
    }
}

// MARK: - Icons & badges

struct HubIconTile: View {
    let systemName: String
    var tint: Color = HubColor.accent
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(tint.opacity(0.16))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.47, weight: .semibold))
                    .foregroundStyle(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(tint.opacity(0.13), lineWidth: 1))
    }
}

struct HubLogoMark: View {
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                    .fill(LinearGradient(
                        colors: [HubColor.logoTop, HubColor.logoBottom],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: size * 0.47, weight: .semibold))
                            .foregroundStyle(
                                Color(nsColor: NSColor(name: nil) { appearance in
                                    let dark = appearance.bestMatch(
                                        from: [.darkAqua, .aqua]) == .darkAqua
                                    return dark
                                        ? NSColor.black.withAlphaComponent(0.72)
                                        : NSColor.white
                                })))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.29, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .strokeBorder(HubColor.strokeStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        .accessibilityLabel("AndroLaunch")
    }
}

struct HubPill: View {
    let text: String
    var tint: Color = HubColor.textSecondary
    var filled: Bool = false
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(filled ? Color.black.opacity(0.82) : tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(filled ? tint : tint.opacity(0.14)))
    }
}

struct HubStatusDot: View {
    var color: Color = HubColor.success
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.7), radius: 3)
    }
}

// MARK: - Rows

struct HubRowButton<Content: View>: View {
    var action: (() -> Void)?
    @ViewBuilder var content: () -> Content
    @State private var hovering = false
    @Environment(\.hubGlassMode) private var glassMode

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content() }
                    .buttonStyle(.plain)
            } else {
                content()
            }
        }
        .padding(.horizontal, HubMetric.rowPaddingH)
        .padding(.vertical, HubMetric.rowPaddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            if !glassMode {
                RoundedRectangle(cornerRadius: HubMetric.rowRadius, style: .continuous)
                    .fill(hovering && action != nil ? HubColor.cardHover.opacity(0.7) : .clear)
            }
        }
        .hoverGlass(
            cornerRadius: HubMetric.rowRadius,
            enabled: glassMode && action != nil,
            scale: 1.004,
            liftShadow: false)
        .onHover { hovering = $0 }
    }
}

struct HubChevronRow: View {
    let icon: String
    var iconTint: Color = HubColor.accent
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var valueTint: Color = HubColor.textSecondary
    var badge: String? = nil
    var badgeTint: Color = HubColor.accent
    var disabled: Bool = false
    var action: (() -> Void)?

    var body: some View {
        HubRowButton(action: disabled ? nil : action) {
            HStack(spacing: 11) {
                HubIconTile(systemName: icon, tint: disabled ? HubColor.textTertiary : iconTint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.hubRowTitle)
                        .foregroundStyle(disabled ? HubColor.textTertiary : HubColor.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.hubRowSubtitle)
                            .foregroundStyle(HubColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                if let badge {
                    HubPill(text: badge, tint: badgeTint)
                }
                if let value {
                    Text(value)
                        .font(.hubCaption)
                        .foregroundStyle(valueTint)
                        .multilineTextAlignment(.trailing)
                }
                if action != nil && !disabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(HubColor.textTertiary)
                }
            }
        }
        .opacity(disabled ? 0.72 : 1)
    }
}

struct HubToggleRow: View {
    let icon: String
    var iconTint: Color = HubColor.accent
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        HStack(spacing: 11) {
            HubIconTile(systemName: icon, tint: disabled ? HubColor.textTertiary : iconTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.hubRowTitle)
                    .foregroundStyle(disabled ? HubColor.textTertiary : HubColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.hubRowSubtitle)
                        .foregroundStyle(HubColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 10)
            HubSwitch(isOn: $isOn, disabled: disabled)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, HubMetric.rowPaddingH)
        .padding(.vertical, HubMetric.rowPaddingV)
    }
}

/// Drawn switch used instead of the native control.
///
/// Two reasons: it matches the reference product's compact switch at this row
/// height, and `ImageRenderer` can rasterise it (AppKit-backed `Toggle` controls
/// render as placeholder blocks in the snapshot pipeline).
struct HubSwitch: View {
    @Binding var isOn: Bool
    var disabled: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            guard !disabled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? HubColor.accent : HubColor.strokeStrong.opacity(disabled ? 0.4 : 1))
                    .frame(width: 34, height: 20)
                    .overlay(
                        Capsule().strokeBorder(
                            isOn ? Color.white.opacity(0.16) : HubColor.stroke,
                            lineWidth: 1))
                Circle()
                    .fill(HubColor.switchKnob.opacity(disabled ? 0.7 : 1))
                    .frame(width: 16, height: 16)
                    .padding(2)
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 0.5)
            }
            .opacity(disabled ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

struct HubValueRow: View {
    let title: String
    var value: String
    var valueTint: Color = HubColor.textSecondary
    @Environment(\.hubGlassMode) private var glassMode

    var body: some View {
        HStack {
            Text(title)
                .font(.hubBody)
                .foregroundStyle(
                    glassMode ? HubColor.glassTextSecondary : HubColor.textSecondary)
            Spacer()
            Text(value)
                .font(.hubBody)
                .foregroundStyle(
                    glassMode ? HubColor.glassTextSecondary : valueTint)
                .textSelection(.enabled)
        }
        .padding(.horizontal, HubMetric.rowPaddingH)
        .padding(.vertical, 7)
    }
}

// MARK: - Controls

enum HubButtonStyleKind {
    case primary, secondary, quiet, destructive
}

struct HubActionButton: View {
    let title: String
    var icon: String? = nil
    var style: HubButtonStyleKind = .primary
    var fullWidth: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                }
                Text(title).font(.hubButton)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(background)
            .overlay(
                Capsule().strokeBorder(border, lineWidth: 1))
            .clipShape(Capsule())
            .hoverGlassCapsule(enabled: enabled, scale: 1.02)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    private var foreground: Color {
        switch style {
        case .primary: return HubColor.buttonPrimaryForeground
        case .secondary: return HubColor.textPrimary
        case .quiet: return HubColor.accent
        case .destructive: return HubColor.danger
        }
    }

    private var background: AnyShapeStyle {
        switch style {
        case .primary:
            return AnyShapeStyle(LinearGradient(
                colors: [HubColor.buttonPrimaryTop, HubColor.buttonPrimaryBottom],
                startPoint: .top, endPoint: .bottom))
        case .secondary: return AnyShapeStyle(HubColor.cardElevated)
        case .quiet: return AnyShapeStyle(HubColor.accentSoft)
        case .destructive: return AnyShapeStyle(HubColor.dangerSoft)
        }
    }

    private var border: Color {
        switch style {
        case .primary: return Color.white.opacity(0.14)
        case .secondary: return HubColor.strokeStrong
        case .quiet: return HubColor.accent.opacity(0.22)
        case .destructive: return HubColor.danger.opacity(0.24)
        }
    }
}

struct HubSegmentedTabs<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        let title: String
        let icon: String?
        var id: Value { value }
    }

    let items: [Item]
    @Binding var selection: Value
    var compact: Bool = false

    @Environment(\.hubGlassMode) private var glassMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let selected = item.value == selection
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                        selection = item.value
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let icon = item.icon {
                            Image(systemName: icon)
                                .font(.system(size: compact ? 9.5 : 10.5, weight: .semibold))
                        }
                        Text(item.title)
                            .font(compact ? .system(size: 11, weight: .semibold) : .hubTabLabel)
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected ? HubColor.textPrimary : HubColor.textSecondary)
                    .padding(.horizontal, compact ? 8 : 10)
                    .padding(.vertical, compact ? 5 : 7)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous)
                            .fill(selected ? HubColor.cardElevated : .clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous)
                                    .strokeBorder(selected ? HubColor.strokeStrong : .clear, lineWidth: 1)))
                    .hoverGlass(
                        cornerRadius: compact ? 6 : 8,
                        enabled: true,
                        scale: 1.02,
                        liftShadow: false)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            if glassMode {
                RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                    .fill(Color.clear)
                    .hubGlassSurface(cornerRadius: compact ? 8 : 10)
            } else {
                RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                    .fill(HubColor.windowTop.opacity(0.65))
            }
        }
        .overlay {
            if !glassMode {
                RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                    .strokeBorder(HubColor.stroke, lineWidth: 1)
            }
        }
    }
}

struct HubProgressBar: View {
    var value: Double
    var tint: Color = HubColor.accent
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(HubColor.controlTrack)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.29), value: value)
    }
}

struct HubSearchField: View {
    @Binding var text: String
    var placeholder: String

    @Environment(\.hubGlassMode) private var glassMode

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HubColor.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.hubBody)
                .foregroundStyle(HubColor.textPrimary)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(HubColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            if glassMode {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.clear)
                    .hubGlassSurface(cornerRadius: 8)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(HubColor.cardElevated)
            }
        }
        .overlay {
            if !glassMode {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(HubColor.stroke, lineWidth: 1)
            }
        }
    }
}

// MARK: - Layout helpers

struct HubPage<Content: View>: View {
    var topPadding: CGFloat = 16
    @Environment(\.hubSnapshotMode) private var snapshotMode
    @ViewBuilder var content: () -> Content

    var body: some View {
        if snapshotMode {
            page
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                page
            }
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: HubMetric.sectionGap) {
            content()
        }
        .padding(.horizontal, HubMetric.pagePadding)
        .padding(.top, topPadding)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HubNote: View {
    let text: String
    var icon: String? = nil
    @Environment(\.hubGlassMode) private var glassMode

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(HubColor.textTertiary)
                    .padding(.top, 1)
            }
            Text(text)
                .font(.hubCaption)
                .foregroundStyle(
                    glassMode ? HubColor.glassTextSecondary : HubColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }
}

struct HubEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(HubColor.textTertiary)
            Text(title)
                .font(.hubRowTitle)
                .foregroundStyle(HubColor.textSecondary)
            if let subtitle {
                Text(subtitle)
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
    }
}

struct HubStubBadge: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(HubColor.warning)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(HubColor.warningSoft))
    }
}
