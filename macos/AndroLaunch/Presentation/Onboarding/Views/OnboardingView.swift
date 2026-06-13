//
//  OnboardingView.swift
//  AndroLaunch
//

import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        Group {
            switch viewModel.currentPhase {
            case .welcome:
                WelcomePage(viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97)),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

            case .dependencyCheck:
                DependencyCheckPage(viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

            case .completion:
                CompletionPage(viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: viewModel.currentPhase)
        .frame(width: 420, height: 480)
        .opacity(viewModel.isDismissing ? 0.0 : 1.0)
        .scaleEffect(viewModel.isDismissing ? 0.95 : 1.0)
        .animation(.easeOut(duration: 0.25), value: viewModel.isDismissing)
    }
}
