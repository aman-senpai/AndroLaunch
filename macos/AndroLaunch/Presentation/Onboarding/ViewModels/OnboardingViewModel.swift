//
//  OnboardingViewModel.swift
//  AndroLaunch
//

import Combine
import Foundation

// MARK: - Phase

enum OnboardingPhase: Int, CaseIterable {
    case welcome = 0
    case dependencyCheck = 1
    case completion = 2
}

// MARK: - ViewModel

final class OnboardingViewModel: ObservableObject {

    // MARK: - Published State

    @Published var currentPhase: OnboardingPhase = .welcome
    @Published var adbStatus: DependencyStatus = .checking
    @Published var scrcpyStatus: DependencyStatus = .checking
    @Published var isHomebrewAvailable: Bool = false
    @Published var canProceedFromDependencyCheck: Bool = false
    @Published var isSkippedADB: Bool = false
    @Published var isSkippedScrcpy: Bool = false
    @Published var isDismissing: Bool = false

    // MARK: - Dependencies

    private let adbService: any ADBServiceProtocol
    private let scrcpyService: any ScrcpyServiceProtocol
    private let homebrewService: any HomebrewServiceProtocol

    // MARK: - Dismiss

    var dismissHandler: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(
        adbService: any ADBServiceProtocol,
        scrcpyService: any ScrcpyServiceProtocol,
        homebrewService: any HomebrewServiceProtocol
    ) {
        self.adbService = adbService
        self.scrcpyService = scrcpyService
        self.homebrewService = homebrewService
    }

    // MARK: - Phase Navigation

    func proceedToDependencyCheck() {
        currentPhase = .dependencyCheck
        beginDependencyCheck()
    }

    // MARK: - Dependency Checking

    func beginDependencyCheck() {
        isHomebrewAvailable = homebrewService.checkHomebrewAvailability()

        // Check ADB
        if let path = adbService.detectADBPath() {
            adbStatus = .found(path: path)
        } else {
            adbStatus = .notFound
        }

        // Check scrcpy
        if let path = scrcpyService.detectScrcpyPath() {
            scrcpyStatus = .found(path: path)
        } else {
            scrcpyStatus = .notFound
        }

        updateCanProceed()
    }

    private func updateCanProceed() {
        canProceedFromDependencyCheck = adbStatus.isResolved && scrcpyStatus.isResolved

        // Auto-advance if both already installed
        if adbStatus.isInstalled && scrcpyStatus.isInstalled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self, self.currentPhase == .dependencyCheck else { return }
                self.goToCompletion()
            }
        }
    }

    // MARK: - Install Actions

    func installADB() {
        adbStatus = .installing(phase: "Preparing...")
        performInstall(formula: "android-platform-tools", dependencyID: "adb") { [weak self] path in
            self?.adbStatus = .installed(path: path)
            self?.updateCanProceed()
        } onFail: { [weak self] error in
            self?.adbStatus = .failed(error: error)
            self?.updateCanProceed()
        }
    }

    func installScrcpy() {
        scrcpyStatus = .installing(phase: "Preparing...")
        performInstall(formula: "scrcpy", dependencyID: "scrcpy") { [weak self] path in
            self?.scrcpyStatus = .installed(path: path)
            self?.updateCanProceed()
        } onFail: { [weak self] error in
            self?.scrcpyStatus = .failed(error: error)
            self?.updateCanProceed()
        }
    }

    private func performInstall(
        formula: String,
        dependencyID: String,
        onComplete: @escaping (String) -> Void,
        onFail: @escaping (String) -> Void
    ) {
        homebrewService.installFormula(formula)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                switch event {
                case .progress(let phase, _):
                    switch dependencyID {
                    case "adb": self?.adbStatus = .installing(phase: phase)
                    case "scrcpy": self?.scrcpyStatus = .installing(phase: phase)
                    default: break
                    }
                case .completed(let path):
                    onComplete(path)
                case .failed(let error):
                    onFail(error)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Skip Actions

    func skipADBInstallation() {
        isSkippedADB = true
        adbStatus = .notFound
        updateCanProceed()
    }

    func skipScrcpyInstallation() {
        isSkippedScrcpy = true
        scrcpyStatus = .notFound
        updateCanProceed()
    }

    // MARK: - Phase Transitions

    func goToCompletion() {
        currentPhase = .completion
    }

    func completeOnboarding() {
        isDismissing = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.dismissHandler?()
        }
    }

    // MARK: - Summary

    var summaryItems: [(icon: String, text: String, success: Bool)] {
        var items: [(String, String, Bool)] = []

        switch adbStatus {
        case .found(let path):
            items.append(("checkmark.circle.fill", "ADB found at \(abbreviatedPath(path))", true))
        case .installed(let path):
            items.append(("checkmark.circle.fill", "ADB installed at \(abbreviatedPath(path))", true))
        case .notFound:
            items.append(("minus.circle.fill", "ADB skipped — install later in Settings", false))
        case .failed(let error):
            items.append(("xmark.circle.fill", "ADB: \(error)", false))
        case .checking, .installing:
            break
        }

        switch scrcpyStatus {
        case .found(let path):
            items.append(("checkmark.circle.fill", "scrcpy found at \(abbreviatedPath(path))", true))
        case .installed(let path):
            items.append(("checkmark.circle.fill", "scrcpy installed at \(abbreviatedPath(path))", true))
        case .notFound:
            items.append(("minus.circle.fill", "scrcpy skipped — install later in Settings", false))
        case .failed(let error):
            items.append(("xmark.circle.fill", "scrcpy: \(error)", false))
        case .checking, .installing:
            break
        }

        return items
    }

    var allDependenciesReady: Bool {
        return adbStatus.isInstalled && scrcpyStatus.isInstalled
    }

    // MARK: - Helpers

    private func abbreviatedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
