//
//  NotificationGroupingLogicTests.swift
//  CoreLogicTests
//
//  Deterministic cover for the premium Notifications tab's Foundation-only
//  decision layer: package grouping that preserves delivery order, per-group
//  counts and the "N notifications mirrored" copy, the Showing/Hidden split
//  (contentless records, phone-marked secrets, sensitive packages), the
//  sender/subject/snippet shaping for mail-style records, and the action-index
//  mapping the cards use for Delete / Mark as read / Reply.
//
//  Compiled by scripts/test-macos-logic.sh together with Foundation-only app
//  sources. Entry point: runNotificationGroupingLogicTests().
//

import Foundation

func runNotificationGroupingLogicTests() {
    notificationGroupingOrder()
    notificationGroupingHiddenSplit()
    notificationGroupingDisplayShaping()
    notificationGroupingActionMapping()
    notificationGroupingCopy()
}

// MARK: - Fixtures

private func record(
    package: String,
    key: String,
    minutesAgo: Double = 0,
    title: String? = "Title",
    text: String? = "Body",
    actions: [AndroidNotificationAction] = [],
    sensitive: Bool = false,
    flags: Int = 0
) -> AndroidNotificationRecord {
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    return AndroidNotificationRecord(
        packageName: package,
        key: key,
        postTime: now - Int64(minutesAgo * 60_000),
        title: title,
        text: text,
        flags: flags,
        isMedia: false,
        actions: actions,
        isSensitive: sensitive)
}

// MARK: - Ordering & counts

private func notificationGroupingOrder() {
    suite("NotificationGroupingLogic.sections ordering") {
        let records = [
            record(package: "com.whatsapp", key: "w1", minutesAgo: 10),
            record(package: "com.google.android.gm", key: "g1", minutesAgo: 20),
            record(package: "com.whatsapp", key: "w2", minutesAgo: 30),
        ]
        let sections = NotificationGroupingLogic.sections(
            records: records, appNames: ["com.whatsapp": "WhatsApp"], hideSensitive: false)

        expect(sections.visible.count == 2, "two packages grouped")
        expect(
            sections.visible.map(\.packageName) == ["com.whatsapp", "com.google.android.gm"],
            "group order follows first delivery, not an alphabetical sort")
        expect(
            sections.visible.first?.items.map(\.key) == ["w1", "w2"],
            "items inside a group keep delivery order")
        expect(sections.visible.first?.count == 2, "group count")
        expect(sections.visibleCount == 3, "section count sums every item")
        expect(sections.hiddenCount == 0, "nothing hidden")
        expect(sections.isEmpty == false, "non-empty sections")

        let empty = NotificationGroupingLogic.sections(records: [], appNames: [:])
        expect(empty.isEmpty && empty.visibleCount == 0 && empty.hiddenCount == 0, "empty input")
    }
}

// MARK: - Hidden split

private func notificationGroupingHiddenSplit() {
    suite("NotificationGroupingLogic.sections hidden split") {
        let records = [
            record(package: "com.whatsapp", key: "v1"),
            record(package: "com.miui.notification", key: "h1", title: nil, text: nil),
            record(package: "com.google.android.gm", key: "g1"),
            record(package: "com.senpai.finance", key: "f1"),
            record(package: "com.whatsapp", key: "v2", sensitive: true),
        ]

        let hiddenOn = NotificationGroupingLogic.sections(
            records: records, appNames: [:], hideSensitive: true)
        expect(hiddenOn.visibleCount == 2, "WhatsApp and mail stay visible")
        expect(hiddenOn.hiddenCount == 3, "contentless, finance and secret rows are hidden")
        expect(
            hiddenOn.hidden.map(\.packageName)
                == [
                    "com.miui.notification", "com.senpai.finance", "com.whatsapp",
                ],
            "hidden group order is preserved")

        // Hidden items must never carry content into the view.
        let hiddenItem = hiddenOn.hidden.first?.items.first
        expect(hiddenItem?.title == nil && hiddenItem?.body == nil && hiddenItem?.sender == nil,
            "hidden items expose no text")
        expect(hiddenItem?.hasReply == false && hiddenItem?.readActionIndex == nil,
            "hidden items expose no actions")

        let hiddenOff = NotificationGroupingLogic.sections(
            records: records, appNames: [:], hideSensitive: false)
        expect(hiddenOff.visibleCount == 4, "policy off reveals mail/finance/secret rows")
        expect(hiddenOff.hiddenCount == 1, "contentless rows stay hidden even with the policy off")

        let ongoing = record(
            package: "com.android.systemui", key: "o1", flags: 0x0000_0002)
        let ongoingItem = NotificationGroupingLogic.sections(
            records: [ongoing], appNames: [:], hideSensitive: false
        ).visible.first?.items.first
        expect(ongoingItem?.isOngoing == true, "ongoing flag survives shaping")
        expect(ongoingItem?.canDismiss == false, "ongoing notifications cannot be deleted")
    }
}

// MARK: - Display shaping

private func notificationGroupingDisplayShaping() {
    suite("NotificationGroupingLogic.displayItem") {
        // Gmail: sender in title, "Subject — snippet" in text.
        let gmail = record(
            package: "com.google.android.gm",
            key: "g1",
            title: "amanraj.hello@gmail.com",
            text: "Axis Bank Cards — Elevate your festive celebration!")
        let item = NotificationGroupingLogic.displayItem(from: gmail)
        expect(item.sender == "amanraj.hello@gmail.com", "mail sender comes from the title")
        expect(item.title == "Axis Bank Cards", "mail subject is split from the snippet")
        expect(item.body == "Elevate your festive celebration!", "mail snippet becomes the body")
        expect(item.senderInitial == "A", "sender initial for the neutral avatar")

        // A plain notification keeps title + body and has no sender.
        let plain = record(
            package: "com.android.systemui",
            key: "s1",
            title: "Wireless debugging connected",
            text: "Tap to turn off wireless debugging")
        let plainItem = NotificationGroupingLogic.displayItem(from: plain)
        expect(plainItem.sender == nil, "plain notifications have no sender")
        expect(plainItem.title == "Wireless debugging connected", "plain title")
        expect(plainItem.body == "Tap to turn off wireless debugging", "plain body")

        // Mail without the separator: the whole line is the subject.
        let singleLine = record(
            package: "com.google.android.gm",
            key: "g2",
            title: "amanraj.hello@gmail.com",
            text: "Statement ready")
        let singleItem = NotificationGroupingLogic.displayItem(from: singleLine)
        expect(singleItem.title == "Statement ready" && singleItem.body == nil,
            "unseparated mail text becomes the subject")

        // Mail with only a sender.
        let senderOnly = record(
            package: "com.google.android.gm",
            key: "g3",
            title: "amanraj.hello@gmail.com",
            text: nil)
        let senderOnlyItem = NotificationGroupingLogic.displayItem(from: senderOnly)
        expect(senderOnlyItem.sender == "amanraj.hello@gmail.com", "sender survives")
        expect(senderOnlyItem.title == nil && senderOnlyItem.body == nil, "no invented body")

        // Non-mail package that happens to include a sender-ish title.
        let messaging = record(
            package: "com.whatsapp",
            key: "w1",
            title: "Aman",
            text: "Are we still on for tonight?")
        let messagingItem = NotificationGroupingLogic.displayItem(from: messaging)
        expect(messagingItem.sender == nil, "only mail-style packages get a sender")
        expect(messagingItem.title == "Aman", "messaging title stays the headline")
        expect(
            messagingItem.body == "Are we still on for tonight?",
            "messaging body stays the preview")

        // Initials skip punctuation/digits.
        expect(NotificationGroupingLogic.initial(for: "amanraj.hello@gmail.com") == "A",
            "initial skips punctuation")
        expect(NotificationGroupingLogic.initial(for: "  -  ") == nil, "no letters → no initial")

        expect(
            NotificationGroupingLogic.isEmailLike(packageName: "com.google.android.gm"),
            "Gmail is mail-like")
        expect(
            !NotificationGroupingLogic.isEmailLike(packageName: "com.whatsapp"),
            "WhatsApp is not mail-like")
    }
}

// MARK: - Actions

private func notificationGroupingActionMapping() {
    suite("NotificationGroupingLogic actions") {
        let withActions = record(
            package: "com.google.android.gm",
            key: "g1",
            title: "amanraj.hello@gmail.com",
            text: "Axis Bank Cards — Elevate your festive celebration!",
            actions: [
                AndroidNotificationAction(index: 0, title: "Mark as read", hasReply: false),
                AndroidNotificationAction(index: 1, title: "Archive", hasReply: false),
                AndroidNotificationAction(index: 2, title: "Reply", hasReply: true),
            ])
        let item = NotificationGroupingLogic.displayItem(from: withActions)
        expect(item.readActionIndex == 0, "Mark as read action index is found")
        expect(item.hasReply, "reply action detected")
        expect(item.replyActionIndex == 2, "reply action index comes from the record")

        let noRead = record(
            package: "com.whatsapp",
            key: "w1",
            actions: [
                AndroidNotificationAction(index: 0, title: "Reply", hasReply: true)
            ])
        expect(
            NotificationGroupingLogic.displayItem(from: noRead).readActionIndex == nil,
            "no read action → nil so the view hides the button")

        // A reply action titled "Reply" must never be treated as read.
        let replyOnly = record(
            package: "com.whatsapp",
            key: "w2",
            actions: [AndroidNotificationAction(index: 0, title: "Reply", hasReply: true)])
        expect(
            NotificationGroupingLogic.readActionIndex(in: replyOnly.actions) == nil,
            "a reply action is not a read action")

        let readVariants = [
            AndroidNotificationAction(index: 3, title: "Read", hasReply: false),
            AndroidNotificationAction(index: 4, title: "Mark as read", hasReply: false),
        ]
        expect(
            NotificationGroupingLogic.readActionIndex(in: readVariants) == 3,
            "case-insensitive read detection keeps the real index")

        let noActions = record(package: "com.whatsapp", key: "w3")
        let noActionsItem = NotificationGroupingLogic.displayItem(from: noActions)
        expect(noActionsItem.hasReply == false && noActionsItem.readActionIndex == nil,
            "dumpsys records expose no reply/read actions")
        expect(noActionsItem.replyActionIndex == -1, "missing reply index is -1")
    }
}

// MARK: - Copy

private func notificationGroupingCopy() {
    suite("NotificationGroupingLogic copy") {
        expect(
            NotificationGroupingLogic.mirroredCountText(4) == "4 notifications mirrored",
            "plural count copy")
        expect(
            NotificationGroupingLogic.mirroredCountText(1) == "1 notification mirrored",
            "singular count copy")
        expect(
            NotificationGroupingLogic.displayName(
                for: "com.example.unknown", appNames: [:]) == "com.example.unknown",
            "unresolved packages keep a temporary name")
        expect(
            NotificationGroupingLogic.displayName(
                for: "com.whatsapp", appNames: ["com.whatsapp": "WhatsApp"]) == "WhatsApp",
            "resolved catalog names win")
        expect(
            NotificationGroupingLogic.displayName(
                for: "com.whatsapp", appNames: ["com.whatsapp": "   "]) == "com.whatsapp",
            "blank catalog names fall back to the package")
    }
}
