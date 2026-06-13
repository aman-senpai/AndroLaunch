//
//  WelcomePage.swift
//  AndroLaunch
//

import SwiftUI

struct WelcomePage: View {
    @ObservedObject var viewModel: OnboardingViewModel

    @State private var showIcon = false
    @State private var showTitle = false
    @State private var showBody = false
    @State private var showButton = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App Icon from menu bar asset
            Image("MenuIcons")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
            .scaleEffect(showIcon ? 1.0 : 0.6)
            .opacity(showIcon ? 1.0 : 0.0)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showIcon)

            Spacer().frame(height: 28)

            // Title
            Text("Welcome to AndroLaunch")
                .font(.system(size: 22, weight: .semibold, design: .default))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .offset(y: showTitle ? 0 : 6)
                .opacity(showTitle ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.4), value: showTitle)

            Spacer().frame(height: 10)

            // Description
            Text("Mirror your Android device, manage apps,\nand control everything from your Mac menu bar.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 48)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(showBody ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.4), value: showBody)

            Spacer().frame(height: 36)

            // Get Started Button — monochrome
            Button {
                viewModel.proceedToDependencyCheck()
            } label: {
                Text("Get Started")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black)
                    )
            }
            .buttonStyle(.plain)
            .scaleEffect(showButton ? 1.0 : 0.95)
            .opacity(showButton ? 1.0 : 0.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showButton)
            .keyboardShortcut(.return, modifiers: [])

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: animateIn)
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            showIcon = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.4)) {
                showTitle = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.4)) {
                showBody = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                showButton = true
            }
        }
    }
}
