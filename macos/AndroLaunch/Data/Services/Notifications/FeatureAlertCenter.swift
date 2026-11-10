//
//  FeatureAlertCenter.swift
//  AndroLaunch
//
//  The one place that posts "feature alert" notifications. Every category is
//  gated by the Settings preference for that category, so the Feature alerts
//  switches are real controls instead of stored decoration. Bodies never include
//  clipboard, notification or message content.
//

import Foundation
import UserNotifications

final class FeatureAlertCenter {
    static let shared = FeatureAlertCenter()

    private let center = UNUserNotificationCenter.current()
    private var didRequestAuthorization = false
    private var lastPosted: [AppFeatureAlert: Date] = [:]
    /// Cheap flood guard: a failed sync loop must not produce a notification per retry.
    private let minimumInterval: TimeInterval = 20

    private init() {}

    /// Posts only when the user enabled this alert category.
    func post(_ alert: AppFeatureAlert, title: String, body: String) {
        guard AppPreferences.shared.isAlertEnabled(alert) else { return }
        postIgnoringPreference(alert: alert, title: title, body: body)
    }

    /// Used for an event whose own category was already checked by the caller.
    func postIgnoringPreference(alert: AppFeatureAlert?, title: String, body: String) {
        if let alert {
            let now = Date()
            if let last = lastPosted[alert], now.timeIntervalSince(last) < minimumInterval {
                return
            }
            lastPosted[alert] = now
        }
        deliver(title: title, body: body)
    }

    private func deliver(title: String, body: String) {
        let deliverBlock = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil)
            self.center.add(request)
        }

        if didRequestAuthorization {
            deliverBlock()
            return
        }
        didRequestAuthorization = true
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async(execute: deliverBlock)
        }
    }
}
