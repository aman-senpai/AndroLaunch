//
//  CallBannerView.swift
//  AndroLaunch
//
//  The banner's content: caller device, state, the two honest actions, and the
//  "audio stays on your phone" line that keeps the feature from over-promising.
//
//  Built entirely from the Hub design system so it matches the app, with 44 pt
//  hit areas, labels on icon-only controls, and no motion when Reduce Motion is on.
//

import AppKit
import SwiftUI

struct CallBannerView: View {
    @ObservedObject var model: CallBannerModel
    @ObservedObject private var center = CallCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let snapshot = model.snapshot {
            content(snapshot)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: HubMetric.cardRadius, style: .continuous)
                        .fill(HubColor.card)
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: HubMetric.cardRadius, style: .continuous
                            )
                            .fill(tint(for: snapshot).opacity(0.05)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: HubMetric.cardRadius, style: .continuous)
                        .strokeBorder(tint(for: snapshot).opacity(0.35), lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    closeButton
                        .padding(.top, 6)
                        .padding(.trailing, 6)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(snapshot.titleText) from \(snapshot.deviceName)")
        } else {
            Color.clear
        }
    }

    // MARK: - Content

    private func content(_ snapshot: CallCenter.Snapshot) -> some View {
        HStack(alignment: .center, spacing: 12) {
            statusIcon(snapshot)
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.titleText)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(HubColor.textPrimary)
                Text(snapshot.deviceName)
                    .font(.system(size: 11.5))
                    .foregroundStyle(HubColor.textSecondary)
                    .lineLimit(1)
                Text(
                    "Audio stays on your phone."
                )
                .font(.system(size: 10.5))
                .foregroundStyle(HubColor.textTertiary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            actions(snapshot)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
    }

    private func statusIcon(_ snapshot: CallCenter.Snapshot) -> some View {
        ZStack {
            Circle()
                .fill(tint(for: snapshot).opacity(0.16))
                .frame(width: 46, height: 46)
            Image(systemName: snapshot.isRinging ? "phone.arrow.up.right.fill" : "phone.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint(for: snapshot))
        }
        .opacity(snapshot.isRinging && !reduceMotion ? 1 : 1)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func actions(_ snapshot: CallCenter.Snapshot) -> some View {
        if snapshot.isRinging {
            VStack(spacing: 7) {
                bannerButton(
                    title: "Answer", icon: "phone.fill",
                    foreground: .white,
                    background: AnyShapeStyle(HubColor.success),
                    help: answerHelp(snapshot),
                    enabled: snapshot.controlAvailable
                ) {
                    center.answer()
                }
                bannerButton(
                    title: "Decline", icon: "phone.down.fill",
                    foreground: HubColor.danger,
                    background: AnyShapeStyle(HubColor.dangerSoft),
                    help: "Declines the call on the phone.",
                    enabled: snapshot.controlAvailable
                ) {
                    center.decline()
                }
            }
        } else {
            bannerButton(
                title: "End call", icon: "phone.down.fill",
                foreground: HubColor.danger,
                background: AnyShapeStyle(HubColor.dangerSoft),
                help: "Ends the call on the phone. Audio stays on the phone.",
                enabled: snapshot.controlAvailable
            ) {
                center.decline()
            }
        }
    }

    private func bannerButton(
        title: String,
        icon: String,
        foreground: Color,
        background: AnyShapeStyle,
        help: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .frame(width: 94, height: 28)
            .background(
                Capsule().fill(background)
            )
            .overlay(Capsule().strokeBorder(foreground.opacity(0.18), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(height: 30)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .help(help)
        .accessibilityLabel(title)
    }

    private var closeButton: some View {
        Button {
            CallBannerController.shared.dismissBanner()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(HubColor.textTertiary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(HubColor.cardElevated))
        }
        .buttonStyle(.plain)
        .help("Hide this banner. The call is not affected.")
        .accessibilityLabel("Hide call banner")
    }

    private func answerHelp(_ snapshot: CallCenter.Snapshot) -> String {
        snapshot.controlAvailable
            ? "Answers the call on your phone. Audio stays on your phone."
            : "Allow call control in AndroLaunch Comp on the phone (Calls → Allow call control)."
    }

    private func tint(for snapshot: CallCenter.Snapshot) -> Color {
        if snapshot.isRinging {
            return snapshot.incoming ? HubColor.success : HubColor.warning
        }
        return HubColor.accent
    }
}
