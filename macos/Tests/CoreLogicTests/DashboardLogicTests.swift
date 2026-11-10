//
//  DashboardLogicTests.swift
//  CoreLogicTests
//
//  Deterministic cover for the Device Dashboard's Foundation-only decisions:
//  the Apps search outcome (app matches vs. "Copy to Android"), notification
//  grouping into Showing/Hidden with temporary names for unresolved packages,
//  and the relative-time copy on notification rows.
//
//  Compiled by scripts/test-macos-logic.sh together with Foundation-only app
//  sources. Entry point: runDashboardLogicTests().
//

import Foundation

func runDashboardLogicTests() {
    dashboardSearchOutcome()
    dashboardNotificationGrouping()
    dashboardRelativeTime()
}

// MARK: - Search

private func dashboardSearchOutcome() {
    suite("DeviceDashboardLogic.searchOutcome") {
        let apps = [
            DashboardSearchItem(id: "a", name: "WhatsApp", packageName: "com.whatsapp"),
            DashboardSearchItem(
                id: "b", name: "AndroLaunch Comp",
                packageName: "com.senpai.androlaunch.companion"),
            DashboardSearchItem(
                id: "c", name: "Photos", packageName: "com.google.android.apps.photos"),
        ]

        expect(
            DeviceDashboardLogic.searchOutcome(query: "", items: apps)
                == .matches(["a", "b", "c"]),
            "blank query shows every app")
        expect(
            DeviceDashboardLogic.searchOutcome(query: "   ", items: apps)
                == .matches(["a", "b", "c"]),
            "whitespace query shows every app")
        expect(
            DeviceDashboardLogic.searchOutcome(query: "photos", items: apps)
                == .matches(["c"]),
            "name match is case-insensitive")
        expect(
            DeviceDashboardLogic.searchOutcome(query: "androlaunch", items: apps)
                == .matches(["b"]),
            "package fragment matches the app")
        expect(
            DeviceDashboardLogic.searchOutcome(query: "androm", items: apps)
                == .copyToAndroid,
            "a partial word that matches no app offers Copy to Android")
        expect(
            DeviceDashboardLogic.searchOutcome(query: "LAUNCH", items: apps)
                == .matches(["b"]),
            "name fragment matches mid-word")
        expect(
            DeviceDashboardLogic.searchOutcome(query: "whatsapp", items: apps)
                == .matches(["a"]),
            "full package name matches")
        expect(
            DeviceDashboardLogic.searchOutcome(query: "Photos", items: apps)
                == .matches(["c"]),
            "exact name still matches through the substring path")
        expect(
            DeviceDashboardLogic.searchOutcome(query: "https://example.com", items: apps)
                == .copyToAndroid,
            "a URL that matches no app becomes Copy to Android")
        expect(
            DeviceDashboardLogic.searchOutcome(query: "meeting at 5", items: apps)
                == .copyToAndroid,
            "free text that matches no app becomes Copy to Android")
        expect(
            DeviceDashboardLogic.searchOutcome(query: "zzz", items: [])
                == .copyToAndroid,
            "non-empty query with an empty catalog becomes Copy to Android")

        expect(DeviceDashboardLogic.isCopyable("hello"), "plain text is copyable")
        expect(!DeviceDashboardLogic.isCopyable("   "), "blank text is not copyable")
        expect(
            !DeviceDashboardLogic.isCopyable(
                String(repeating: "a", count: DeviceDashboardLogic.maxCopyLength + 1)),
            "oversized text is rejected before the clipboard request")
    }
}

// MARK: - Notification grouping

private func dashboardNotificationGrouping() {
    suite("DeviceDashboardLogic.groupNotifications") {
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        func record(
            package: String, key: String, minutesAgo: Double,
            title: String? = "Title", text: String? = "Body",
            sensitive: Bool = false
        ) -> AndroidNotificationRecord {
            AndroidNotificationRecord(
                packageName: package,
                key: key,
                postTime: now - Int64(minutesAgo * 60_000),
                title: title,
                text: text,
                flags: 0,
                isMedia: false,
                isSensitive: sensitive)
        }

        let records = [
            record(package: "com.miui.notification", key: "h1", minutesAgo: 3000, title: nil, text: nil),
            record(package: "com.whatsapp", key: "v1", minutesAgo: 10),
            record(package: "com.whatsapp", key: "v2", minutesAgo: 20),
            record(package: "com.android.systemui", key: "v3", minutesAgo: 5),
        ]

        let names = ["com.whatsapp": "WhatsApp"]
        let sections = DeviceDashboardLogic.groupNotifications(
            records: records, appNames: names, hideSensitive: true)

        expect(sections.visibleCount == 3, "three records have readable content")
        expect(sections.hiddenCount == 1, "the contentless record is hidden")
        expect(sections.visible.count == 2, "two packages in Showing")
        expect(
            sections.visible.first?.packageName == "com.android.systemui",
            "groups are ordered by the newest record")
        expect(
            sections.visible.first(where: { $0.packageName == "com.whatsapp" })?.count == 2,
            "records from one package are grouped")
        expect(
            sections.visible.first(where: { $0.packageName == "com.whatsapp" })?.records
                .map(\.key) == ["v1", "v2"],
            "records inside a group are newest first")
        expect(
            sections.hidden.first?.displayName == "com.miui.notification",
            "an unresolved package keeps its temporary name")

        // Known names win; unknown packages keep the package string.
        expect(
            sections.visible.first(where: { $0.packageName == "com.whatsapp" })?.displayName
                == "WhatsApp",
            "a resolved app name is used for the group label")
        expect(
            DeviceDashboardLogic.displayName(
                for: "com.example.unknown", appNames: ["com.example.unknown": "  "])
                == "com.example.unknown",
            "a blank app name falls back to the temporary package name")

        // Later catalog resolution re-labels the same group instead of splitting it.
        let resolved = DeviceDashboardLogic.groupNotifications(
            records: records,
            appNames: ["com.miui.notification": "System"],
            hideSensitive: true)
        expect(resolved.hidden.first?.displayName == "System", "hidden label resolves later")
        expect(resolved.hidden.count == 1, "label changes never split a group")

        // Sensitive apps and secret content stay hidden while the policy is on.
        let sensitiveRecords = [
            record(package: "com.google.android.gm", key: "s1", minutesAgo: 1),
            record(package: "com.senpai.finance", key: "s2", minutesAgo: 2),
            record(package: "com.whatsapp", key: "s3", minutesAgo: 3, sensitive: true),
        ]
        let hidden = DeviceDashboardLogic.groupNotifications(
            records: sensitiveRecords, appNames: [:], hideSensitive: true)
        expect(hidden.visibleCount == 1, "gmail is visible; finance and secret rows stay hidden")
        expect(hidden.hiddenCount == 2, "finance and secret rows appear in the Hidden section")

        let policyOff = DeviceDashboardLogic.groupNotifications(
            records: sensitiveRecords, appNames: [:], hideSensitive: false)
        expect(policyOff.visibleCount == 3, "turning the policy off shows those rows")

        // No content at all still hides a record even with the policy off.
        let noContent = DeviceDashboardLogic.groupNotifications(
            records: [record(package: "com.example.app", key: "n1", minutesAgo: 1, title: nil, text: nil)],
            appNames: [:], hideSensitive: false)
        expect(noContent.hiddenCount == 1, "contentless records are always hidden")
        expect(noContent.visibleCount == 0, "contentless records never show")

        let empty = DeviceDashboardLogic.groupNotifications(records: [], appNames: [:])
        expect(empty.isEmpty && empty.visibleCount == 0 && empty.hiddenCount == 0, "empty list")
    }
}

// MARK: - Relative time

private func dashboardRelativeTime() {
    suite("DeviceDashboardLogic.relativeTime") {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        expect(
            DeviceDashboardLogic.relativeTime(postTimeMilliseconds: 0, now: now) == "—",
            "a missing post time is a dash, not a guess")
        expect(
            DeviceDashboardLogic.relativeTime(since: now.addingTimeInterval(-2), now: now)
                == "just now",
            "very recent notifications read just now")
        expect(
            DeviceDashboardLogic.relativeTime(since: now.addingTimeInterval(-9), now: now)
                == "9 sec. ago",
            "seconds read as sec.")
        expect(
            DeviceDashboardLogic.relativeTime(since: now.addingTimeInterval(-90), now: now)
                == "1 min. ago",
            "minutes read as min.")
        expect(
            DeviceDashboardLogic.relativeTime(since: now.addingTimeInterval(-3600), now: now)
                == "1 hr. ago",
            "one hour is singular")
        expect(
            DeviceDashboardLogic.relativeTime(since: now.addingTimeInterval(-2 * 86_400), now: now)
                == "2 days ago",
            "days read naturally")
        expect(
            DeviceDashboardLogic.relativeTime(since: now.addingTimeInterval(-86_400), now: now)
                == "1 day ago",
            "one day is singular")
        expect(
            DeviceDashboardLogic.relativeTime(since: now.addingTimeInterval(-21 * 86_400), now: now)
                == "3 wks ago",
            "weeks read as wks")
        expect(
            DeviceDashboardLogic.relativeTime(
                since: now.addingTimeInterval(120), now: now) == "just now",
            "clock skew never prints a negative age")

        let millis = Int64(now.timeIntervalSince1970 * 1000) - 9_000
        expect(
            DeviceDashboardLogic.relativeTime(postTimeMilliseconds: millis, now: now)
                == "9 sec. ago",
            "milliseconds convert to the same relative copy")
    }
}
