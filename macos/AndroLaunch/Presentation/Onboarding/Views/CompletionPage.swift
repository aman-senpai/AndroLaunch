//
//  CompletionPage.swift
//  AndroLaunch
//
//  Final onboarding step: what's ready, how to authorize the phone, and the two
//  completion paths (Connect your phone → Hub, or Open AndroLaunch).
//

import SwiftUI

struct CompletionPage: View {
    let summary: [OnboardingSummaryItem]
    let adbReady: Bool
    let onConnect: () -> Void
    let onOpenApp: () -> Void

    /// See `WelcomePage`: snapshot rendering bypasses the ScrollView wrapper.
    @Environment(\.hubSnapshotMode) private var snapshotMode

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
        VStack(spacing: 18) {
            header
            summaryCard
            connectCard
            actionsView
            HubNote(
                text: "You can change every connection later in the Hub. The menu bar icon stays available for one-click actions.",
                icon: "menubar.rectangle")
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(HubColor.successSoft)
                    .frame(width: 62, height: 62)
                Circle()
                    .strokeBorder(HubColor.success.opacity(0.28), lineWidth: 1)
                    .frame(width: 62, height: 62)
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(HubColor.success)
            }
            VStack(spacing: 5) {
                Text(OnboardingCopy.completionTitle)
                    .font(.hubWindowTitle)
                    .foregroundStyle(HubColor.textPrimary)
                Text(
                    adbReady
                        ? "AndroLaunch can reach your phone. Authorize it once, then everything else is one click away."
                        : "Setup is incomplete. You can install ADB later from Settings; device actions need it."
                )
                .font(.hubBody)
                .foregroundStyle(HubColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Summary

    private var summaryCard: some View {
        HubCard {
            VStack(spacing: 0) {
                if summary.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(HubColor.textTertiary)
                        Text("Dependencies were skipped. You can install them later in Settings.")
                            .font(.hubRowSubtitle)
                            .foregroundStyle(HubColor.textSecondary)
                        Spacer(minLength: 0)
                    }
                }
                ForEach(Array(summary.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 9) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(
                                item.isSuccess ? HubColor.success : HubColor.warning)
                            .frame(width: 16)
                        Text(item.text)
                            .font(.hubRowSubtitle)
                            .foregroundStyle(HubColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7)
                    if index < summary.count - 1 {
                        Rectangle()
                            .fill(HubColor.stroke)
                            .frame(height: 1)
                            .padding(.leading, 25)
                    }
                }
            }
        }
    }

    // MARK: Connect instructions

    private var connectCard: some View {
        HubCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Connect your Android phone")
                    .font(.hubCardTitle)
                    .foregroundStyle(HubColor.textPrimary)
                instructionRow(
                    number: 1,
                    text: "Enable Developer options and USB debugging on Android.")
                instructionRow(
                    number: 2,
                    text:
                        "Connect a data cable, unlock the phone and approve “Allow USB debugging?” for this Mac.")
                instructionRow(
                    number: 3,
                    text:
                        "Open the Hub: the device appears by name, ready to browse files, mirror or open apps.")
            }
        }
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(HubColor.accent)
                .frame(width: 16, height: 16)
                .background(Circle().fill(HubColor.accentSoft))
            Text(text)
                .font(.hubRowSubtitle)
                .foregroundStyle(HubColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: Actions

    private var actionsView: some View {
        VStack(spacing: 9) {
            HubActionButton(
                title: "Connect your Android phone",
                icon: "cable.connector",
                style: .primary,
                fullWidth: true,
                action: onConnect)
            HubActionButton(
                title: "Open AndroLaunch",
                icon: "macwindow",
                style: .secondary,
                fullWidth: true,
                action: onOpenApp)
        }
    }
}
