//
//  NotificationCategories.swift
//  AndroLaunch
//
//  macOS notification categories shared by phone features:
//
//  - Mirrored notifications get inline reply + "Dismiss on phone" while the
//    posting app supports direct reply; everything else still gets dismiss.
//  - Calls get Answer / Decline, which run through the companion's best-effort
//    call control. There is no call audio on the Mac and no category implies any.
//
//  Registration happens once, before the first notification is delivered.
//

import UserNotifications

enum NotificationCategories {

    /// Mirrored notification whose app exposes a direct-reply action.
    static let message = "ANDROLAUNCH_MESSAGE"
    /// Mirrored notification without reply support.
    static let plain = "ANDROLAUNCH_NOTIFICATION"
    /// Ringing-call alert with Answer/Decline.
    static let call = "ANDROLAUNCH_CALL"

    static let replyAction = "ANDROLAUNCH_REPLY"
    static let dismissAction = "ANDROLAUNCH_DISMISS"
    static let callAnswerAction = "ANDROLAUNCH_CALL_ANSWER"
    static let callDeclineAction = "ANDROLAUNCH_CALL_DECLINE"

    private static var registered = false
    private static var preferenceObserver: NSObjectProtocol?

    /// Idempotent; safe to call from any surface before posting a notification.
    /// Re-applies the categories when the Inline reply preference changes.
    static func registerIfNeeded() {
        if !registered {
            registered = true
            preferenceObserver = NotificationCenter.default.addObserver(
                forName: .appPreferencesDidChange, object: nil, queue: .main
            ) { note in
                guard let key = note.userInfo?["key"] as? String,
                    key == AppPreferenceKeys.inlineReply
                else { return }
                applyCategories()
            }
        }
        applyCategories()
    }

    private static func applyCategories() {
        // The Inline reply switch is a real control: without it the mirrored
        // notification keeps Dismiss but never offers a text input.
        let actions: [UNNotificationAction]
        if AppPreferences.shared.inlineReply {
            let reply = UNTextInputNotificationAction(
                identifier: replyAction,
                title: "Reply",
                options: [],
                textInputButtonTitle: "Send",
                textInputPlaceholder: "Message")
            let dismiss = UNNotificationAction(
                identifier: dismissAction,
                title: "Dismiss on phone",
                options: [])
            actions = [reply, dismiss]
        } else {
            let dismiss = UNNotificationAction(
                identifier: dismissAction,
                title: "Dismiss on phone",
                options: [])
            actions = [dismiss]
        }

        let messageCategory = UNNotificationCategory(
            identifier: message,
            actions: actions,
            intentIdentifiers: [],
            options: [])
        let plainCategory = UNNotificationCategory(
            identifier: plain,
            actions: [UNNotificationAction(
                identifier: dismissAction,
                title: "Dismiss on phone",
                options: [])],
            intentIdentifiers: [],
            options: [])

        let answer = UNNotificationAction(
            identifier: callAnswerAction,
            title: "Answer",
            options: [])
        let decline = UNNotificationAction(
            identifier: callDeclineAction,
            title: "Decline",
            options: [.destructive])
        let callCategory = UNNotificationCategory(
            identifier: call,
            actions: [answer, decline],
            intentIdentifiers: [],
            options: [])

        UNUserNotificationCenter.current().setNotificationCategories(
            [messageCategory, plainCategory, callCategory])
    }
}
