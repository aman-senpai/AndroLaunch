//
//  NotificationParserTests.swift
//  CoreLogicTests
//
//  Fixtures for the `dumpsys notification` parser. The dump format is not a
//  public contract, so these cases pin the behaviour we rely on: never replay
//  archived notifications, never invent text that was redacted, and stay quiet
//  on output we do not understand.
//

import Foundation

private func dump(_ records: [String], after: String? = nil) -> String {
    var lines = ["Current Notification Manager state:", "  Notification List:"]
    lines.append(contentsOf: records)
    if let after { lines.append(after) }
    return lines.joined(separator: "\n")
}

private func record(
    pkg: String,
    key: String = "0|pkg|1|null|1000",
    flags: String = "0x10",
    postTime: Int64 = 1_699_000_000_000,
    title: String? = nil,
    text: String? = nil,
    extraLines: [String] = []
) -> String {
    var lines = [
        "    NotificationRecord(0x0a1b: pkg=\(pkg) user=0 id=1 tag=null key=\(key): "
            + "Notification(pri=0 flags=\(flags) when=1699000000000)"
    ]
    var extras: [String] = []
    if let title { extras.append("        android.title=String (\(title))") }
    if let text { extras.append("        android.text=String (\(text))") }
    extras.append(contentsOf: extraLines)
    if !extras.isEmpty {
        lines.append("      extras={")
        lines.append(contentsOf: extras)
        lines.append("      }")
    }
    lines.append("      posttime=\(postTime)")
    return lines.joined(separator: "\n")
}

func runNotificationParserTests() {
    suite("NotificationDumpParser") {
        let parsed = NotificationDumpParser.parse(
            dump([
                record(
                    pkg: "com.whatsapp", key: "0|com.whatsapp|42|null|10123",
                    postTime: 1_699_000_000_123, title: "Alice", text: "See you at 8")
            ]))
        expect(parsed?.count == 1, "parses one record")
        let first = parsed?.first
        expect(first?.packageName == "com.whatsapp", "package name")
        expect(first?.key == "0|com.whatsapp|42|null|10123", "notification key")
        expect(first?.postTime == 1_699_000_000_123, "post time")
        expect(first?.title == "Alice", "title")
        expect(first?.text == "See you at 8", "text")
        expect(first?.isOngoing == false, "normal notification is not ongoing")
        expect(first?.isGroupSummary == false, "normal notification is not a summary")
        expect(first?.isMedia == false, "normal notification is not media")
        expect(first?.displayText == "Alice — See you at 8", "display text combines title and body")
        expect(
            first?.fingerprint == "0|com.whatsapp|42|null|10123|1699000000123",
            "fingerprint is key plus post time")
    }

    suite("NotificationDumpParser section handling") {
        expect(NotificationDumpParser.parse("") == nil, "empty output is unparseable")
        expect(
            NotificationDumpParser.parse("Current Notification Manager state:\n  mArchive:\n    x")
                == nil,
            "output without a notification list is unparseable")
        expect(
            NotificationDumpParser.parse(dump([]))?.isEmpty == true,
            "present but empty section is zero notifications, not nil")
        expect(
            NotificationDumpParser.hasNotificationSection(dump([])),
            "section detection agrees")
        expect(
            !NotificationDumpParser.hasNotificationSection("mArchive:\n  nothing"),
            "no section reported when the header is missing")
    }

    suite("NotificationDumpParser archived records") {
        let output = dump(
            [
                record(pkg: "com.slack", key: "0|com.slack|1|null|1", title: "Live", text: "now")
            ],
            after: "  mArchive:\n" + record(pkg: "com.old", key: "0|com.old|9|null|9", title: "Old", text: "past")
        )
        let parsed = NotificationDumpParser.parse(output)
        expect(parsed?.count == 1, "archived records after the terminator are not replayed")
        expect(parsed?.contains { $0.packageName == "com.old" } == false, "old package excluded")
    }

    suite("NotificationDumpParser flags and media") {
        let ongoing = NotificationDumpParser.parse(
            dump([record(pkg: "com.android.music", flags: "0x2", title: "Playing")]))
        expect(ongoing?.first?.isOngoing == true, "ongoing flag detected")

        let summary = NotificationDumpParser.parse(
            dump([record(pkg: "com.mail", flags: "0x200", title: "3 new")]))
        expect(summary?.first?.isGroupSummary == true, "group summary flag detected")

        let media = NotificationDumpParser.parse(
            dump([
                record(
                    pkg: "com.spotify.music", title: "Song",
                    extraLines: ["        android.mediaSession=String (Token)"]
                )
            ]))
        expect(media?.first?.isMedia == true, "media session detected")
    }

    suite("NotificationDumpParser redaction and escaping") {
        let redacted = NotificationDumpParser.parse(
            dump([record(pkg: "com.bank", title: "Payment")]))
        expect(redacted?.first?.title == "Payment", "title survives")
        expect(redacted?.first?.text == nil, "missing text stays nil so the mirror can skip it")
        expect(redacted?.first?.displayText == "Payment", "display text falls back to the title")

        let escaped = NotificationDumpParser.parse(
            dump([record(pkg: "com.chat", title: "Bob", text: #"line one\nline two"#)]))
        expect(escaped?.first?.text == "line one line two", "escaped newlines are flattened")

        let nullText = NotificationDumpParser.parse(
            dump([record(pkg: "com.chat", text: "null")]))
        expect(nullText?.first?.text == nil, "literal null text is dropped")

        let garbage = NotificationDumpParser.parse(
            "Current Notification Manager state:\n  Notification List:\n    <<<garbage>>>")
        expect(garbage?.isEmpty == true, "garbage inside the section yields no records")
    }
}
