//
//  DashboardSettingsView.swift
//  AndroLaunch
//
//  Settings tab of the compact dashboard: the per-device mirror preferences that
//  matter while looking at one phone (audio, clipboard, stream quality), followed
//  by the complete Settings surface inline — no Hub window and no second link.
//

import SwiftUI

struct DashboardSettingsView: View {
    @ObservedObject var store: HubStore
    let device: AndroidDevice?
    let isPreview: Bool

    @State private var audioEnabled = true
    @State private var clipboardEnabled = false
    @State private var resolution = 900

    /// scrcpy's `-m` values the Hub's Settings surface also exposes.
    private let qualities: [Int] = [1080, 900, 720, 480]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HubCard(padding: 0) {
                VStack(spacing: 0) {
                    HubToggleRow(
                        icon: "speaker.wave.2.fill",
                        title: "Audio forwarding",
                        subtitle: "Play the phone's sound on the Mac while mirroring.",
                        isOn: $audioEnabled,
                        disabled: device == nil)

                    HubDivider()

                    HubToggleRow(
                        icon: "doc.on.clipboard",
                        title: "Clipboard sync",
                        subtitle: "Opt in for this phone. The Mac clipboard is sent over ADB.",
                        isOn: $clipboardEnabled,
                        disabled: device == nil)
                }
            }

            qualityCard

            // The complete Settings surface renders inline in the panel — no
            // separate Hub window or "Open full Settings" link.
            SettingsRootView(store: store, embedded: true)
        }
        .onAppear(perform: loadPreferences)
        .onChange(of: device?.id) { _, _ in loadPreferences() }
        .onChange(of: audioEnabled) { _, newValue in
            guard !isPreview, let device else { return }
            let current = DependencyContainer.shared.deviceRepository.isAudioEnabled(
                for: device.id)
            if current != newValue {
                DependencyContainer.shared.deviceRepository.toggleAudio(for: device.id)
            }
        }
        .onChange(of: clipboardEnabled) { _, newValue in
            guard !isPreview, let device else { return }
            let current = DependencyContainer.shared.deviceRepository.isClipboardEnabled(
                for: device.id)
            if current != newValue {
                DependencyContainer.shared.deviceRepository.toggleClipboard(for: device.id)
            }
        }
        .onChange(of: resolution) { _, newValue in
            guard !isPreview, let device else { return }
            DependencyContainer.shared.deviceRepository.setResolution(
                for: device.id, resolution: newValue)
        }
    }

    // MARK: - Quality

    private var qualityCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            DashboardSectionHeader("Stream quality") {
                Text("\(resolution)p")
                    .font(.hubCaption)
                    .foregroundStyle(HubColor.textTertiary)
            }
            HubCard(padding: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    HubSegmentedTabs(
                        items: qualities.map {
                            HubSegmentedTabs<Int>.Item(
                                value: $0, title: "\($0)p", icon: nil)
                        },
                        selection: $resolution,
                        compact: true)
                    Text(qualitySubtitle)
                        .font(.hubCaption)
                        .foregroundStyle(HubColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .opacity(device == nil ? 0.6 : 1)
        .disabled(device == nil && !isPreview)
    }

    private var qualitySubtitle: String {
        switch resolution {
        case 1080: return "Sharpest text; uses more bandwidth."
        case 900: return "Balanced default for most phones."
        case 720: return "Lighter on Wi-Fi and CPU."
        default: return "Fastest on a busy network, softer text."
        }
    }

    // MARK: - Actions

    private func loadPreferences() {
        guard !isPreview, let device else {
            audioEnabled = true
            clipboardEnabled = false
            resolution = 900
            return
        }
        let repository = DependencyContainer.shared.deviceRepository
        audioEnabled = repository.isAudioEnabled(for: device.id)
        clipboardEnabled = repository.isClipboardEnabled(for: device.id)
        let stored = repository.getResolution(for: device.id)
        resolution = qualities.contains(stored) ? stored : 900
    }
}
