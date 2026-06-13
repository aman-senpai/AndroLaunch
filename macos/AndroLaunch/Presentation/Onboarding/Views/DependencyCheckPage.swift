//
//  DependencyCheckPage.swift
//  AndroLaunch
//

import SwiftUI

struct DependencyCheckPage: View {
    @ObservedObject var viewModel: OnboardingViewModel

    @State private var showCards = false
    @State private var showContinueButton = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 28)

            // Header
            VStack(spacing: 6) {
                Text("Checking Dependencies")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)

                Text("Let's make sure everything is ready.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 22)

            // Dependency Cards
            VStack(spacing: 12) {
                DependencyCard(
                    info: .adb,
                    status: $viewModel.adbStatus,
                    isHomebrewAvailable: viewModel.isHomebrewAvailable,
                    onInstall: { viewModel.installADB() },
                    onSkip: { viewModel.skipADBInstallation() },
                    onRetry: { viewModel.installADB() }
                )

                DependencyCard(
                    info: .scrcpy,
                    status: $viewModel.scrcpyStatus,
                    isHomebrewAvailable: viewModel.isHomebrewAvailable,
                    onInstall: { viewModel.installScrcpy() },
                    onSkip: { viewModel.skipScrcpyInstallation() },
                    onRetry: { viewModel.installScrcpy() }
                )
            }
            .padding(.horizontal, 32)
            .offset(y: showCards ? 0 : 16)
            .opacity(showCards ? 1.0 : 0.0)
            .animation(.easeOut(duration: 0.35).delay(0.1), value: showCards)

            Spacer(minLength: 20)

            // Action Buttons
            VStack(spacing: 10) {
                if viewModel.canProceedFromDependencyCheck {
                    Button {
                        viewModel.goToCompletion()
                    } label: {
                        Text("Continue")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 180)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.black)
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }

                if !viewModel.adbStatus.isInstalled || !viewModel.scrcpyStatus.isInstalled {
                    Button("Skip All") {
                        if !viewModel.adbStatus.isResolved { viewModel.skipADBInstallation() }
                        if !viewModel.scrcpyStatus.isResolved { viewModel.skipScrcpyInstallation() }
                        viewModel.goToCompletion()
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 28)
            .opacity(showContinueButton ? 1.0 : 0.0)
            .animation(.easeOut(duration: 0.3), value: showContinueButton)

            Spacer().frame(height: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                showCards = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    showContinueButton = viewModel.canProceedFromDependencyCheck
                }
            }
        }
        .onChange(of: viewModel.canProceedFromDependencyCheck) { newValue in
            withAnimation(.easeOut(duration: 0.3)) {
                showContinueButton = newValue
            }
        }
    }
}

// MARK: - Dependency Card (Monochrome)

private struct DependencyCard: View {
    let info: DependencyInfo
    @Binding var status: DependencyStatus
    let isHomebrewAvailable: Bool
    let onInstall: () -> Void
    let onSkip: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: info.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary.opacity(0.55))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(info.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text(info.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                statusIndicator
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            // Action row
            if status == .notFound || isFailed {
                Divider()
                    .background(Color.primary.opacity(0.08))
                    .padding(.horizontal, 14)

                actionRow
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Install progress
            if case .installing(let phase) = status {
                Divider()
                    .background(Color.primary.opacity(0.08))
                    .padding(.horizontal, 14)

                installProgressRow(phase: phase)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.25), value: status)
    }

    // MARK: - Status Indicator (Monochrome)

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.8)

        case .found(let path):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.primary.opacity(0.5))
                    .symbolEffect(.bounce, value: status)
                Text(abbreviatedPath(path))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

        case .notFound:
            Image(systemName: "circle")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.4))

        case .installing:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.8)

        case .installed(let path):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.primary.opacity(0.5))
                    .symbolEffect(.bounce, value: status)
                Text(abbreviatedPath(path))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.5))
        }
    }

    // MARK: - Action Row

    @ViewBuilder
    private var actionRow: some View {
        if !isHomebrewAvailable && status == .notFound {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Homebrew is not installed.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Link("Install Homebrew →", destination: URL(string: "https://brew.sh")!)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        } else {
            HStack(spacing: 8) {
                Button(action: onInstall) {
                    Text("Install with Homebrew")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.black)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isHomebrewAvailable)

                Button("Skip") { onSkip() }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)

                if isFailed {
                    Button("Retry") { onRetry() }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Progress Row

    private func installProgressRow(phase: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.linear)
                .controlSize(.small)
            Text(phase)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Helpers

    private var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
