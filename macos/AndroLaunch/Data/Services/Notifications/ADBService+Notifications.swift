//
//  ADBService+Notifications.swift
//  AndroLaunch
//
//  ADB calls used by `NotificationMirror`. This is an extension (not an edit to
//  ADBService.swift) so the notification feature keeps its own file, as the
//  continuity architecture contract requires. `executeADBCommand` is internal
//  precisely so feature extensions can reuse it.
//

import Foundation

/// Outcome of one `dumpsys notification` read. The unsupported case is kept
/// separate from a generic failure so the mirror can fall back to the narrower
/// dump once per device/OS instead of treating it as a transient error.
enum NotificationDumpOutcome {
    case success(String)
    /// `dumpsys` rejected the `--noredact` argument (older Android).
    case unsupportedFlag(String)
    case failure(String)
}

extension ADBService {
    /// Reads the current notification list from `deviceID`.
    ///
    /// `useNoredact` asks Android for un-redacted notification text (available
    /// on most Android 11+ builds). Older builds reject the flag; the mirror
    /// then retries without it and remembers the working variant per device.
    func fetchNotificationDump(
        deviceID: String, useNoredact: Bool,
        completion: @escaping (NotificationDumpOutcome) -> Void
    ) {
        var arguments = ["-s", deviceID, "shell", "dumpsys", "notification"]
        if useNoredact { arguments.append("--noredact") }

        executeADBCommand(arguments: arguments) { success, output, errorOutput in
            let stdout = output ?? ""
            let stderr = errorOutput ?? ""
            let combined = (stderr + "\n" + stdout).lowercased()

            // Some Android builds print "Unknown option: --noredact" into the
            // dump and still exit 0 (the flag is simply ignored). Detect that in
            // both streams so the mirror can fall back to the plain dump and
            // remember the working variant for this device/OS.
            let flagRejected =
                (combined.contains("unknown option")
                    || combined.contains("unrecognized option")
                    || combined.contains("unknown argument")
                    || combined.contains("invalid option"))
                && combined.contains("noredact")

            if success && !(useNoredact && flagRejected) {
                completion(.success(stdout))
                return
            }

            if useNoredact && flagRejected {
                completion(.unsupportedFlag(stderr.isEmpty ? stdout : stderr))
            } else {
                let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                completion(
                    .failure(message.isEmpty ? "ADB returned no output." : message)
                )
            }
        }
    }

    /// Opens the posting app on the phone (tap-to-open from a mirrored banner).
    /// The package identifier is validated by the caller, but it is re-checked
    /// here as well so no ADB command is ever built from an unchecked string.
    func launchPackageOnDevice(
        deviceID: String, packageID: String, completion: @escaping (Bool) -> Void
    ) {
        guard Self.isSafePackageIdentifier(packageID) else {
            completion(false)
            return
        }
        executeADBCommand(arguments: ["-s", deviceID, "shell", "monkey", "-p", packageID, "1"]) {
            success, _, _ in
            completion(success)
        }
    }

    /// Package names are reverse-DNS: letters, digits, dots and underscores only.
    static func isSafePackageIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 255 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
