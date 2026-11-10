//
//  StorageAccessModels.swift
//  AndroLaunch
//
//  Foundation-only models for protocol v5's storage-permission handshake.
//
//  `storage.access` answers:
//      {"granted":false,"manager":false,"read":false,"media":true,"detail":"…"}
//
//  `storage.requestAccess` answers `opened` (the Android Settings screen that
//  grants the permission was launched) or an error code. The grant happens in
//  Android settings, so the Mac always re-reads `storage.access` afterwards
//  instead of assuming the tap succeeded.
//
//  Keeping decoding and the action-argument format here (no AppKit) means the
//  logic tests exercise the same code the app runs and never touch a device.
//

import Foundation

// MARK: - storage.access

/// Current storage-permission state of the companion on one device.
struct StorageAccessState: Equatable {
    /// Full folder-tree access (All files access on Android 11+, legacy read below).
    var granted: Bool
    /// Android 11+ "All files access" special grant.
    var manager: Bool
    /// Legacy READ_EXTERNAL_STORAGE grant (meaningful up to API 32).
    var read: Bool
    /// READ_MEDIA_IMAGES / READ_MEDIA_VIDEO granted (Android 13+); media only.
    var media: Bool
    /// One sentence the Mac can show unchanged.
    var detail: String

    /// Short menu/subtitle-friendly summary.
    var summary: String {
        if manager { return "All files access" }
        if granted { return "Storage access" }
        if media { return "Media only" }
        return "No storage access"
    }

    /// True when the Mac should offer the "Allow storage access" action.
    var needsGrant: Bool { !granted }

    /// Derives a detail sentence when the phone did not send one (older payload
    /// shape or a trimmed response).
    static func derivedDetail(granted: Bool, manager: Bool, media: Bool) -> String {
        if manager { return "All files access is granted, so folder totals are complete." }
        if granted { return "Storage access is granted, so folder totals are complete." }
        if media {
            return "Media access only. Folder totals need All files access in Android settings."
        }
        return "Storage access is not granted. Android hides folder totals from apps without it."
    }

    /// Decodes `storage.access`. Returns nil only when the payload is not a JSON
    /// object at all; missing fields fall back to safe defaults so a newer/older
    /// companion shape still renders.
    static func decode(_ json: String) -> StorageAccessState? {
        guard let object = PhoneJSON.object(json) else { return nil }

        let manager = PhoneJSON.bool(object["manager"])
        let read = PhoneJSON.bool(object["read"])
        let media = PhoneJSON.bool(object["media"])
        // `granted` is explicit when present; otherwise derive it. Media-only
        // access can never be "granted" because it cannot enumerate folders.
        let granted: Bool
        if object["granted"] == nil {
            granted = manager || read
        } else {
            granted = PhoneJSON.bool(object["granted"])
        }

        let detail =
            (object["detail"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return StorageAccessState(
            granted: granted,
            manager: manager,
            read: read,
            media: media,
            detail: detail.isEmpty ? derivedDetail(granted: granted, manager: manager, media: media) : detail)
    }
}

// MARK: - storage.requestAccess

enum StorageAccessLogic {

    /// `storage.requestAccess` answers `opened` when Settings was launched.
    static func didOpenSettings(_ payload: String) -> Bool {
        payload.trimmingCharacters(in: .whitespacesAndNewlines) == "opened"
    }

    /// Human error for a failed access check / request, including a legacy
    /// companion that predates protocol v5.
    static func friendlyError(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else {
            return "The phone did not report its storage permission state."
        }
        if raw.contains("unknown_command") {
            return "Update AndroLaunch Comp on the phone to manage storage access from the Mac."
        }
        switch raw {
        case "failed":
            return "Android did not open its settings screen. Open AndroLaunch Comp on the phone and allow storage access there."
        case "not running", "not ready":
            return "AndroLaunch Comp is not running on the phone."
        default:
            return raw
        }
    }
}

// MARK: - notif.action argument

/// `notif.action` argument is `<notification key>\n<action index>`.
///
/// A single newline-separated string keeps the request side of the line protocol
/// JSON-free, matching `notif.dismiss` (key only) and `notif.reply` (JSON).
enum CompanionNotificationActionArgument {

    static func make(key: String, actionIndex: Int) -> String? {
        let cleaned = key
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, actionIndex >= 0 else { return nil }
        return "\(cleaned)\n\(actionIndex)"
    }

    static func parse(_ argument: String) -> (key: String, actionIndex: Int)? {
        guard let newline = argument.firstIndex(of: "\n") else { return nil }
        let key = argument[..<newline].trimmingCharacters(in: .whitespaces)
        let indexText = argument[argument.index(after: newline)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let index = Int(indexText), index >= 0 else { return nil }
        return (key, index)
    }
}

// MARK: - Notification action failure copy

/// Typed companion results and transport errors become actionable copy.
/// Foundation-only so the logic tests cover the exact strings the UI shows.
enum NotificationActionFailureText {

    static func message(for raw: String?) -> String {
        guard let raw, !raw.isEmpty else {
            return "The phone did not run that notification action."
        }
        if raw.contains("unknown_command") {
            return "Update AndroLaunch Comp on the phone to use notification actions."
        }
        switch raw {
        case "gone":
            return "That notification is no longer on the phone."
        case "no_action":
            return "This notification does not offer that action on the phone."
        case "action_failed":
            return "The phone refused the notification action."
        case "permission_required":
            return "Allow notification access for AndroLaunch Comp on the phone."
        default:
            return raw
        }
    }
}
