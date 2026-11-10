//
//  OnboardingSnapshotRenderer.swift
//  AndroLaunch
//
//  DEBUG-only visual verification for the onboarding pages: renders them with the
//  same Hub design system tokens at the real 620×600 window size, without a
//  window-server session or Screen Recording permission.
//
//  This is the platform-extras counterpart to the Lead-owned HubSnapshotRenderer;
//  it is not wired into the app's launch arguments to keep AppDelegate untouched.
//

#if DEBUG
    import AppKit
    import SwiftUI

    enum OnboardingSnapshotRenderer {
        @MainActor
        static func render(to directoryPath: String) {
            let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)

            let size = CGSize(width: 620, height: 600)

            render(
                WelcomePage(onConnect: {}, onOpenApp: {}),
                size: size, name: "onboarding-welcome.png", in: directory)

            render(
                DependencyCheckPage(
                    adbStatus: .found(path: "/opt/homebrew/bin/adb"),
                    scrcpyStatus: .notFound,
                    homebrewAvailable: true,
                    canProceed: false,
                    actions: OnboardingDependencyActions()),
                size: size, name: "onboarding-dependencies.png", in: directory)

            render(
                CompletionPage(
                    summary: [
                        OnboardingSummaryItem(
                            icon: "checkmark.circle.fill",
                            text: "ADB is ready for device connections",
                            isSuccess: true),
                        OnboardingSummaryItem(
                            icon: "checkmark.circle.fill",
                            text: "scrcpy is ready for screen mirroring",
                            isSuccess: true),
                    ],
                    adbReady: true,
                    onConnect: {},
                    onOpenApp: {}),
                size: size, name: "onboarding-completion.png", in: directory)

            // Compact check: the same welcome page in a smaller window must stay
            // scrollable and legible rather than clip.
            render(
                WelcomePage(onConnect: {}, onOpenApp: {}),
                size: CGSize(width: 460, height: 500),
                name: "onboarding-welcome-compact.png", in: directory)
        }

        @MainActor
        private static func render<V: View>(
            _ view: V, size: CGSize, name: String, in directory: URL
        ) {
            let renderer = ImageRenderer(
                content: view
                    .frame(width: size.width, height: size.height)
                    .background(HubColor.background)
                    .environment(\.colorScheme, .dark)
                    .environment(\.dynamicTypeSize, .large)
                    .environment(\.hubSnapshotMode, true)
            )
            renderer.scale = 2
            guard let cgImage = renderer.cgImage else {
                FileHandle.standardError.write(Data("snapshot failed: \(name)\n".utf8))
                return
            }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            do {
                try data.write(to: directory.appendingPathComponent(name))
                print("rendered \(name)")
            } catch {
                FileHandle.standardError.write(
                    Data("write failed for \(name): \(error.localizedDescription)\n".utf8))
            }
        }
    }
#endif
