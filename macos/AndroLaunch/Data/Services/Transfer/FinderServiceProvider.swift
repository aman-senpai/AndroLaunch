//
//  FinderServiceProvider.swift
//  AndroLaunch
//
//  The macOS Services hook behind Finder → right-click → Services →
//  "Send to Android". It reads the selected files off the pasteboard and hands
//  them to the shared transfer queue, so a file reaches the phone without the
//  file browser being opened.
//

import AppKit

final class FinderServiceProvider: NSObject {
    static let shared = FinderServiceProvider()

    private let coordinator = TransferCoordinator.shared

    private override init() {
        super.init()
    }

    /// Registers the provider for the `NSServices` entry declared in Info.plist.
    /// Must be called during launch, after `NSApp` exists.
    func install() {
        guard let application = NSApp else { return }
        application.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// Services entry point. The selector name must match `NSMessage` in Info.plist.
    @objc func sendFilesToAndroid(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let objects =
            pboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) ?? []
        let urls = objects.compactMap { $0 as? URL }.filter { $0.isFileURL }

        guard !urls.isEmpty else {
            error.pointee = "Select one or more files to send to Android." as NSString
            return
        }

        guard let device = preferredDevice() else {
            error.pointee =
                "No Android device is connected. Connect and authorize a device in AndroLaunch." as NSString
            return
        }

        coordinator.enqueue(files: urls, deviceID: device.id)
    }

    /// Finder → Services → "Copy to Android". Text and URLs only; files use
    /// "Send to Android" above.
    @objc func copyToAndroid(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let text =
            pboard.string(forType: .string)
            ?? pboard.string(forType: .URL)
            ?? pboard.propertyList(forType: .string) as? String
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "Select text or a link to copy to Android." as NSString
            return
        }
        guard CopyToAndroidService.shared.copy(text) else {
            error.pointee =
                "No Android device is connected. Connect and authorize a device in AndroLaunch." as NSString
            return
        }
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return !isDirectory.boolValue
    }

    private static func totalSize(of urls: [URL]) -> Int64 {
        urls.reduce(into: Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
    }

    // MARK: - Device selection

    /// Prefers the device used most recently in the menu, then falls back to the
    /// first authorized device (the connected-device list only contains devices
    /// ADB has authorized).
    private func preferredDevice() -> AndroidDevice? {
        let viewModel = DependencyContainer.shared.menuViewModel
        if let currentDeviceID = viewModel.currentDeviceID,
            let recent = viewModel.devices.first(where: { $0.id == currentDeviceID })
        {
            return recent
        }
        return viewModel.devices.first
    }
}
