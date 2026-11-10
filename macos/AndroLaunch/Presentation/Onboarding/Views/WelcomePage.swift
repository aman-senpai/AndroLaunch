//
//  WelcomePage.swift
//  AndroLaunch
//
//  First-run welcome, on the Hub design system. The window is 620×600
//  (AppDelegate-owned) and the layout stays comfortable when the user resizes it:
//  content is capped at 560 pt and scrolls if the window gets shorter.
//

import SwiftUI

struct WelcomePage: View {
    var onConnect: () -> Void
    var onOpenApp: () -> Void

    /// `ImageRenderer` cannot lay out `ScrollView` content, so the design
    /// snapshot renderer asks pages for their direct content instead.
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
        VStack(spacing: 20) {
            hero
            steps
            features
            actions
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 30)
        .padding(.top, 30)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 12) {
            HubLogoMark(size: 58)
            VStack(spacing: 6) {
                Text(OnboardingCopy.heroTitle)
                    .font(.hubWindowTitle)
                    .foregroundStyle(HubColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(OnboardingCopy.heroBody)
                    .font(.hubBody)
                    .foregroundStyle(HubColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2.5)
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Steps

    private var steps: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(OnboardingCopy.steps) { step in
                HubCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 7) {
                            HubIconTile(systemName: step.icon, size: 26)
                            Spacer(minLength: 4)
                            Text("\(step.index)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(HubColor.textTertiary)
                                .monospacedDigit()
                        }
                        Text(step.title)
                            .font(.hubRowTitle)
                            .foregroundStyle(HubColor.textPrimary)
                        Text(step.detail)
                            .font(.hubCaption)
                            .foregroundStyle(HubColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: Features

    private var features: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader("Included")
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10
            ) {
                ForEach(OnboardingCopy.features) { feature in
                    HubCard(padding: 11) {
                        HStack(spacing: 10) {
                            HubIconTile(systemName: feature.icon, size: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title)
                                    .font(.hubRowTitle)
                                    .foregroundStyle(HubColor.textPrimary)
                                Text(feature.detail)
                                    .font(.hubCaption)
                                    .foregroundStyle(HubColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
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
            HubNote(text: OnboardingCopy.localNote, icon: "lock.fill")
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
        .padding(.top, 2)
    }
}
