//
//  OnboardingPageModels.swift
//  AndroLaunch
//
//  Copy and value types for the first-run experience. Pages take these
//  values instead of the view model so they stay easy to render and preview, and
//  the view model remains the only place with service dependencies.
//

import Foundation

// MARK: - Content

struct OnboardingStep: Identifiable {
    let index: Int
    let title: String
    let detail: String
    let icon: String

    var id: Int { index }
}

struct OnboardingFeature: Identifiable {
    let title: String
    let detail: String
    let icon: String

    var id: String { title }
}

enum OnboardingCopy {
    static let heroTitle = "Welcome to AndroLaunch"
    static let heroBody =
        "A local, account-free bridge between your Android phone and your Mac. Connect once, then work with files, mirroring and Frame Mode windows."

    static let steps: [OnboardingStep] = [
        OnboardingStep(
            index: 1,
            title: "Files",
            detail: "Browse, push and pull files over ADB.",
            icon: "folder.fill"),
        OnboardingStep(
            index: 2,
            title: "Mirror",
            detail: "See and control the phone screen.",
            icon: "display"),
        OnboardingStep(
            index: 3,
            title: "Frame Mode",
            detail: "Android apps in their own Mac windows.",
            icon: "rectangle.on.rectangle"),
    ]

    static let features: [OnboardingFeature] = [
        OnboardingFeature(
            title: "Notifications",
            detail: "Mirror with actions and inline reply.",
            icon: "bell.badge.fill"),
        OnboardingFeature(
            title: "Clipboard",
            detail: "Text and images, both directions.",
            icon: "doc.on.clipboard.fill"),
        OnboardingFeature(
            title: "Calls",
            detail: "Answer or decline; audio stays on the phone.",
            icon: "phone.fill"),
        OnboardingFeature(
            title: "Android Use",
            detail: "Let local AI tools drive your phone.",
            icon: "sparkles"),
    ]

    static let setupTitle = "Set up your Mac"
    static let setupBody =
        "AndroLaunch uses two free, open-source tools. Both stay on this Mac."
    static let completionTitle = "You're ready"
    static let localNote = "Local only — no account, no cloud, no telemetry."
}

// MARK: - Dependency setup

struct OnboardingDependencyActions {
    var installADB: () -> Void = {}
    var installScrcpy: () -> Void = {}
    var skipADB: () -> Void = {}
    var skipScrcpy: () -> Void = {}
    var continueSetup: () -> Void = {}
    var skipAll: () -> Void = {}
}

// MARK: - Completion summary

struct OnboardingSummaryItem: Identifiable {
    let icon: String
    let text: String
    let isSuccess: Bool

    var id: String { text }
}

// MARK: - Presentation helpers

extension DependencyStatus {
    /// Short badge for the setup cards.
    var onboardingBadge: (text: String, tone: String) {
        switch self {
        case .checking: return ("Checking", "secondary")
        case .found: return ("Ready", "success")
        case .installed: return ("Installed", "success")
        case .notFound: return ("Not installed", "warning")
        case .installing: return ("Installing", "accent")
        case .failed: return ("Failed", "danger")
        }
    }

    var onboardingIsReady: Bool {
        switch self {
        case .found, .installed: return true
        default: return false
        }
    }

    /// Install/skip affordances are only useful while the tool is missing or an
    /// install attempt failed.
    var onboardingNeedsAction: Bool {
        switch self {
        case .notFound, .failed: return true
        default: return false
        }
    }

    var onboardingFailureMessage: String? {
        if case .failed(let error) = self { return error }
        return nil
    }

    var onboardingInstallPhase: String? {
        if case .installing(let phase) = self { return phase }
        return nil
    }
}
