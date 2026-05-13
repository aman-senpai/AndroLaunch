import AppKit

/// Shared utility for presenting native macOS alert dialogs.
/// Deduplicates alerts based on a normalized hash to prevent spam.
enum AlertPresenter {
    private static var lastAlertTime: Date = .distantPast
    private static var lastAlertHash: Int = 0
    private static var consecutiveCount: Int = 0
    private static var suppressedSince: Date?

    /// Minimum interval between any two alerts (seconds).
    private static let minInterval: TimeInterval = 3.0
    /// After this many consecutive alerts, suppress all further alerts for the cooldown period.
    private static let maxConsecutiveBeforeCooldown = 3
    /// Cooldown period when alerts are suppressed (seconds).
    private static let cooldownInterval: TimeInterval = 30.0

    /// Shows a warning-style NSAlert with the given message.
    /// Rate-limited and deduplicated to prevent alert spam.
    static func showWarning(message: String, title: String = "Error") {
        guard shouldShow(message: message) else { return }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    /// Shows a critical-style NSAlert with the given message.
    static func showCritical(message: String, title: String = "Error") {
        guard shouldShow(message: message) else { return }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.alertStyle = .critical
            alert.runModal()
        }
    }

    // MARK: - Rate Limiting

    private static func shouldShow(message: String) -> Bool {
        let now = Date()
        let hash = normalizedHash(of: message)

        // If we're in cooldown, suppress all alerts
        if let suppressedSince = suppressedSince {
            if now.timeIntervalSince(suppressedSince) < cooldownInterval {
                return false
            } else {
                // Cooldown expired, reset
                self.suppressedSince = nil
                consecutiveCount = 0
            }
        }

        // Same alert as last time? Increment consecutive count
        if hash == lastAlertHash && now.timeIntervalSince(lastAlertTime) < minInterval * 2 {
            consecutiveCount += 1
        } else if now.timeIntervalSince(lastAlertTime) > minInterval * 2 {
            // Different alert or enough time passed, reset count
            consecutiveCount = 1
        }

        lastAlertTime = now
        lastAlertHash = hash

        // If too many consecutive alerts, enter cooldown
        if consecutiveCount >= maxConsecutiveBeforeCooldown {
            suppressedSince = now
            // Show one final alert explaining suppression
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Errors Suppressed"
                alert.informativeText =
                    "Multiple errors are occurring. Further alerts will be suppressed for \(Int(cooldownInterval)) seconds.\n\nCheck your Android SDK configuration in Preferences."
                alert.addButton(withTitle: "OK")
                alert.alertStyle = .warning
                alert.runModal()
            }
            return false
        }

        return true
    }

    /// Create a hash of the normalized message (first meaningful line, stripped of paths).
    private static func normalizedHash(of message: String) -> Int {
        // Take first line only
        let firstLine = message.components(separatedBy: "\n").first ?? message
        // Replace file paths with a placeholder to group similar errors
        let normalized =
            firstLine
            .replacingOccurrences(of: "/[^ ]+", with: "/<PATH>", options: .regularExpression)
            .replacingOccurrences(of: "“[^”]+”", with: "“<FILE>”", options: .regularExpression)
        return normalized.hashValue
    }

    /// Reset rate limiting state (e.g., when user opens Preferences to fix the issue).
    static func resetRateLimit() {
        lastAlertTime = .distantPast
        lastAlertHash = 0
        consecutiveCount = 0
        suppressedSince = nil
    }
}
