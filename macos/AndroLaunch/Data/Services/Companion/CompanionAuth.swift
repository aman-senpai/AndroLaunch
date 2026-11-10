//
//  CompanionAuth.swift
//  AndroLaunch
//
//  A per-install shared secret for the loopback companion socket. It travels in
//  the request id field (`t.<token>.<id>`), which older companions simply echo
//  and ignore, so protocol compatibility is preserved. The Mac passes the same
//  token as a foreground-service extra when it starts the companion; apps on the
//  phone cannot set it because the companion only accepts the extra from the
//  adb shell / its own UID.
//

import Foundation

enum CompanionAuth {
    static let defaultsKey = "companion.authToken"

    /// Stable 128-bit token, generated once per Mac install.
    static var token: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: defaultsKey),
            existing.count >= 32
        {
            return existing
        }
        let generated =
            UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        defaults.set(generated, forKey: defaultsKey)
        return generated
    }

    /// Request id carrying the token. Older companions echo it; newer companions
    /// validate it before dispatching the command.
    static func requestID() -> String {
        "t.\(token).\(UUID().uuidString.prefix(8))"
    }
}
