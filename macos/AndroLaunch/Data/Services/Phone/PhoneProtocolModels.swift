//
//  PhoneProtocolModels.swift
//  AndroLaunch
//
//  Foundation-only decoding for the companion protocol v3.
//
//  The wire format for the state commands is JSON carried inside one base64 line.
//  Keeping the decoders pure (no AppKit, no ADB, no UI state) means the same code
//  the app uses is also what the logic tests exercise, and a malformed payload
//  can never trap the UI — every decoder returns an optional or a safe default.
//
//  Backward compatibility: every v1/v2 payload still decodes. v3 fields are
//  optional here, because a user may still have the v2 APK installed.
//

import Foundation

// MARK: - Call state

/// Decoded `call.state` payload.
struct CompanionCallState: Equatable {
    var supported: Bool
    var permission: Bool
    var enabled: Bool
    var controlAvailable: Bool
    var state: String
    var incoming: Bool
    var sinceMillis: Int64

    var isIdle: Bool { state == "idle" }
    var isRinging: Bool { state == "ringing" }
    var isInCall: Bool { state == "offhook" }

    /// The state label shown in UI copy.
    var displayName: String {
        switch state {
        case "ringing": return incoming ? "Incoming call" : "Ringing"
        case "offhook": return "In call"
        default: return "Idle"
        }
    }

    /// How the Mac copies this state into one sentence without promising audio.
    var detailText: String {
        switch state {
        case "ringing":
            return incoming
                ? "Ringing on your phone. Answer here; audio stays on your phone."
                : "A call is ringing on your phone."
        case "offhook":
            return "In a call on your phone. Audio stays on your phone."
        default:
            return "No call"
        }
    }

    static func decode(_ json: String) -> CompanionCallState? {
        guard let object = PhoneJSON.object(json) else { return nil }
        let state = (object["state"] as? String)?.lowercased() ?? "idle"
        return CompanionCallState(
            supported: PhoneJSON.bool(object["supported"]),
            permission: PhoneJSON.bool(object["permission"]),
            enabled: PhoneJSON.bool(object["enabled"]),
            controlAvailable: PhoneJSON.bool(object["control"]),
            state: state,
            incoming: PhoneJSON.bool(object["incoming"]),
            sinceMillis: PhoneJSON.int64(object["since"])
        )
    }
}

// MARK: - Media state

struct CompanionMediaState: Equatable {
    var available: Bool
    var packageName: String
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var canNext: Bool
    var canPrevious: Bool
    /// Decoded album art, present only when the caller asked for artwork. Memory-only.
    var artworkPNG: Data?

    static let unavailable = CompanionMediaState(
        available: false, packageName: "", title: "", artist: "", album: "",
        isPlaying: false, canNext: false, canPrevious: false, artworkPNG: nil)

    /// Stable identity of the current track, used to skip redundant artwork fetches.
    var trackIdentity: String {
        "\(packageName)|\(title)|\(artist)|\(album)"
    }

    static func decode(_ json: String) -> CompanionMediaState? {
        guard let object = PhoneJSON.object(json) else { return nil }
        var artwork: Data?
        if let art = object["artwork"] as? [String: Any],
            let base64 = art["data"] as? String,
            let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
        {
            // 512 KB is generous for a 256 px thumbnail and keeps a bad payload bounded.
            if data.count <= 512 * 1024 { artwork = data }
        }
        let packageName = object["app"] as? String ?? ""
        return CompanionMediaState(
            available: PhoneJSON.bool(object["available"]),
            packageName: packageName,
            title: object["title"] as? String ?? "",
            artist: object["artist"] as? String ?? "",
            album: object["album"] as? String ?? "",
            isPlaying: PhoneJSON.bool(object["playing"]),
            canNext: PhoneJSON.bool(object["canNext"]),
            canPrevious: PhoneJSON.bool(object["canPrev"]),
            artworkPNG: artwork
        )
    }
}

// MARK: - Storage

struct CompanionStorageFolder: Equatable, Identifiable {
    var name: String
    var bytes: Int64
    var id: String { name }
}

struct CompanionStorageState: Equatable {
    var totalBytes: Int64
    var usedBytes: Int64
    var freeBytes: Int64
    var path: String
    var externalTotalBytes: Int64
    var externalFreeBytes: Int64
    var scannedAt: Date
    /// False when the phone could not measure every top-level folder (scoped
    /// storage); the Mac then re-scans the folder list through `adb shell`.
    var folderListComplete: Bool
    var folders: [CompanionStorageFolder]

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }

    static func decode(_ json: String) -> CompanionStorageState? {
        guard let object = PhoneJSON.object(json) else { return nil }
        var folders: [CompanionStorageFolder] = []
        if let raw = object["folders"] as? [[String: Any]] {
            folders = raw.compactMap { entry in
                guard let name = entry["name"] as? String, !name.isEmpty else { return nil }
                return CompanionStorageFolder(name: name, bytes: PhoneJSON.int64(entry["bytes"]))
            }
            .sorted { $0.bytes > $1.bytes }
        }
        let scannedMillis = PhoneJSON.int64(object["scannedAt"])
        return CompanionStorageState(
            totalBytes: PhoneJSON.int64(object["total"]),
            usedBytes: PhoneJSON.int64(object["used"]),
            freeBytes: PhoneJSON.int64(object["free"]),
            path: object["path"] as? String ?? "/data",
            externalTotalBytes: PhoneJSON.int64(object["externalTotal"]),
            externalFreeBytes: PhoneJSON.int64(object["externalFree"]),
            scannedAt: scannedMillis > 0
                ? Date(timeIntervalSince1970: Double(scannedMillis) / 1000)
                : Date(),
            folderListComplete: PhoneJSON.bool(object["complete"]),
            folders: folders)
    }
}

// MARK: - Notifications

/// One action exposed by a mirrored notification.
struct CompanionNotificationAction: Equatable {
    var index: Int
    var title: String
    var hasReply: Bool
}

/// A notification read through the companion's notification listener.
struct CompanionNotification: Equatable {
    var key: String
    var packageName: String
    var title: String
    var text: String
    var postedAt: Date
    var isOngoing: Bool
    var isSensitive: Bool
    var replyActionIndex: Int
    var actions: [CompanionNotificationAction]

    var hasReply: Bool { replyActionIndex >= 0 }

    /// Best available text for a macOS banner.
    var displayText: String {
        let pieces = [title, text].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return pieces.joined(separator: " — ")
    }

    /// Stable de-duplication fingerprint: key plus post time.
    var fingerprint: String { "\(key)|\(Int64(postedAt.timeIntervalSince1970 * 1000))" }

    static func decodeList(_ json: String) -> [CompanionNotification]? {
        guard let data = json.data(using: .utf8),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        return raw.compactMap { entry in
            guard let key = entry["key"] as? String, !key.isEmpty else { return nil }
            let actions = (entry["actions"] as? [[String: Any]] ?? []).map { action in
                CompanionNotificationAction(
                    index: PhoneJSON.int((action["index"]) ?? -1),
                    title: action["title"] as? String ?? "",
                    hasReply: PhoneJSON.bool(action["hasReply"]))
            }
            let millis = PhoneJSON.int64(entry["time"])
            let replyIndex = entry["replyIndex"] == nil
                ? actions.first(where: { $0.hasReply })?.index ?? -1
                : PhoneJSON.int(entry["replyIndex"])
            return CompanionNotification(
                key: key,
                packageName: entry["pkg"] as? String ?? "",
                title: entry["title"] as? String ?? "",
                text: entry["text"] as? String ?? "",
                postedAt: millis > 0
                    ? Date(timeIntervalSince1970: Double(millis) / 1000)
                    : Date(),
                isOngoing: PhoneJSON.bool(entry["ongoing"]),
                isSensitive: PhoneJSON.bool(entry["sensitive"]),
                replyActionIndex: replyIndex,
                actions: actions)
        }
    }
}

// MARK: - Verification codes

/// Extracts a one-time code from mirrored notification text.
///
/// Deliberately conservative: a code must be 4–8 digits, standalone (not part of
/// a longer number, a decimal or a version string), and either grouped in two
/// halves (`123 456`) or surrounded by code vocabulary. Four-digit years and
/// plain phone numbers are rejected unless the notification talks about a code.
enum VerificationCode {

    private static let keywords = [
        "code", "otp", "verification", "verify", "passcode", "pin", "2fa",
        "two-factor", "one-time", "sign in", "sign-in", "login", "security",
    ]

    /// Returns the first plausible code, or nil.
    static func extract(from text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let lowered = text.lowercased()
        let mentionsCode = keywords.contains { lowered.contains($0) }

        // Grouped codes first: 123 456 / 123-456 / 1234 5678 are unambiguous.
        for match in matches(pattern: "(?<![0-9])([0-9]{3,4})[ -]([0-9]{3,4})(?![0-9])", in: text) {
            let digits = match.filter { $0.isNumber }
            if (4...8).contains(digits.count) { return digits }
        }

        let candidates = matches(pattern: "(?<![0-9])[0-9]{4,8}(?![0-9])", in: text)
        guard !candidates.isEmpty else { return nil }

        if mentionsCode {
            // With code vocabulary present, a date-like value only wins when it is
            // the sole candidate (e.g. "your code for 2026 is ready" is ambiguous
            // but a bare year next to a real code must not shadow it).
            let nonYear = candidates.filter { !isYearLike($0) }
            let pool = nonYear.isEmpty ? candidates : nonYear
            return pool.first { $0.count <= 8 }
        }

        // Without vocabulary, reject years and phone-number-length values.
        return candidates.first { digits in
            if isYearLike(digits) { return false }
            if digits.count >= 7 { return false }
            return true
        }
    }

    private static func isYearLike(_ digits: String) -> Bool {
        guard digits.count == 4, let value = Int(digits) else { return false }
        return (1900...2099).contains(value)
    }

    private static func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { result in
            guard result.numberOfRanges > 1 else {
                guard let full = Range(result.range, in: text) else { return nil }
                return String(text[full])
            }
            var captured = ""
            for index in 1..<result.numberOfRanges {
                if let range = Range(result.range(at: index), in: text) {
                    captured += text[range]
                }
            }
            return captured.isEmpty ? nil : captured
        }
    }
}

// MARK: - Byte formatting

enum PhoneFormat {
    /// Binary units with one decimal below 100 units, matching Finder's feel.
    static func bytes(_ value: Int64) -> String {
        guard value > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(value)
        var unit = 0
        while size >= 1024, unit < units.count - 1 {
            size /= 1024
            unit += 1
        }
        if unit == 0 { return "\(Int(size)) B" }
        let rounded = (size * 10).rounded() / 10
        let text = rounded >= 100 ? String(format: "%.0f", rounded) : String(format: "%.1f", rounded)
        return "\(text) \(units[unit])"
    }

    /// "3.4 GB of 5 GB used" style summary used by the storage sheet.
    static func usedOfTotal(used: Int64, total: Int64) -> String {
        "\(bytes(used)) of \(bytes(total)) used"
    }
}

// MARK: - JSON helpers

enum PhoneJSON {
    static func object(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func bool(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? Int { return value != 0 }
        if let value = value as? String {
            return value == "true" || value == "1"
        }
        return false
    }

    static func int64(_ value: Any?) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String, let parsed = Int64(value) { return parsed }
        return 0
    }

    static func int(_ value: Any?) -> Int {
        Int(int64(value))
    }
}

// MARK: - Storage models shared with the UI

struct StorageFolder: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let bytes: Int64
}

struct StorageItem: Identifiable, Equatable {
    var id: String { path.isEmpty ? name : path }
    let name: String
    let path: String
    let bytes: Int64
}

// MARK: - Shell output parsers

/// Parsers for the `adb shell` fallbacks used by the storage sheet. Pure and
/// dependency-free so the same parsing the app performs is covered by the logic
/// tests, and malformed shell output degrades to "no data" instead of a crash.
enum StorageParsers {

    /// Parses `df -k /data` and returns total/used/free in bytes.
    ///
    /// Android's toybox df prints a header and one row per filesystem; the row
    /// mounted on `/data` is the volume the storage sheet describes.
    static func parseDF(_ output: String?) -> (total: Int64, used: Int64, free: Int64)? {
        guard let output else { return nil }
        for line in output.components(separatedBy: .newlines) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard fields.count >= 6 else { continue }
            guard fields.last == "/data" || fields.last?.hasPrefix("/data") == true else { continue }
            guard let totalKB = Int64(fields[1]),
                let usedKB = Int64(fields[2]),
                let freeKB = Int64(fields[3])
            else { continue }
            return (totalKB * 1024, usedKB * 1024, freeKB * 1024)
        }
        return nil
    }

    /// Parses `du -sk <paths>` output ("12345\t/storage/emulated/0/DCIM").
    static func parseDU(_ output: String?) -> [StorageFolder] {
        guard let output else { return [] }
        var folders: [String: Int64] = [:]
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: true)
            let leading: Substring
            let path: String
            if parts.count == 2 {
                leading = parts[0]
                path = String(parts[1])
            } else {
                // Some OEM du versions separate the size and path with spaces.
                let spaced = trimmed.split(
                    separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard spaced.count == 2 else { continue }
                leading = spaced[0]
                path = String(spaced[1])
            }
            guard let kb = Int64(leading.trimmingCharacters(in: .whitespaces)) else { continue }
            let name = (path as NSString).lastPathComponent
            // Zero-byte folders carry no information and only add noise.
            guard !name.isEmpty, kb > 0 else { continue }
            folders[name, default: 0] += kb * 1024
        }
        return folders
            .map { StorageFolder(name: $0.key, bytes: $0.value) }
            .sorted { $0.bytes > $1.bytes }
    }

    /// Parses `content query` rows: `Row: 0 _display_name=a.jpg, _size=123`.
    static func parseMediaQuery(_ output: String?, limit: Int = 8) -> [StorageItem] {
        guard let output else { return [] }
        var items: [StorageItem] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Row:") else { continue }
            guard
                let nameRange = trimmed.range(of: "_display_name="),
                let sizeRange = trimmed.range(of: "_size=")
            else { continue }
            var name = String(trimmed[nameRange.upperBound...])
            if let comma = name.range(of: ",") {
                name = String(name[..<comma.lowerBound])
            }
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            var sizeText = String(trimmed[sizeRange.upperBound...])
            if let comma = sizeText.range(of: ",") {
                sizeText = String(sizeText[..<comma.lowerBound])
            }
            sizeText = sizeText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let bytes = Int64(sizeText) else { continue }
            items.append(StorageItem(name: name, path: name, bytes: bytes))
        }
        return Array(items.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }
}

// MARK: - Reply argument

/// JSON body for `notif.reply`. The text lives only in this one request.
enum CompanionReplyArgument {
    static func make(key: String, actionIndex: Int, text: String) -> String {
        let object: [String: Any] = [
            "key": key,
            "action": actionIndex,
            "text": text,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{\"key\":\"\",\"action\":-1,\"text\":\"\"}"
        }
        return json
    }
}
