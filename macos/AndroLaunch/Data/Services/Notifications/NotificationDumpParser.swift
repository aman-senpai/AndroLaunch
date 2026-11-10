//
//  NotificationDumpParser.swift
//  AndroLaunch
//
//  Parses the text printed by `adb shell dumpsys notification` (with or without
//  `--noredact`). The dump format is not a public contract and differs across
//  Android versions, OEM skins and even point releases, so this parser is
//  deliberately line-oriented and forgiving:
//
//  - It only looks inside the "Notification List:" / "Notification records:"
//    section, never the archive/history sections that also contain records.
//  - Every field is optional; a record that cannot be understood is dropped, and
//    a dump with no notification section at all returns nil (the caller treats
//    that as "unparseable", not "zero notifications").
//  - It never traps: no force-unwraps, no array indexing, no assumptions about
//    indentation or field order.
//

import Foundation

/// One action button exposed by a notification.
struct AndroidNotificationAction: Equatable {
    /// Index into the phone notification's `actions` array.
    let index: Int
    let title: String
    /// True when the action accepts free-form text (direct reply).
    let hasReply: Bool
}

/// One notification entry extracted from a `dumpsys notification` dump or read
/// through the companion's notification listener.
///
/// The `dumpsys` parser fills the flags-based fields; the companion path fills
/// `actions` and `isSensitive` from real platform metadata. Both produce the same
/// type so mirroring, filtering and delivery stay in one place.
struct AndroidNotificationRecord: Equatable {
    /// Reverse-DNS package that posted the notification.
    let packageName: String
    /// Notification key (`userId|package|id|tag|uid`), or a synthesised key when
    /// the dump did not include one.
    let key: String
    /// Post time in milliseconds since the epoch, or 0 when the dump omitted it.
    let postTime: Int64
    let title: String?
    let text: String?
    /// `Notification.flags` bit mask. 0 when absent.
    let flags: Int
    /// True when the dump looks like a media-style notification.
    let isMedia: Bool
    /// Action buttons, when read through the companion (empty for a dump).
    var actions: [AndroidNotificationAction] = []
    /// The posting app marked this notification secret.
    var isSensitive: Bool = false

    /// True when the phone app offers inline reply for this notification.
    var hasReply: Bool { actions.contains { $0.hasReply } }

    /// Action index to use for a reply, or -1.
    var replyActionIndex: Int {
        actions.first(where: { $0.hasReply })?.index ?? -1
    }

    /// Stable de-duplication fingerprint: key plus post time.
    var fingerprint: String { "\(key)|\(postTime)" }

    /// True for ongoing / foreground-service notifications that the user cannot
    /// dismiss on the phone; mirroring them would be noise.
    var isOngoing: Bool { flags & (0x0000_0002 | 0x0000_0040) != 0 }

    /// Auto-group / group-summary row. Its text usually comes from the children
    /// anyway, so it is skipped to avoid duplicate banners.
    var isGroupSummary: Bool { flags & 0x0000_0200 != 0 }

    /// Best available text, used only to decide whether the record has any
    /// readable content at all.
    var displayText: String? {
        let pieces = [title, text].compactMap { value -> String? in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                !trimmed.isEmpty
            else { return nil }
            return trimmed
        }
        guard !pieces.isEmpty else { return nil }
        return pieces.joined(separator: " — ")
    }
}

enum NotificationDumpParser {
    // MARK: - Section detection

    /// Returns nil when the dump contains no recognisable notification list,
    /// which the caller interprets as "this device/OS does not expose readable
    /// notifications". An empty array means "the section exists and is empty".
    static func parse(_ output: String) -> [AndroidNotificationRecord]? {
        guard !output.isEmpty else { return nil }
        guard let section = notificationSectionLines(in: output) else { return nil }
        return parseRecords(in: section)
    }

    /// True when the dump contains the notification-list section. Used to tell a
    /// redacted-but-valid dump apart from a command that returned nothing.
    static func hasNotificationSection(_ output: String) -> Bool {
        notificationSectionLines(in: output) != nil
    }

    /// `nil` when there is no notification-list section at all; an empty array
    /// when the section is present but lists no notifications.
    private static func notificationSectionLines(in output: String) -> [String]? {
        let lines = output.components(separatedBy: .newlines)
        guard
            let start = lines.firstIndex(where: { isNotificationListHeader($0) })
        else { return nil }

        var body: [String] = []
        for line in lines[(start + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if isRecordStart(trimmed) {
                body.append(line)
                continue
            }
            if isSectionTerminator(line) { break }
            body.append(line)
        }
        return body
    }

    private static func isNotificationListHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let lowered = trimmed.lowercased()
        return lowered.hasPrefix("notification list:")
            || lowered.hasPrefix("notification records:")
            || lowered == "notification list"
    }

    /// Sections that follow the live notification list in various Android dumps.
    /// Hitting one of these stops parsing so archived/past notifications are not
    /// mirrored again.
    private static func isSectionTerminator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let leading = leadingSpaceCount(line)
        if leading <= 2 && trimmed.hasSuffix(":") && !trimmed.hasPrefix("NotificationRecord") {
            return true
        }
        let terminators = [
            "mArchive", "Archive:", "mHistory", "History:", "mSnoozed",
            "Snoozed notifications", "Notification Summaries", "Notification Counts",
            "Notification Listeners", "Notification Modes", "Ranking Config",
            "Usage Stats", "mUseAttentionLight", "mHandler", "mPolicy",
            "mSoundNotificationKeys", "mToastQueue", "Zen Mode", "mAssistants",
            "Notification Assistant", "mTempWhitelist", "mSummaryByGroupKey",
        ]
        return terminators.contains { trimmed.hasPrefix($0) }
    }

    private static func leadingSpaceCount(_ line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " {
                count += 1
            } else if character == "\t" {
                count += 4
            } else {
                break
            }
        }
        return count
    }

    private static func isRecordStart(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("NotificationRecord")
    }

    // MARK: - Record parsing

    private static func parseRecords(in lines: [String]) -> [AndroidNotificationRecord] {
        var records: [AndroidNotificationRecord] = []
        var block: [String] = []

        func flush() {
            guard !block.isEmpty else { return }
            if let record = parseRecord(block.joined(separator: "\n")) {
                records.append(record)
            }
            block.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isRecordStart(trimmed) {
                flush()
                block.append(line)
            } else if !block.isEmpty {
                block.append(line)
            }
        }
        flush()
        return records
    }

    private static func parseRecord(_ block: String) -> AndroidNotificationRecord? {
        let firstLine = block.components(separatedBy: .newlines).first ?? block

        guard let packageName = capture(CompiledRegex.packageName, in: firstLine),
            !packageName.isEmpty
        else { return nil }

        let key =
            capture(CompiledRegex.key, in: firstLine)
            ?? synthesisedKey(block: block, packageName: packageName)

        let postTime =
            capture(CompiledRegex.postTime, in: block).flatMap { Int64($0) }
            ?? capture(CompiledRegex.whenTime, in: firstLine).flatMap { Int64($0) }
            ?? 0

        let flags = capture(CompiledRegex.flags, in: firstLine)
            .flatMap(parseFlags) ?? 0

        let title = extraValue(named: ["android.title", "android.title.big"], in: block)
        let text =
            extraValue(
                named: [
                    "android.text", "android.bigText", "android.summaryText", "android.subText",
                ], in: block)
            ?? extraValue(named: ["tickerText", "android.tickerText"], in: block)

        let lowered = block.lowercased()
        let isMedia =
            lowered.contains("mediastyle")
            || lowered.contains("android.mediasession")
            || lowered.contains("notification$mediastyle")

        return AndroidNotificationRecord(
            packageName: packageName,
            key: key,
            postTime: postTime,
            title: title,
            text: text,
            flags: flags,
            isMedia: isMedia
        )
    }

    private static func synthesisedKey(block: String, packageName: String) -> String {
        let identifier = capture(CompiledRegex.identifier, in: block) ?? "0"
        let tag = capture(CompiledRegex.tag, in: block) ?? "null"
        return "\(packageName)|\(identifier)|\(tag)"
    }

    private static func parseFlags(_ raw: String) -> Int? {
        if raw.lowercased().hasPrefix("0x") {
            return Int(raw.dropFirst(2), radix: 16)
        }
        return Int(raw)
    }

    // MARK: - Extras extraction

    /// Looks for `name=Class (value)` (or `name=value`) lines in a record block.
    private static func extraValue(named names: [String], in block: String) -> String? {
        for line in block.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for name in names {
                let prefix = name + "="
                guard trimmed.hasPrefix(prefix) else { continue }
                let raw = String(trimmed.dropFirst(prefix.count))
                if let value = decodeExtra(raw) { return value }
            }
        }
        // Some dumps print an entire extras map on a single line.
        for name in names {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: name)
                + #"=([A-Za-z0-9_.$]+)\s*\(([^)\n]*)\)"#
            if let match = firstMatch(pattern, in: block, group: 2),
                let value = decodeExtra(match)
            {
                return value
            }
        }
        return nil
    }

    private static func decodeExtra(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }

        let lowered = value.lowercased()
        if lowered == "null" || lowered == "nil" || lowered == "redacted" || lowered == "[redacted]" {
            return nil
        }

        // Unwrap `String (Hello)`, `CharSequence (Hello)`, `SpannableString (...)`.
        if let open = value.firstIndex(of: "(") {
            let prefix = String(value[value.startIndex..<open]).trimmingCharacters(in: .whitespaces)
            let looksLikeClass = !prefix.isEmpty
                && prefix.rangeOfCharacter(from: .whitespaces) == nil
                && prefix.rangeOfCharacter(from: CharacterSet.letters.union(CharacterSet(charactersIn: ".$")))
                    != nil
                && prefix.allSatisfy {
                    $0.isLetter || $0.isNumber || $0 == "." || $0 == "$" || $0 == "_"
                }
            if looksLikeClass {
                var inner = String(value[value.index(after: open)...])
                // Values may contain ")" themselves; only strip the final wrapper.
                if inner.hasSuffix(")") { inner.removeLast() }
                value = inner
            }
        }

        // A bare wrapper class name (e.g. `android.text=SpannableString` on a
        // redacted build) is a type marker, not text.
        let bareWrapperNames: Set<String> = [
            "string", "charsequence", "spannablestring", "spannedstring", "boolean",
        ]
        if !value.contains("("), bareWrapperNames.contains(value.lowercased()) {
            return nil
        }

        // dumpsys escapes control characters rather than printing raw newlines.
        value =
            value
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\t", with: " ")
            .replacingOccurrences(of: "\\r", with: " ")
            .replacingOccurrences(of: "\\u0000", with: "")

        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLowered = value.lowercased()
        if finalLowered == "null" || finalLowered == "nil" || finalLowered == "redacted"
            || finalLowered == "[redacted]"
        {
            return nil
        }
        guard !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Small regex helpers

    /// Compiled once for the whole process: the parser runs every few seconds and
    /// `NSRegularExpression` compilation is comparatively expensive.
    private enum CompiledRegex {
        static let packageName = try? NSRegularExpression(pattern: #"\bpkg=([A-Za-z0-9._]+)"#)
        static let key = try? NSRegularExpression(pattern: #"\bkey=([^\s:]+)"#)
        static let postTime = try? NSRegularExpression(pattern: #"\bposttime=(-?\d+)"#)
        static let whenTime = try? NSRegularExpression(pattern: #"\bwhen=(\d+)"#)
        static let flags = try? NSRegularExpression(pattern: #"\bflags=(0x[0-9a-fA-F]+|\d+)"#)
        static let identifier = try? NSRegularExpression(pattern: #"\bid=(\d+)"#)
        static let tag = try? NSRegularExpression(pattern: #"\btag=(\S+)"#)
    }

    private static func capture(
        _ regex: NSRegularExpression?, in text: String, group: Int = 1
    ) -> String? {
        guard let regex else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
            match.numberOfRanges > group,
            let valueRange = Range(match.range(at: group), in: text)
        else { return nil }
        return String(text[valueRange])
    }

    private static func firstMatch(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
            match.numberOfRanges > group,
            let valueRange = Range(match.range(at: group), in: text)
        else { return nil }
        return String(text[valueRange])
    }
}
