//
//  CompletionPage.swift
//  AndroLaunch
//

import SwiftUI

struct CompletionPage: View {
    @ObservedObject var viewModel: OnboardingViewModel

    @State private var showCheckmark = false
    @State private var checkmarkScale: CGFloat = 0.0
    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var showCards = false
    @State private var showButton = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Checkmark in subtle ring
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundColor(.primary.opacity(0.6))
            }
            .scaleEffect(checkmarkScale)
            .onAppear(perform: animateCheckmark)

            Spacer().frame(height: 22)

            // Title
            Text("You're All Set")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.primary)
                .opacity(showTitle ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.4), value: showTitle)

            Spacer().frame(height: 8)

            // Subtitle
            Text("AndroLaunch is ready to use.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .opacity(showSubtitle ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.4), value: showSubtitle)

            Spacer().frame(height: 22)

            // Summary cards
            VStack(spacing: 6) {
                ForEach(Array(viewModel.summaryItems.enumerated()), id: \.offset) { index, item in
                    summaryRow(icon: item.icon, text: item.text, success: item.success)
                        .offset(y: showCards ? 0 : 12)
                        .opacity(showCards ? 1.0 : 0.0)
                        .animation(
                            .easeOut(duration: 0.3).delay(0.08 * Double(index)),
                            value: showCards
                        )
                }
            }
            .padding(.horizontal, 40)

            Spacer().frame(height: 32)

            // Start button
            Button {
                viewModel.completeOnboarding()
            } label: {
                Text("Start Using AndroLaunch")
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
        .onAppear(perform: sequenceReveal)
    }

    // MARK: - Animations

    private func animateCheckmark() {
        withAnimation(.interpolatingSpring(stiffness: 150, damping: 8)) {
            checkmarkScale = 1.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.interpolatingSpring(stiffness: 200, damping: 12)) {
                checkmarkScale = 1.0
            }
        }
    }

    private func sequenceReveal() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.4)) { showTitle = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.4)) { showSubtitle = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.3)) { showCards = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { showButton = true }
        }
    }

    // MARK: - Summary Row (Monochrome)

    private func summaryRow(icon: String, text: String, success: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(success ? .primary.opacity(0.45) : .secondary.opacity(0.5))
                .frame(width: 16)

            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
    }
}
