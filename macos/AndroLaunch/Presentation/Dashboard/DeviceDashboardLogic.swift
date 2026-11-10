//
//  DeviceDashboardLogic.swift
//  AndroLaunch
//
//  Foundation-only decision logic for the compact Device Dashboard. Kept free
//  of SwiftUI/AppKit so `Tests/CoreLogicTests/DashboardLogicTests.swift` can
//  exercise it without a window server:
//
//  - Search outcome: matching apps keep the grid, a non-empty query that matches
//    nothing becomes a "Copy to Android" offer (the reference product sends the
//    typed text to the phone clipboard).
//  - Notification grouping: records are grouped per package, split into the
//    visible list and the "Hidden" list (no displayable content, or content the
//    privacy policy keeps off the Mac). A package without a resolved app label
//    keeps a temporary name (the package string) until the catalog arrives.
//  - Relative time copy for notification rows.
//

import Foundation

// MARK: - Search

/// One searchable app, reduced to the fields the dashboard decision needs.
struct DashboardSearchItem: Equatable {
    let id: String
    let name: String
    let packageName: String
}

/// What the Apps tab should render for the current query.
enum DashboardSearchOutcome: Equatable {
    /// IDs of the apps that match, in the caller's order. A blank query returns
    /// every app, so the grid can render "all apps" through the same path.
    case matches([String])
    /// The query matched no app: offer to send the text to the phone clipboard.
    case copyToAndroid
}

// MARK: - Notifications

/// A package's notifications, in newest-first order.
struct DashboardNotificationGroup: Equatable, Identifiable {
    let packageName: String
    /// Resolved app label, or the package string while the catalog has no name.
    let displayName: String
    let records: [AndroidNotificationRecord]

    var id: String { packageName }
    var count: Int { records.count }

    /// Post time of the newest record, or 0 when the dump carried no time.
    var latestPostTime: Int64 { records.first?.postTime ?? 0 }

    var latest: AndroidNotificationRecord? { records.first }
}

/// The two sections the Notifications tab renders.
struct DashboardNotificationSections: Equatable {
    let visible: [DashboardNotificationGroup]
    let hidden: [DashboardNotificationGroup]

    var visibleCount: Int { visible.reduce(0) { $0 + $1.count } }
    var hiddenCount: Int { hidden.reduce(0) { $0 + $1.count } }
    var isEmpty: Bool { visible.isEmpty && hidden.isEmpty }
}

// MARK: - Logic

enum DeviceDashboardLogic {

    // MARK: Search

    /// Copy-to-Android accepts short text and URLs; the same ceiling as
    /// `CopyToAndroidService` keeps a huge paste from being attempted.
    static let maxCopyLength = 200_000

    /// Decides what the Apps tab shows for `query`.
    ///
    /// - Blank/whitespace query → every item, so the default grid is one path.
    /// - Any case-insensitive name or package substring → those items.
    /// - Nothing matched → the "Copy to Android" offer.
    static func searchOutcome(
        query: String, items: [DashboardSearchItem]
    ) -> DashboardSearchOutcome {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .matches(items.map(\.id))
        }
        let lowered = trimmed.lowercased()
        let matches = items.filter { item in
            item.name.lowercased().contains(lowered)
                || item.packageName.lowercased().contains(lowered)
        }
        if matches.isEmpty { return .copyToAndroid }
        return .matches(matches.map(\.id))
    }

    /// True when `text` can actually be handed to the phone clipboard.
    static func isCopyable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxCopyLength
    }

    // MARK: Notifications

    /// Splits records into the visible list and the hidden list and groups each
    /// by package.
    ///
    /// A record is hidden when:
    /// - it has no readable title/body (locked phone, redacted dump, media
    ///   placeholder) — guessing text would be dishonest, and
    /// - the privacy policy holds it back (`isSensitive` from the phone, or a
    ///   finance/password/authenticator/email package while the user keeps
    ///   "Hide sensitive apps" on).
    ///
    /// Group labels come from `appNames`; a package with no label keeps the
    /// package string as a temporary name, so several records from the same
    /// unknown app still collect into one group.
    static func groupNotifications(
        records: [AndroidNotificationRecord],
        appNames: [String: String] = [:],
        hideSensitive: Bool = true
    ) -> DashboardNotificationSections {
        var visible: [String: [AndroidNotificationRecord]] = [:]
        var hidden: [String: [AndroidNotificationRecord]] = [:]

        for record in records {
            let bucketKey = record.packageName
            if isHidden(record, hideSensitive: hideSensitive) {
                hidden[bucketKey, default: []].append(record)
            } else {
                visible[bucketKey, default: []].append(record)
            }
        }

        func makeGroups(_ buckets: [String: [AndroidNotificationRecord]])
            -> [DashboardNotificationGroup]
        {
            buckets
                .map { packageName, records in
                    let sorted = records.sorted { lhs, rhs in
                        lhs.postTime > rhs.postTime
                    }
                    return DashboardNotificationGroup(
                        packageName: packageName,
                        displayName: displayName(for: packageName, appNames: appNames),
                        records: sorted)
                }
                .sorted { lhs, rhs in
                    if lhs.latestPostTime != rhs.latestPostTime {
                        return lhs.latestPostTime > rhs.latestPostTime
                    }
                    return lhs.displayName.localizedStandardCompare(rhs.displayName)
                        == .orderedAscending
                }
        }

        return DashboardNotificationSections(
            visible: makeGroups(visible),
            hidden: makeGroups(hidden))
    }

    /// Display label for a package: the catalog name when known, otherwise the
    /// package string as a temporary name (the reference product does the same
    /// for packages it cannot label).
    static func displayName(for packageName: String, appNames: [String: String]) -> String {
        if let resolved = appNames[packageName]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !resolved.isEmpty
        {
            return resolved
        }
        return packageName
    }

    /// True when a record belongs in the Hidden section rather than Showing.
    static func isHidden(_ record: AndroidNotificationRecord, hideSensitive: Bool) -> Bool {
        guard record.displayText != nil else { return true }
        guard hideSensitive else { return false }
        if record.isSensitive { return true }
        return NotificationPrivacy.isSensitivePackage(record.packageName)
    }

    // MARK: Time

    /// "just now" / "9 sec. ago" / "1 min. ago" / "2 days ago" for a
    /// notification post time in milliseconds since the epoch. A zero/absent
    /// timestamp returns "—" instead of pretending to know when it arrived.
    static func relativeTime(
        postTimeMilliseconds: Int64, now: Date = Date()
    ) -> String {
        guard postTimeMilliseconds > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: Double(postTimeMilliseconds) / 1000)
        return relativeTime(since: date, now: now)
    }

    /// Human-friendly age. Future timestamps (clock skew between phone and Mac)
    /// clamp to "just now" rather than printing a negative age.
    static func relativeTime(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 {
            return "\(Int(seconds)) sec. ago"
        }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes) min. ago"
        }
        let hours = Int(seconds / 3600)
        if hours < 24 {
            return hours == 1 ? "1 hr. ago" : "\(hours) hr. ago"
        }
        let days = Int(seconds / 86_400)
        if days < 7 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
        let weeks = days / 7
        if weeks < 5 {
            return weeks == 1 ? "1 wk. ago" : "\(weeks) wks ago"
        }
        let months = days / 30
        if months < 12 {
            return months == 1 ? "1 mo. ago" : "\(months) mos ago"
        }
        let years = days / 365
        return years == 1 ? "1 yr. ago" : "\(years) yrs ago"
    }
}
