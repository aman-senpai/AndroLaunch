//
//  CopyToAndroidService.swift
//  AndroLaunch
//
//  Sends selected text or a URL to the connected phone clipboard. Used by the
//  macOS Services item and the dashboard search action.
//

import Foundation

final class CopyToAndroidService {
    static let shared = CopyToAndroidService()

    private init() {}

    /// Attempts to deliver text to the phone clipboard through the companion.
    /// Returns false only when there is no text or no connected device; delivery
    /// failures are surfaced as a local alert by the companion callback.
    @discardableResult
    func copy(_ text: String, deviceID: String? = nil) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200_000 else { return false }
        guard let target = deviceID ?? preferredDeviceID() else { return false }

        CompanionClient.shared.pushClipboard(trimmed, deviceID: target) { success in
            guard !success else { return }
            DispatchQueue.main.async {
                AlertPresenter.showWarning(
                    message:
                        "Couldn't copy to Android. Make sure the phone is connected and "
                        + "AndroLaunch Comp is installed from Devices → Wi-Fi → Companion app.")
            }
        }
        return true
    }

    private func preferredDeviceID() -> String? {
        let viewModel = DependencyContainer.shared.menuViewModel
        if let current = viewModel.currentDeviceID,
            viewModel.devices.contains(where: { $0.id == current })
        {
            return current
        }
        return viewModel.devices.first(where: \.isConnected)?.id ?? viewModel.devices.first?.id
    }
}
