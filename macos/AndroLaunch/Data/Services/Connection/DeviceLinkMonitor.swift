//
//  DeviceLinkMonitor.swift
//  AndroLaunch
//
//  Reads the raw `adb devices -l` transport list so the Devices surface can show
//  every link the way adb sees it — including phones that are connected but not
//  usable yet (unauthorized, offline, bootloader). `AndroidDevice` only carries
//  authorized devices, which is right for the rest of the app but hides the one
//  state a new user is most likely to hit.
//

import Combine
import Foundation

final class DeviceLinkMonitor: ObservableObject {

    enum ProbeState: Equatable {
        case unknown
        case running
        case failed(String)
    }

    @Published private(set) var entries: [ADBLinkEntry] = []
    @Published private(set) var probeState: ProbeState = .unknown
    @Published private(set) var isRefreshing = false

    private let adb: ADBService?
    private let preview: Bool

    init(preview: Bool = false) {
        self.preview = preview
        // Preview snapshots must not construct the service graph (it starts
        // emulator polling). The Devices view uses its own preview fixtures.
        self.adb = preview ? nil : DependencyContainer.shared.adb
    }

    func refresh() {
        guard !preview, let adb, !isRefreshing else { return }
        guard adb.adbPath != nil else {
            entries = []
            probeState = .failed("ADB was not found. Install Android platform-tools.")
            return
        }
        isRefreshing = true
        adb.executeADBCommand(arguments: ["devices", "-l"]) {
            [weak self] success, output, errorOutput in
            guard let self else { return }
            self.isRefreshing = false
            if success {
                self.entries = ADBDeviceListParser.parse(output ?? "")
                self.probeState = .running
            } else {
                let detail = (errorOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                self.entries = []
                self.probeState = .failed(
                    detail.isEmpty ? "Could not read the ADB device list." : detail)
            }
        }
    }
}
