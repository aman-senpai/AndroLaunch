//
//  DesktopShortcutBuilder.swift
//  AndroLaunch
//
//  Generates a tiny, self-contained `.app` on the Desktop whose executable is a
//  two-line shell script: it opens `androlaunch://launch?…`, the same URL the
//  About/deep-link path uses. Nothing is installed system-wide and removing the
//  file removes the shortcut.
//

import AppKit

enum DesktopShortcutError: LocalizedError {
    case desktopUnavailable
    case bundleCreationFailed(String)
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .desktopUnavailable:
            return "The Desktop folder isn't available, so no shortcut was created."
        case .bundleCreationFailed(let detail):
            return "The shortcut couldn't be created: \(detail)"
        case .validationFailed(let detail):
            return "The shortcut was written but failed validation: \(detail)"
        }
    }
}

enum DesktopShortcutBuilder {
    /// Creates a Desktop shortcut for one app and returns its URL.
    static func create(app: AndroidApp, device: AndroidDevice) throws -> URL {
        try create(app: app, device: device, in: nil)
    }

    /// Same, writing into `directory` when supplied (used by verification tools);
    /// nil means the user's Desktop.
    static func create(app: AndroidApp, device: AndroidDevice, in directory: URL?) throws -> URL {
        let fileManager = FileManager.default
        let destination: URL
        if let directory {
            destination = directory
        } else if let desktop = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first {
            destination = desktop
        } else {
            destination = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Desktop")
        }
        guard fileManager.fileExists(atPath: destination.path) else {
            throw DesktopShortcutError.desktopUnavailable
        }
        guard
            let url = AppDeepLink.makeURL(
                deviceID: device.id,
                packageID: app.packageName,
                appName: app.name,
                mode: .meldWindow)
        else {
            throw DesktopShortcutError.bundleCreationFailed("The app link could not be built.")
        }

        let existingNames = (try? fileManager.contentsOfDirectory(atPath: destination.path)) ?? []
        let bundleName = ShortcutNaming.uniqueBundleName(
            appName: app.name,
            deviceName: device.name,
            packageID: app.packageName,
            existingNames: existingNames)
        let bundleURL = destination.appendingPathComponent(
            bundleName + ".app", isDirectory: true)
        guard !fileManager.fileExists(atPath: bundleURL.path) else {
            throw DesktopShortcutError.bundleCreationFailed(
                "A shortcut named “\(bundleName).app” already exists.")
        }

        let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        let executableName = "launch"
        let executableURL = macOS.appendingPathComponent(executableName)

        do {
            try fileManager.createDirectory(at: macOS, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)

            let iconURL = resources.appendingPathComponent("AppIcon.icns")
            let hasIcon = writeIcon(app: app, to: iconURL)

            var info: [String: Any] = [
                "CFBundleName": bundleName,
                "CFBundleDisplayName": bundleName,
                "CFBundleIdentifier":
                    "com.senpai.AndroLaunch.shortcut."
                    + ShortcutNaming.identifierSuffix(
                        deviceID: device.id, packageID: app.packageName),
                "CFBundleVersion": "1",
                "CFBundleShortVersionString": "1.0",
                "CFBundlePackageType": "APPL",
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundleExecutable": executableName,
                "LSMinimumSystemVersion": "13.0",
                "LSUIElement": true,
                "NSHighResolutionCapable": true,
            ]
            if hasIcon {
                info["CFBundleIconFile"] = "AppIcon"
            }
            let plistData = try PropertyListSerialization.data(
                fromPropertyList: info, format: .xml, options: 0)
            try plistData.write(to: contents.appendingPathComponent("Info.plist"))

            // `open` launches the registered androlaunch:// handler, so the
            // shortcut keeps working after the app moves or updates. Single
            // quotes prevent shell metacharacters in a device/app label from
            // being evaluated when the shortcut is double-clicked.
            let quotedURL = url.absoluteString.replacingOccurrences(
                of: "'", with: "'\\''")
            let script = """
                #!/bin/sh
                exec /usr/bin/open '\(quotedURL)'
                """
            try script.write(to: executableURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        } catch {
            try? fileManager.removeItem(at: bundleURL)
            throw DesktopShortcutError.bundleCreationFailed(error.localizedDescription)
        }

        try validate(bundleURL: bundleURL, executableURL: executableURL, infoPlistURL: contents.appendingPathComponent("Info.plist"))
        return bundleURL
    }

    // MARK: - Validation

    private static func validate(
        bundleURL: URL, executableURL: URL, infoPlistURL: URL
    ) throws {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            try? fileManager.removeItem(at: bundleURL)
            throw DesktopShortcutError.validationFailed("The launcher script is not executable.")
        }
        guard let data = try? Data(contentsOf: infoPlistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dictionary = plist as? [String: Any],
            dictionary["CFBundleExecutable"] as? String == executableURL.lastPathComponent
        else {
            try? fileManager.removeItem(at: bundleURL)
            throw DesktopShortcutError.validationFailed(
                "The generated Info.plist could not be read back.")
        }
        guard Bundle(url: bundleURL)?.executableURL != nil else {
            try? fileManager.removeItem(at: bundleURL)
            throw DesktopShortcutError.validationFailed("macOS does not recognise the bundle.")
        }
    }

    // MARK: - Icon

    /// Best-effort `.icns` rendered from the app's SF Symbol and the brand
    /// gradient. A missing icon never blocks the shortcut.
    private static func writeIcon(app: AndroidApp, to iconURL: URL) -> Bool {
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory.appendingPathComponent(
            "androlaunch-shortcut-icon-\(UUID().uuidString)", isDirectory: true)
        let iconset = work.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        defer { try? fileManager.removeItem(at: work) }
        guard (try? fileManager.createDirectory(at: iconset, withIntermediateDirectories: true))
            != nil
        else { return false }

        let symbolName = AppIconMapper.getIconName(for: app)
        let variants: [(name: String, pixels: Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for variant in variants {
            guard let data = iconPNGData(symbolName: symbolName, pixels: variant.pixels) else {
                return false
            }
            do {
                try data.write(to: iconset.appendingPathComponent("\(variant.name).png"))
            } catch {
                return false
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconset.path, "-o", iconURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        return process.terminationStatus == 0 && fileManager.fileExists(atPath: iconURL.path)
    }

    private static func iconPNGData(symbolName: String, pixels: Int) -> Data? {
        guard pixels > 0,
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }

        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        let inset = CGFloat(pixels) * 0.035
        let tile = rect.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(
            roundedRect: tile, xRadius: CGFloat(pixels) * 0.225,
            yRadius: CGFloat(pixels) * 0.225)
        path.addClip()
        let gradient = NSGradient(colors: [
            NSColor(srgbRed: 0x6F / 255.0, green: 0xE0 / 255.0, blue: 0x7A / 255.0, alpha: 1),
            NSColor(srgbRed: 0x2F / 255.0, green: 0x7D / 255.0, blue: 0x36 / 255.0, alpha: 1),
        ])
        gradient?.draw(in: path, angle: -90)

        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(
                    pointSize: CGFloat(pixels) * 0.46, weight: .semibold)
                    .applying(.init(paletteColors: [.white])))
        {
            let symbolSize = symbol.size
            let scale = min(
                CGFloat(pixels) * 0.56 / max(symbolSize.width, 1),
                CGFloat(pixels) * 0.56 / max(symbolSize.height, 1))
            let drawSize = NSSize(
                width: symbolSize.width * scale, height: symbolSize.height * scale)
            let origin = NSPoint(
                x: (CGFloat(pixels) - drawSize.width) / 2,
                y: (CGFloat(pixels) - drawSize.height) / 2)
            symbol.draw(in: NSRect(origin: origin, size: drawSize))
        }

        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
