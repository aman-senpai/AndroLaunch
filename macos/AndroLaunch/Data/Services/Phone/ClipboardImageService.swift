//
//  ClipboardImageService.swift
//  AndroLaunch
//
//  Image clipboard between the Mac and the phone through the companion.
//
//  Mac → phone is fully supported: the bytes are downscaled/re-encoded to fit the
//  8 MB protocol cap, then the companion writes them where a pasting app can read
//  them (MediaStore on Android 10+, FileProvider on 8–9).
//
//  Phone → Mac remains best-effort by platform design: Android 10+ only lets an
//  app read the clipboard while it has focus, so "no image" is the common honest
//  result. Nothing is cached on either side.
//

import AppKit
import Foundation

final class ClipboardImageService {

    static let shared = ClipboardImageService()

    private let companion: CompanionClient

    init(companion: CompanionClient = .shared) {
        self.companion = companion
    }

    // MARK: - Mac → phone

    /// Sends the image currently on the Mac pasteboard to the phone clipboard.
    func pushPasteboardImage(to deviceID: String, completion: @escaping (Bool, String?) -> Void) {
        guard let image = Self.pasteboardImage() else {
            completion(false, "Copy an image on the Mac first (screenshot, Preview, Finder).")
            return
        }
        guard
            let data = Self.protocolData(
                from: image, maxBytes: CompanionClient.maxClipboardImageBytes)
        else {
            completion(
                false,
                "The image could not be reduced below \(PhoneFormat.bytes(Int64(CompanionClient.maxClipboardImageBytes))).")
            return
        }
        companion.pushClipboardImage(data, deviceID: deviceID) { success, message in
            completion(success, message)
        }
    }

    // MARK: - Phone → Mac

    /// Copies an image from the phone clipboard onto the Mac pasteboard.
    func pullPhoneImage(from deviceID: String, completion: @escaping (Bool, String?) -> Void) {
        companion.pullClipboardImage(deviceID: deviceID) { data in
            guard let data, let image = NSImage(data: data) else {
                completion(
                    false,
                    "No image was available. Android only allows clipboard reads while AndroLaunch Comp is open on the phone."
                )
                return
            }
            Self.writeToPasteboard(image)
            completion(true, nil)
        }
    }

    // MARK: - Pasteboard helpers

    /// Cheap probe for menu enabling: checks pasteboard types instead of decoding
    /// a possibly multi-megabyte image on every menu build.
    static func pasteboardContainsImage() -> Bool {
        let pasteboard = NSPasteboard.general
        let types = pasteboard.types ?? []
        if types.contains(.tiff) || types.contains(.png) { return true }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard
            let urls = pasteboard.readObjects(
                forClasses: [NSURL.self], options: options) as? [URL]
        else { return false }
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp"]
        return urls.contains { imageExtensions.contains($0.pathExtension.lowercased()) }
    }

    static func pasteboardImage() -> NSImage? {
        let pasteboard = NSPasteboard.general
        if let image = NSImage(pasteboard: pasteboard) {
            return image
        }
        // Finder copies files rather than image data; accept common image files.
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard
            let urls = pasteboard.readObjects(
                forClasses: [NSURL.self], options: options) as? [URL]
        else { return nil }
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp"]
        for url in urls where imageExtensions.contains(url.pathExtension.lowercased()) {
            if let image = NSImage(contentsOf: url) { return image }
        }
        return nil
    }

    static func writeToPasteboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    /// Encodes an image for the wire: PNG when it fits, otherwise a downscaled
    /// PNG, otherwise JPEG at decreasing quality. Returns nil only if even the
    /// smallest encoding would exceed the cap.
    static func protocolData(from image: NSImage, maxBytes: Int) -> Data? {
        let sizes = [2048, 1536, 1280, 1024, 768]
        for edge in sizes {
            let scaled = resized(image, maxEdge: CGFloat(edge))
            if let png = pngData(scaled), png.count <= maxBytes {
                return png
            }
        }
        for quality in [0.85, 0.7, 0.55, 0.4, 0.25] {
            let scaled = resized(image, maxEdge: 1280)
            if let jpeg = jpegData(scaled, quality: quality), jpeg.count <= maxBytes {
                return jpeg
            }
        }
        return nil
    }

    static func resized(_ image: NSImage, maxEdge: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let longest = max(size.width, size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let result = NSImage(size: target)
        result.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1)
        result.unlockFocus()
        return result
    }

    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    static func jpegData(_ image: NSImage, quality: Double) -> Data? {
        guard let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
