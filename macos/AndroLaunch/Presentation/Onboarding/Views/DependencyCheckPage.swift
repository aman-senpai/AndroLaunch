//
//  DependencyCheckPage.swift
//  AndroLaunch
//
//  First-run dependency setup, restyled on the Hub design system. The flow is
//  unchanged from before: detect adb/scrcpy, offer a Homebrew install, allow a
//  skip, and continue when both are resolved.
//

import SwiftUI

struct DependencyCheckPage: View {
    let adbStatus: DependencyStatus
    let scrcpyStatus: DependencyStatus
    let homebrewAvailable: Bool
    let canProceed: Bool
    let actions: OnboardingDependencyActions

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
            cards
            if !homebrewAvailable { homebrewNote }
            HubNote(
                text:
                    "Both tools are free and open source. They run on this Mac; nothing is uploaded anywhere.",
                icon: "lock.fill")
            actionsView
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 30)
        .padding(.top, 30)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 11) {
            HubLogoMark(size: 40)
            VStack(spacing: 5) {
                Text(OnboardingCopy.setupTitle)
                    .font(.hubWindowTitle)
                    .foregroundStyle(HubColor.textPrimary)
                Text(OnboardingCopy.setupBody)
                    .font(.hubBody)
                    .foregroundStyle(HubColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Cards

    private var cards: some View {
        VStack(spacing: 10) {
            DependencySetupCard(
                title: "ADB (Android Debug Bridge)",
                detail: "Talks to your phone over USB or Wi-Fi.",
                icon: "terminal.fill",
                status: adbStatus,
                installTitle: "Install with Homebrew",
                installEnabled: homebrewAvailable,
                onInstall: actions.installADB,
                onSkip: actions.skipADB)

            DependencySetupCard(
                title: "scrcpy (Screen Copy)",
                detail: "Powers screen mirroring, camera preview and app windows.",
                icon: "display",
                status: scrcpyStatus,
                installTitle: "Install with Homebrew",
                installEnabled: homebrewAvailable,
                onInstall: actions.installScrcpy,
                onSkip: actions.skipScrcpy)
        }
    }

    private var homebrewNote: some View {
        HubNote(
            text:
                "Homebrew isn't installed. Install it from brew.sh, then reopen AndroLaunch to set these up automatically.",
            icon: "info.circle")
    }

    // MARK: Actions

    private var actionsView: some View {
        VStack(spacing: 9) {
            HubActionButton(
                title: "Continue",
                icon: "arrow.right",
                style: .primary,
                fullWidth: true,
                enabled: canProceed,
                action: actions.continueSetup)

            if !(adbStatus.onboardingIsReady && scrcpyStatus.onboardingIsReady) {
                HubActionButton(
                    title: "Skip for now",
                    style: .quiet,
                    action: actions.skipAll)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Card

private struct DependencySetupCard: View {
    let title: String
    let detail: String
    let icon: String
    let status: DependencyStatus
    let installTitle: String
    let installEnabled: Bool
    let onInstall: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HubCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 11) {
                    HubIconTile(systemName: icon, tint: tint, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.hubRowTitle)
                            .foregroundStyle(HubColor.textPrimary)
                        Text(detail)
                            .font(.hubRowSubtitle)
                            .foregroundStyle(HubColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    badge
                }

                if status.onboardingNeedsAction {
                    divider
                    HStack(spacing: 8) {
                        HubActionButton(
                            title: installTitle,
                            icon: "arrow.down.circle",
                            style: .secondary,
                            enabled: installEnabled,
                            action: onInstall)
                        HubActionButton(title: "Skip", style: .quiet, action: onSkip)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 10)
                }

                if let phase = status.onboardingInstallPhase {
                    divider
                    HStack(spacing: 9) {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                        Text(phase)
                            .font(.hubCaption)
                            .foregroundStyle(HubColor.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 10)
                }

                if let failure = status.onboardingFailureMessage {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(HubColor.warning)
                            .padding(.top, 1)
                        Text(failure)
                            .font(.hubCaption)
                            .foregroundStyle(HubColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(HubColor.stroke)
            .frame(height: 1)
            .padding(.top, 11)
    }

    @ViewBuilder
    private var badge: some View {
        switch status {
        case .checking:
            HStack(spacing: 5) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("Checking")
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textSecondary)
            }
        case .installing:
            HubPill(text: "Installing", tint: HubColor.accent, icon: "arrow.down.circle.fill")
        default:
            let badge = status.onboardingBadge
            HubPill(
                text: badge.text, tint: tintFor(tone: badge.tone),
                icon: status.onboardingIsReady ? "checkmark.circle.fill" : nil)
        }
    }

    private var tint: Color {
        if status.onboardingIsReady { return HubColor.success }
        switch status {
        case .checking, .installing: return HubColor.accent
        case .failed: return HubColor.danger
        default: return HubColor.warning
        }
    }

    private func tintFor(tone: String) -> Color {
        switch tone {
        case "success": return HubColor.success
        case "warning": return HubColor.warning
        case "danger": return HubColor.danger
        case "accent": return HubColor.accent
        default: return HubColor.textSecondary
        }
    }
}
