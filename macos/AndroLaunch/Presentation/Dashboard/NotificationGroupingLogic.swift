//
//  NotificationGroupingLogic.swift
//  AndroLaunch
//
//  Foundation-only decision layer for the premium Notifications tab. Kept free
//  of SwiftUI/AppKit so `Tests/CoreLogicTests/NotificationGroupingLogicTests.swift`
//  can exercise it without a window server:
//
//  - Group records by package, preserving the order the phone (or the fixture)
//    delivered them in. Each group knows its count and the reference copy
//    ("4 notifications mirrored").
//  - Split the groups into the Showing list and the Hidden list. Hidden means
//    the record carried no readable content, the phone marked it secret, or the
//    privacy policy keeps that app off the Mac. Hidden items never expose
//    title/body text to the view.
//  - Turn a raw `AndroidNotificationRecord` into what a card renders: sender,
//    headline and preview. Gmail-style records put the sender in `title` and the
//    subject/snippet in `text`, so the card header can read
//    "Gmail · amanraj.hello@gmail.com" while the card body reads
//    "Axis Bank Cards" / "Elevate your festive celebration!".
//  - Map notification actions: the action index that marks a record read and the
//    reply action index, so the view only shows buttons the phone actually
//    exposes.
//

import Foundation

// MARK: - Display item

/// One notification, shaped for the card UI.
struct NotificationDisplayItem: Equatable, Identifiable {
    /// Phone notification key; also the list identity inside a group.
    let key: String
    let packageName: String
    let postTime: Int64
    /// Sender for email-style notifications (Gmail/Outlook), nil otherwise.
    let sender: String?
    /// Headline (email subject or the notification title).
    let title: String?
    /// Preview line (email snippet or the notification body).
    let body: String?
    /// True when the phone exposed a direct-reply action.
    let hasReply: Bool
    /// Action index for Reply, or -1 when the phone exposes none.
    let replyActionIndex: Int
    /// Action index whose title marks the notification read, when exposed.
    let readActionIndex: Int?
    /// Ongoing notifications cannot be dismissed from the phone.
    let isOngoing: Bool

    var id: String { key }

    /// Dismiss/Turn off is only offered for notifications the phone can remove.
    var canDismiss: Bool { !isOngoing }

    /// The letter shown in the neutral sender avatar, when a sender is known.
    var senderInitial: String? {
        sender.flatMap { NotificationGroupingLogic.initial(for: $0) }
    }

    /// True when there is anything a card can honestly show beyond the app name.
    var hasContent: Bool {
        sender != nil || title != nil || body != nil
    }
}

// MARK: - Groups and sections

/// Every notification from one package, in delivery order.
struct NotificationPackageGroup: Equatable, Identifiable {
    let packageName: String
    /// Resolved app label, or the package string while the catalog has no name.
    let displayName: String
    let items: [NotificationDisplayItem]

    var id: String { packageName }
    var count: Int { items.count }
    var latest: NotificationDisplayItem? { items.first }

    /// Post time of the newest record in delivery order.
    var latestPostTime: Int64 { items.first?.postTime ?? 0 }

    /// "4 notifications mirrored" — the reference product's count line.
    var mirroredCountText: String {
        NotificationGroupingLogic.mirroredCountText(count)
    }
}

/// The two sections the Notifications tab renders.
struct NotificationSections: Equatable {
    let visible: [NotificationPackageGroup]
    let hidden: [NotificationPackageGroup]

    var visibleCount: Int { visible.reduce(0) { $0 + $1.count } }
    var hiddenCount: Int { hidden.reduce(0) { $0 + $1.count } }
    var isEmpty: Bool { visible.isEmpty && hidden.isEmpty }
}

// MARK: - Logic

enum NotificationGroupingLogic {

    /// Separators email notifications use between subject and snippet.
    private static let emailBodySeparators = [" — ", " – ", "\n", " · "]

    /// Packages whose notifications put the sender in the title slot.
    private static let emailPackageNeedles = ["gmail", "mail", "outlook", "proton", "email"]

    // MARK: Sections

    /// Groups records by package and splits them into Showing/Hidden.
    ///
    /// Order is preserved exactly as delivered: the first record of a package
    /// fixes that package's place in the list, and records inside a group stay
    /// in delivery order (the phone returns newest first).
    static func sections(
        records: [AndroidNotificationRecord],
        appNames: [String: String] = [:],
        hideSensitive: Bool = true
    ) -> NotificationSections {
        var visibleOrder: [String] = []
        var hiddenOrder: [String] = []
        var visibleItems: [String: [NotificationDisplayItem]] = [:]
        var hiddenItems: [String: [NotificationDisplayItem]] = [:]

        for record in records {
            let item = displayItem(from: record)
            if isHidden(record, hideSensitive: hideSensitive) {
                if hiddenItems[record.packageName] == nil {
                    hiddenOrder.append(record.packageName)
                }
                // Hidden items must never carry content into the view.
                hiddenItems[record.packageName, default: []].append(
                    NotificationDisplayItem(
                        key: item.key,
                        packageName: item.packageName,
                        postTime: item.postTime,
                        sender: nil,
                        title: nil,
                        body: nil,
                        hasReply: false,
                        replyActionIndex: -1,
                        readActionIndex: nil,
                        isOngoing: item.isOngoing))
            } else {
                if visibleItems[record.packageName] == nil {
                    visibleOrder.append(record.packageName)
                }
                visibleItems[record.packageName, default: []].append(item)
            }
        }

        func makeGroups(
            _ order: [String], _ items: [String: [NotificationDisplayItem]]
        ) -> [NotificationPackageGroup] {
            order.compactMap { packageName in
                guard let items = items[packageName], !items.isEmpty else { return nil }
                return NotificationPackageGroup(
                    packageName: packageName,
                    displayName: displayName(for: packageName, appNames: appNames),
                    items: items)
            }
        }

        return NotificationSections(
            visible: makeGroups(visibleOrder, visibleItems),
            hidden: makeGroups(hiddenOrder, hiddenItems))
    }

    /// True when a record belongs in the Hidden section rather than Showing.
    ///
    /// Contentless records are always hidden — guessing text would be dishonest.
    /// Sensitive apps and phone-marked secret content are hidden while the user
    /// keeps "Hide sensitive apps" on.
    static func isHidden(_ record: AndroidNotificationRecord, hideSensitive: Bool) -> Bool {
        guard record.displayText != nil else { return true }
        // System connectivity/security rows are device status, not personal
        // content; keep them visible even when the phone marks the notification
        // PRIVATE. This is what makes the "Security / battery saver" card match
        // the reference.
        if Self.isSystemStatusPackage(record.packageName) { return false }
        guard hideSensitive else { return false }
        if record.isSensitive { return true }
        return NotificationPrivacy.isSensitivePackage(record.packageName)
    }

    private static func isSystemStatusPackage(_ packageName: String) -> Bool {
        let lowered = packageName.lowercased()
        return lowered == "android"
            || lowered.hasPrefix("com.android.systemui")
            || lowered.hasPrefix("com.miui.security")
            || lowered.hasPrefix("com.miui.notification")
    }

    // MARK: Display shaping

    /// Shapes one raw record into a card item.
    static func displayItem(from record: AndroidNotificationRecord) -> NotificationDisplayItem {
        let parsed = parsedContent(for: record)
        return NotificationDisplayItem(
            key: record.key,
            packageName: record.packageName,
            postTime: record.postTime,
            sender: parsed.sender,
            title: parsed.title,
            body: parsed.body,
            hasReply: record.hasReply,
            replyActionIndex: record.replyActionIndex,
            readActionIndex: readActionIndex(in: record.actions),
            isOngoing: record.isOngoing)
    }

    /// Splits a record's raw title/text into sender, headline and preview.
    ///
    /// Email-style packages put the sender in `title` and "Subject — snippet" in
    /// `text`. Everything else is a plain notification: title + body.
    static func parsedContent(
        for record: AndroidNotificationRecord
    ) -> (sender: String?, title: String?, body: String?) {
        let rawTitle = cleaned(record.title)
        let rawText = cleaned(record.text)

        guard isEmailLike(packageName: record.packageName) else {
            return (nil, rawTitle, rawText)
        }

        // Without a title there is no sender to show; treat the text as a plain
        // notification so the card still says something.
        guard let rawTitle else {
            return (nil, rawText, nil)
        }

        let sender = rawTitle
        guard let rawText else {
            return (sender, nil, nil)
        }

        for separator in emailBodySeparators {
            if let range = rawText.range(of: separator) {
                let subject = cleaned(String(rawText[..<range.lowerBound]))
                let snippet = cleaned(String(rawText[range.upperBound...]))
                return (sender, subject, snippet)
            }
        }
        // A single unseparated line is the subject.
        return (sender, rawText, nil)
    }

    /// True for packages whose notifications follow the sender / subject / snippet shape.
    static func isEmailLike(packageName: String) -> Bool {
        let lowered = packageName.lowercased()
        if lowered == "com.google.android.gm" { return true }
        return emailPackageNeedles.contains { lowered.contains($0) }
    }

    /// The action index that marks a notification read, when the phone exposed one.
    static func readActionIndex(in actions: [AndroidNotificationAction]) -> Int? {
        actions.first { action in
            let title = action.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !title.isEmpty, !action.hasReply else { return false }
            if title.contains("reply") { return false }
            return title.contains("mark as read")
                || title == "read"
                || title.hasPrefix("read ")
        }?.index
    }

    // MARK: Copy

    /// "4 notifications mirrored" / "1 notification mirrored".
    static func mirroredCountText(_ count: Int) -> String {
        count == 1 ? "1 notification mirrored" : "\(count) notifications mirrored"
    }

    /// Display label for a package: catalog name when known, otherwise the
    /// package string as a temporary name until the catalog resolves it.
    static func displayName(for packageName: String, appNames: [String: String]) -> String {
        if let resolved = appNames[packageName]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !resolved.isEmpty
        {
            return resolved
        }
        return packageName
    }

    /// First letter of a sender/name, for the neutral avatar. Skips punctuation
    /// and digits so "amanraj.hello@gmail.com" becomes "A".
    static func initial(for name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scalar = trimmed.unicodeScalars.first(where: {
            CharacterSet.letters.contains($0)
        }) else { return nil }
        return String(Character(scalar)).uppercased()
    }

    // MARK: Helpers

    private static func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
