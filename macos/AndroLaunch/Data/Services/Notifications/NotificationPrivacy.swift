//
//  NotificationPrivacy.swift
//  AndroLaunch
//
//  Foundation-only sensitive-app policy shared by every surface that can expose
//  phone notification text: macOS mirroring and the Android Use MCP server.
//

import Foundation

enum NotificationPrivacy {
    /// UserDefaults key owned by the Notifications settings switch.
    static let hideSensitiveDefaultsKey = "notifications.hideSensitiveApps"

    /// Default is on: financial, authenticator, password-manager and wallet
    /// notifications stay off the Mac unless the user explicitly opts out.
    /// Mail is shown so the dashboard can act as a notification surface.
    static var hideSensitiveApps: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: hideSensitiveDefaultsKey) != nil else { return true }
        return defaults.bool(forKey: hideSensitiveDefaultsKey)
    }

    /// Package-name needles for apps whose notification text is sensitive by
    /// default. Matching is a case-insensitive substring test, which covers the
    /// common OEM and Play Store variants.
    private static let sensitivePackageNeedles = [
        // Finance and banking.
        "bank", "finance", ".bank", "chase", "wellsfargo", "revolut", "monzo",
        "starling", "hsbc", "barclays", "citibank", "coinbase", "binance",
        // Authenticators and 2FA.
        "authenticator", "2fa", "otp", "authy",
        // Password managers.
        "password", "1password", "bitwarden", "lastpass", "keepass",
        // Wallets and payment.
        "wallet", "pay", "venmo", "cashapp", "cash.app",
    ]

    /// Exact matches for apps whose package name defeats the substring list
    /// (Gmail ships as `com.google.android.gm`).
    private static let sensitivePackageNames: Set<String> = []

    static func isSensitivePackage(_ packageName: String) -> Bool {
        let lowered = packageName.lowercased()
        if sensitivePackageNames.contains(lowered) { return true }
        return sensitivePackageNeedles.contains { lowered.contains($0) }
    }
}
