//
//  SettingsComponents.swift
//  AndroLaunch
//
//  Small Settings-specific rows built on the shared Hub design system. The
//  Settings screen is dense, so these add exactly what the shared rows
//  do not: inline requirement notes, a copyable command block, and action
//  strips for the camera card.
//

import SwiftUI

// MARK: - Switch

/// Custom capsule switch. The Hub's `HubToggleRow` uses a real AppKit `Toggle`,
/// which `ImageRenderer` draws as a placeholder instead of the control; this
/// switch renders identically in the live window and in the DEBUG snapshot
/// harness, and gives the Settings screen its own 44 pt target.
struct SettingsSwitch: View {
    @Binding var isOn: Bool
    var disabled: Bool = false
    var label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            guard !disabled else { return }
            isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? HubColor.accent : HubColor.cardElevated)
                .overlay(
                    Capsule().strokeBorder(
                        isOn ? HubColor.accent.opacity(0.35) : HubColor.strokeStrong,
                        lineWidth: 1))
                .frame(width: 34, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? Color.white : HubColor.textSecondary)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                        .padding(2)
                }
                .frame(width: 44, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
        .help(disabled ? "\(label) is unavailable" : "\(label): \(isOn ? "On" : "Off")")
    }
}

// MARK: - Toggle with requirement note

struct SettingsToggleRow: View {
    let icon: String
    var iconTint: Color = HubColor.accent
    let title: String
    var subtitle: String? = nil
    /// Shown below the row when the toggle is off for a platform reason, so a
    /// disabled switch always explains itself.
    var footnote: String? = nil
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                HubIconTile(
                    systemName: icon,
                    tint: disabled ? HubColor.textTertiary : iconTint)
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
                SettingsSwitch(isOn: $isOn, disabled: disabled, label: title)
            }
            .padding(.horizontal, HubMetric.rowPaddingH)
            .padding(.vertical, HubMetric.rowPaddingV)
            .opacity(disabled ? 0.72 : 1)

            if let footnote, !footnote.isEmpty {
                HubNote(text: footnote, icon: "info.circle")
                    .padding(.leading, 54)
                    .padding(.trailing, HubMetric.rowPaddingH)
                    .padding(.bottom, 10)
            }
        }
    }
}

// MARK: - Status row

/// Read-only status line used under a card's primary row (MCP server state,
/// camera extension state, login item state). Not a button.
struct SettingsStatusRow: View {
    @Environment(\.hubGlassMode) private var glassMode
    var dotColor: Color? = nil
    let title: String
    var value: String
    var valueTint: Color = HubColor.textSecondary

    var body: some View {
        HStack(spacing: 8) {
            if let dotColor {
                HubStatusDot(color: dotColor, size: 6)
            }
            Text(title)
                .font(.hubCaption)
                .foregroundStyle(
                    glassMode ? HubColor.glassTextSecondary : HubColor.textTertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(.hubCaption)
                .foregroundStyle(valueTint)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, HubMetric.rowPaddingH)
        .padding(.vertical, 6)
    }
}

// MARK: - Command block

/// The real executable command for an MCP client, with a copy affordance and a
/// visible "Copied" confirmation. Monospaced and selectable for manual copying.
struct SettingsCommandBlock: View {
    let label: String
    let command: String
    var isCopyConfirmed: Bool
    let copy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label)
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textTertiary)
                Spacer()
                Button(action: copy) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopyConfirmed ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text(isCopyConfirmed ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(isCopyConfirmed ? HubColor.textPrimary : HubColor.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            isCopyConfirmed
                                ? HubColor.cardElevated : HubColor.accentSoft))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy MCP command")
                .help("Copy the command an MCP client needs")
            }

            Text(command)
                .font(.hubMono)
                .foregroundStyle(HubColor.textPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(HubColor.windowTop.opacity(0.7)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(HubColor.stroke, lineWidth: 1))
                .accessibilityLabel("MCP command: \(command)")
        }
        .padding(.horizontal, HubMetric.rowPaddingH)
        .padding(.vertical, 9)
    }
}

// MARK: - Action strip

/// A row of compact actions inside a card (camera install/preview, MCP stop).
struct SettingsActionStrip: View {
    struct Action: Identifiable {
        let id = UUID()
        let title: String
        var icon: String? = nil
        var style: HubButtonStyleKind = .secondary
        var enabled: Bool = true
        let handler: () -> Void
    }

    let actions: [Action]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(actions) { action in
                HubActionButton(
                    title: action.title,
                    icon: action.icon,
                    style: action.style,
                    enabled: action.enabled,
                    action: action.handler)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HubMetric.rowPaddingH)
        .padding(.bottom, 10)
        .padding(.top, 2)
    }
}

// MARK: - Badge

/// Small state pill used in Settings headers and rows.
struct SettingsStatePill: View {
    let text: String
    var tint: Color = HubColor.textSecondary
    var filled: Bool = false

    var body: some View {
        HubPill(text: text, tint: tint, filled: filled)
    }
}

// MARK: - Empty state

struct SettingsEmptyNote: View {
    let icon: String
    let text: String
    @Environment(\.hubGlassMode) private var glassMode

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HubColor.textTertiary)
                .padding(.top, 1)
            Text(text)
                .font(.hubCaption)
                .foregroundStyle(
                    glassMode ? HubColor.glassTextSecondary : HubColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, HubMetric.rowPaddingH)
        .padding(.vertical, 9)
    }
}
