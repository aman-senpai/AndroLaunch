//
//  OnboardingView.swift
//  AndroLaunch
//
//  First-run shell. Maps the existing `OnboardingViewModel` (dependency detection,
//  Homebrew installs, completion) onto the redesigned pages. Completion
//  and window dismissal stay owned by AppDelegate.
//

import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            HubColor.background
            content
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(viewModel.isDismissing ? 0 : 1)
        .scaleEffect(viewModel.isDismissing && !reduceMotion ? 0.98 : 1)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.25), value: viewModel.isDismissing)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.22), value: viewModel.currentPhase)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.currentPhase {
        case .welcome:
            WelcomePage(
                onConnect: { viewModel.proceedToDependencyCheck() },
                onOpenApp: { viewModel.completeOnboarding() })

        case .dependencyCheck:
            DependencyCheckPage(
                adbStatus: viewModel.adbStatus,
                scrcpyStatus: viewModel.scrcpyStatus,
                homebrewAvailable: viewModel.isHomebrewAvailable,
                canProceed: viewModel.canProceedFromDependencyCheck,
                actions: OnboardingDependencyActions(
                    installADB: { viewModel.installADB() },
                    installScrcpy: { viewModel.installScrcpy() },
                    skipADB: { viewModel.skipADBInstallation() },
                    skipScrcpy: { viewModel.skipScrcpyInstallation() },
                    continueSetup: { viewModel.goToCompletion() },
                    skipAll: { skipAllSetup() }))

        case .completion:
            CompletionPage(
                summary: viewModel.summaryItems.map {
                    OnboardingSummaryItem(
                        icon: $0.icon, text: $0.text, isSuccess: $0.success)
                },
                adbReady: viewModel.adbStatus.isInstalled,
                onConnect: { viewModel.completeOnboarding() },
                onOpenApp: { viewModel.completeOnboarding() })
        }
    }

    private func skipAllSetup() {
        if !viewModel.adbStatus.isResolved { viewModel.skipADBInstallation() }
        if !viewModel.scrcpyStatus.isResolved { viewModel.skipScrcpyInstallation() }
        viewModel.goToCompletion()
    }
}
