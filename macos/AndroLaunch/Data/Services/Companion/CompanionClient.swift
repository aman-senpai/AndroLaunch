//
//  CompanionClient.swift
//  AndroLaunch
//
//  Talks to the first-party Android companion over the ADB tunnel.
//
//  Transport: the companion listens on a Linux abstract socket, adb forwards a
//  loopback TCP port to it, and requests are newline-delimited lines
//  (`id \t command \t base64-argument`). No network permission, no pairing, no
//  third-party app — the channel exists exactly as long as the device is connected.
//
//  Every call is a short-lived connection: ADB forwarding is cheap, and a
//  per-request connection means a wedged companion can never leave the Mac with a
//  half-open socket.
//

import Combine
import Foundation
import Network

final class CompanionClient: ObservableObject {

    static let shared = CompanionClient()

    static let packageName = "com.senpai.androlaunch.companion"
    /// Loopback port the companion listens on inside the device.
    static let devicePort: UInt16 = 27777
    static let serviceComponent =
        "com.senpai.androlaunch.companion/.CompanionService"
    /// Name of the APK copied into the app bundle's Resources.
    static let bundledAPKName = "AndroLaunchCompanion"

    enum State: Equatable {
        case unknown
        case notInstalled
        case stopped
        case ready(version: String)
        case failed(String)
    }

    /// Per-device state, keyed by ADB transport ID.
    @Published private(set) var states: [String: State] = [:]

    private let adb: ADBService
    private var ports: [String: UInt16] = [:]
    private var nextPort: UInt16 = 27777
    private var readyDevices: Set<String> = []
    private var inFlight: Set<String> = []
    private let queue = DispatchQueue(label: "com.senpai.AndroLaunch.companion")
    /// Lets synchronous helpers detect that they already run on `queue`; calling
    /// `queue.sync` from `queue` traps the process (the companion prepare path
    /// did exactly that and crashed AndroLaunch).
    private let queueKey = DispatchSpecificKey<Void>()

    init(adb: ADBService = DependencyContainer.shared.adb) {
        self.adb = adb
        queue.setSpecific(key: queueKey, value: ())
    }

    func state(for deviceID: String) -> State {
        states[deviceID] ?? .unknown
    }

    func isReady(_ deviceID: String) -> Bool {
        if case .ready = state(for: deviceID) { return true }
        return false
    }

    // MARK: - Lifecycle

    /// Starts the companion service, establishes the forward and verifies it answers.
    /// Safe to call repeatedly; concurrent calls for one device are collapsed.
    func prepare(deviceID: String, completion: ((Bool) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            // Already verified: the forward and the service are alive, so a paste does
            // not need four adb round trips.
            if self.readyDevices.contains(deviceID) {
                DispatchQueue.main.async { completion?(true) }
                return
            }
            guard !self.inFlight.contains(deviceID) else {
                let ready = self.readyDevices.contains(deviceID)
                DispatchQueue.main.async { completion?(ready) }
                return
            }
            self.inFlight.insert(deviceID)

            self.adb.executeADBCommand(
                arguments: ["-s", deviceID, "shell", "pm", "path", Self.packageName]
            ) { [weak self] success, output, _ in
                guard let self else { return }
                let installed = success && (output?.contains("package:") == true)
                guard installed else {
                    self.finish(deviceID: deviceID, state: .notInstalled, ready: false, completion: completion)
                    return
                }
                self.startServiceAndConnect(deviceID: deviceID, attempt: 0, completion: completion)
            }
        }
    }

    private func startServiceAndConnect(
        deviceID: String, attempt: Int, completion: ((Bool) -> Void)?
    ) {
        let port = port(for: deviceID)
        let forward = "tcp:\(port)"

        adb.executeADBCommand(
            arguments: ["-s", deviceID, "forward", forward, "tcp:\(Self.devicePort)"]
        ) { [weak self] forwardOK, _, _ in
            guard let self else { return }
            guard forwardOK else {
                self.finish(
                    deviceID: deviceID,
                    state: .failed("Could not open the AndroLaunch Comp channel."),
                    ready: false, completion: completion)
                return
            }

            self.adb.executeADBCommand(
                arguments: [
                    "-s", deviceID, "shell", "am", "start-foreground-service",
                    "-n", Self.serviceComponent,
                    "--es", "token", CompanionAuth.token,
                ]
            ) { [weak self] startOK, startOut, startErr in
                guard let self else { return }
                // The service binds its socket on start; give it a moment, then ping.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.call(deviceID: deviceID, command: "ping") { result in
                        switch result {
                        case .success(let version):
                            // The channel is ready as soon as ping answers; do not
                            // hold every companion command behind the six grant
                            // ADB calls. Grants run in the background once.
                            self.finish(
                                deviceID: deviceID, state: .ready(version: version),
                                ready: true, completion: completion)
                            self.grantDefaultAccess(deviceID: deviceID) {}
                        case .failure:
                            if attempt < 2 {
                                self.startServiceAndConnect(
                                    deviceID: deviceID, attempt: attempt + 1,
                                    completion: completion)
                            } else {
                                self.finish(
                                    deviceID: deviceID,
                                    state: .failed("AndroLaunch Comp is installed but not responding."),
                                    ready: false, completion: completion)
                            }
                        }
                    }
                }
            }
        }
    }

    private func finish(
        deviceID: String, state: State, ready: Bool, completion: ((Bool) -> Void)?
    ) {
        queue.async {
            self.inFlight.remove(deviceID)
            if ready { self.readyDevices.insert(deviceID) } else { self.readyDevices.remove(deviceID) }
        }
        DispatchQueue.main.async {
            if self.states[deviceID] != state { self.states[deviceID] = state }
            completion?(ready)
        }
    }

    // MARK: - Clipboard

    /// Sends text to the phone's clipboard. Prepares the channel first, so the very
    /// first paste after installing the companion works without manual steps.
    func pushClipboard(_ text: String, deviceID: String, completion: ((Bool) -> Void)? = nil) {
        guard !text.isEmpty else {
            completion?(false)
            return
        }
        func attempt(_ retry: Bool) {
            prepare(deviceID: deviceID) { [weak self] ready in
                guard let self, ready else {
                    completion?(false)
                    return
                }
                self.call(deviceID: deviceID, command: "clip.set", argument: text) { result in
                    switch result {
                    case .success:
                        completion?(true)
                    case .failure(let error):
                        // The service may have been killed while the channel looked
                        // healthy (Doze, force-stop, reboot). Rebuild once, then give up.
                        if retry {
                            self.invalidate(deviceID)
                            attempt(false)
                        } else {
                            DispatchQueue.main.async {
                                self.states[deviceID] = .failed(error.localizedDescription)
                            }
                            completion?(false)
                        }
                    }
                }
            }
        }
        attempt(true)
    }

    /// Best-effort read of the phone clipboard. Android only allows this while the
    /// app has focus, so a `focus_required` failure is expected and callers fall
    /// back to the mirrored session.
    func pullClipboard(deviceID: String, completion: @escaping (String?) -> Void) {
        prepare(deviceID: deviceID) { [weak self] ready in
            guard let self, ready else {
                completion(nil)
                return
            }
            self.call(deviceID: deviceID, command: "clip.get") { result in
                switch result {
                case .success(let text): completion(text.isEmpty ? nil : text)
                case .failure: completion(nil)
                }
            }
        }
    }

    // MARK: - Notifications (ready for the companion's relay)

    func notifications(deviceID: String, completion: @escaping ([[String: Any]]) -> Void) {
        prepare(deviceID: deviceID) { [weak self] ready in
            guard let self, ready else {
                completion([])
                return
            }
            self.call(deviceID: deviceID, command: "notif.list") { result in
                guard case .success(let json) = result,
                    let data = json.data(using: .utf8),
                    let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else {
                    completion([])
                    return
                }
                completion(parsed)
            }
        }
    }

    // MARK: - Generic requests (protocol v3)

    /// Sends one protocol command after making sure the channel is alive.
    ///
    /// This is the single entry point every v3 feature uses: calls, media,
    /// ring, storage and clipboard images. Commands the installed companion does
    /// not know answer `unknown_command:<name>`, which callers surface as
    /// "update AndroLaunch Comp" instead of pretending success.
    func request(
        deviceID: String,
        command: String,
        argument: String = "",
        timeout: TimeInterval = 6,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        prepare(deviceID: deviceID) { [weak self] ready in
            guard let self, ready else {
                completion(
                    .failure(
                        CompanionError(
                            message: "AndroLaunch Comp is not running on this device.")))
                return
            }
            self.call(
                deviceID: deviceID, command: command, argument: argument,
                timeout: timeout, completion: completion)
        }
    }

    /// Reuses an already-verified channel without waiting on `prepare`.
    /// Polling paths use this so a 1.5 s tick never queues behind a channel check.
    func requestWhenReady(
        deviceID: String,
        command: String,
        argument: String = "",
        timeout: TimeInterval = 4,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard isReady(deviceID) else {
            completion(.failure(CompanionError(message: "AndroLaunch Comp is not ready.")))
            return
        }
        call(
            deviceID: deviceID, command: command, argument: argument,
            timeout: timeout, completion: completion)
    }

    // MARK: - Calls

    func callState(deviceID: String, completion: @escaping (Result<CompanionCallState, Error>) -> Void) {
        requestWhenReady(deviceID: deviceID, command: "call.state", timeout: 3) { result in
            switch result {
            case .success(let payload):
                guard let state = CompanionCallState.decode(payload) else {
                    completion(.failure(CompanionError(message: "Unreadable call state.")))
                    return
                }
                completion(.success(state))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func answerCall(deviceID: String, completion: @escaping (Bool, String?) -> Void) {
        callCommand(deviceID: deviceID, command: "call.answer", completion: completion)
    }

    func endCall(deviceID: String, completion: @escaping (Bool, String?) -> Void) {
        callCommand(deviceID: deviceID, command: "call.end", completion: completion)
    }

    // MARK: - Media

    func mediaState(
        deviceID: String, includeArtwork: Bool = false,
        completion: @escaping (Result<CompanionMediaState, Error>) -> Void
    ) {
        requestWhenReady(
            deviceID: deviceID, command: "media.state",
            argument: includeArtwork ? "artwork" : "",
            timeout: includeArtwork ? 8 : 3
        ) { result in
            switch result {
            case .success(let payload):
                guard let state = CompanionMediaState.decode(payload) else {
                    completion(.failure(CompanionError(message: "Unreadable media state.")))
                    return
                }
                completion(.success(state))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func mediaTransport(
        deviceID: String, action: String, completion: @escaping (Bool, String?) -> Void
    ) {
        // `action` is one of play/pause/next/prev, validated by the caller.
        guard ["play", "pause", "next", "prev"].contains(action) else {
            completion(false, "Unsupported media action.")
            return
        }
        callCommand(deviceID: deviceID, command: "media.\(action)", completion: completion)
    }

    // MARK: - Find my phone

    func ring(deviceID: String, durationMs: Int = 30_000, completion: ((Bool, String?) -> Void)? = nil) {
        request(
            deviceID: deviceID, command: "phone.ring", argument: String(durationMs),
            timeout: 6
        ) { result in
            switch result {
            case .success:
                completion?(true, nil)
            case .failure(let error):
                completion?(false, error.localizedDescription)
            }
        }
    }

    func stopRing(deviceID: String, completion: ((Bool) -> Void)? = nil) {
        requestWhenReady(deviceID: deviceID, command: "phone.ring.stop", timeout: 4) { result in
            switch result {
            case .success: completion?(true)
            case .failure: completion?(false)
            }
        }
    }

    // MARK: - Storage

    func storageInfo(
        deviceID: String, completion: @escaping (Result<CompanionStorageState, Error>) -> Void
    ) {
        request(
            deviceID: deviceID, command: "storage.info", timeout: 12
        ) { result in
            switch result {
            case .success(let payload):
                guard let state = CompanionStorageState.decode(payload) else {
                    completion(.failure(CompanionError(message: "Unreadable storage info.")))
                    return
                }
                completion(.success(state))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Storage permission (protocol v5)

    /// Reads whether the companion can enumerate the phone's storage tree.
    ///
    /// Capacity numbers never need this; per-folder totals do. An older companion
    /// answers `unknown_command:storage.access`, which surfaces as a readable error
    /// so callers can say "update AndroLaunch Comp" instead of guessing.
    func storageAccess(
        deviceID: String,
        completion: @escaping (Result<StorageAccessState, Error>) -> Void
    ) {
        request(deviceID: deviceID, command: "storage.access", timeout: 8) { result in
            switch result {
            case .success(let payload):
                guard let state = StorageAccessState.decode(payload) else {
                    completion(
                        .failure(
                            CompanionError(message: "Unreadable storage access state.")))
                    return
                }
                completion(.success(state))
            case .failure(let error):
                completion(
                    .failure(
                        CompanionError(
                            message: StorageAccessLogic.friendlyError(
                                error.localizedDescription))))
            }
        }
    }

    /// Asks the companion to open the Android Settings screen that grants storage
    /// access. `true` means the screen was launched; the grant itself is the
    /// user's action and must be re-read with `storageAccess`.
    func requestStorageAccess(
        deviceID: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        request(deviceID: deviceID, command: "storage.requestAccess", timeout: 10) { result in
            switch result {
            case .success(let payload):
                completion(.success(StorageAccessLogic.didOpenSettings(payload)))
            case .failure(let error):
                completion(
                    .failure(
                        CompanionError(
                            message: StorageAccessLogic.friendlyError(
                                error.localizedDescription))))
            }
        }
    }

    // MARK: - App icons (protocol v4)

    /// Fetches real launcher icons for the given packages.
    ///
    /// The argument is newline-separated package names; the companion answers
    /// `{"c":"app-icons","icons":[…]}` with 96 px PNGs. Callers should batch (see
    /// `AppIconBatches`) rather than asking for an entire app list in one request.
    /// An older companion answers `unknown_command:app-icons`, which surfaces as a
    /// failure so the Mac keeps its SF Symbol fallback instead of waiting.
    func appIcons(
        packages: [String], deviceID: String,
        completion: @escaping (Result<[CompanionAppIcon], Error>) -> Void
    ) {
        let unique = packages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !unique.isEmpty else {
            completion(.success([]))
            return
        }
        guard unique.count <= AppIconPayload.maxIconCount else {
            completion(
                .failure(
                    CompanionError(
                        message: "Too many packages in one app-icons request.")))
            return
        }

        let argument = unique.joined(separator: "\n")
        request(
            deviceID: deviceID, command: "app-icons", argument: argument, timeout: 25
        ) { result in
            switch result {
            case .success(let json):
                guard let icons = AppIconPayload.decode(json) else {
                    completion(
                        .failure(
                            CompanionError(message: "Unreadable app icon payload.")))
                    return
                }
                completion(.success(icons))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Notification actions

    func reply(
        toNotificationKey key: String, actionIndex: Int, text: String, deviceID: String,
        completion: ((Bool, String?) -> Void)? = nil
    ) {
        guard !key.isEmpty, !text.isEmpty else {
            completion?(false, "There is nothing to send.")
            return
        }
        // The reply text travels in this one request only; it is never logged or stored.
        let argument = CompanionReplyArgument.make(key: key, actionIndex: actionIndex, text: text)
        requestWhenReady(
            deviceID: deviceID, command: "notif.reply", argument: argument, timeout: 8
        ) { result in
            switch result {
            case .success(let payload):
                completion?(payload == "replied", payload)
            case .failure(let error):
                completion?(false, error.localizedDescription)
            }
        }
    }

    /// Invokes a non-reply notification action (for example “Mark as read”).
    /// The companion implements this in protocol v5; older companions return a
    /// helpful error and the UI keeps only the actions they support.
    func actionNotification(
        key: String, actionIndex: Int, deviceID: String,
        completion: ((Bool, String?) -> Void)? = nil
    ) {
        guard let argument = CompanionNotificationActionArgument.make(
            key: key, actionIndex: actionIndex)
        else {
            completion?(false, "That notification action is no longer available.")
            return
        }
        requestWhenReady(
            deviceID: deviceID, command: "notif.action", argument: argument, timeout: 5
        ) { result in
            switch result {
            case .success(let payload):
                if payload == "ok" {
                    completion?(true, nil)
                } else {
                    completion?(false, Self.notificationActionFailureText(payload))
                }
            case .failure(let error):
                completion?(false, Self.notificationActionFailureText(error.localizedDescription))
            }
        }
    }

    /// Typed companion results and transport errors become actionable copy.
    static func notificationActionFailureText(_ raw: String?) -> String {
        NotificationActionFailureText.message(for: raw)
    }

    func dismissNotification(
        key: String, deviceID: String, completion: ((Bool, String?) -> Void)? = nil
    ) {
        guard !key.isEmpty else {
            completion?(false, "Missing notification key.")
            return
        }
        requestWhenReady(deviceID: deviceID, command: "notif.dismiss", argument: key, timeout: 5) {
            result in
            switch result {
            case .success(let payload):
                completion?(payload == "dismissed", payload)
            case .failure(let error):
                completion?(false, error.localizedDescription)
            }
        }
    }

    // MARK: - Clipboard images

    /// Sends PNG/JPEG bytes to the phone clipboard. Oversized images are rejected
    /// here, before a multi-megabyte line is written to the tunnel.
    func pushClipboardImage(
        _ imageData: Data, deviceID: String, completion: ((Bool, String?) -> Void)? = nil
    ) {
        guard !imageData.isEmpty else {
            completion?(false, "There is no image on the Mac clipboard.")
            return
        }
        guard imageData.count <= CompanionClient.maxClipboardImageBytes else {
            completion?(
                false,
                "The image is \(PhoneFormat.bytes(Int64(imageData.count))); the phone clipboard accepts up to \(PhoneFormat.bytes(Int64(CompanionClient.maxClipboardImageBytes))).")
            return
        }
        let argument = imageData.base64EncodedString()
        request(
            deviceID: deviceID, command: "clip.set.image", argument: argument, timeout: 25
        ) { result in
            switch result {
            case .success(let payload):
                completion?(payload == "image_set", payload)
            case .failure(let error):
                completion?(false, Self.explainImageError(error.localizedDescription))
            }
        }
    }

    /// Best-effort image read from the phone clipboard. Android only allows
    /// clipboard reads while the companion has focus, so nil is a normal outcome.
    func pullClipboardImage(deviceID: String, completion: @escaping (Data?) -> Void) {
        requestWhenReady(
            deviceID: deviceID, command: "clip.get.image", timeout: 25
        ) { result in
            guard case .success(let base64) = result,
                let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
                !data.isEmpty
            else {
                completion(nil)
                return
            }
            completion(data)
        }
    }

    static let maxClipboardImageBytes = 8 * 1024 * 1024

    private static func explainImageError(_ raw: String) -> String {
        switch raw {
        case "too_large":
            return "The phone rejected the image because it is too large."
        case "unsupported_type":
            return "The phone clipboard accepts PNG, JPEG or WebP images only."
        case "focus_required":
            return "Android only allows clipboard reads while AndroLaunch Comp is open on the phone."
        case "empty":
            return "There is no image on the phone clipboard."
        default:
            return raw
        }
    }

    // MARK: - Private helpers

    private func callCommand(
        deviceID: String, command: String, completion: @escaping (Bool, String?) -> Void
    ) {
        request(deviceID: deviceID, command: command, timeout: 6) { result in
            switch result {
            case .success:
                completion(true, nil)
            case .failure(let error):
                completion(false, error.localizedDescription)
            }
        }
    }

    /// Forgets the channel for a device so the next call re-establishes it.
    func invalidate(_ deviceID: String) {
        queue.async {
            self.readyDevices.remove(deviceID)
        }
        if let port = ports[deviceID] {
            adb.executeADBCommand(arguments: ["-s", deviceID, "forward", "--remove", "tcp:\(port)"]) {
                _, _, _ in
            }
        }
    }

    // MARK: - Installation

    var bundledAPKURL: URL? {
        Bundle.main.url(forResource: Self.bundledAPKName, withExtension: "apk")
    }

    /// Installs (or updates) the bundled companion APK on the device.
    func install(deviceID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let apk = bundledAPKURL else {
            completion(
                .failure(
                    NSError(
                        domain: "AndroLaunch.Companion", code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "AndroLaunch Comp is not bundled with this build."
                        ])))
            return
        }

        // Install without `-g`: that flag auto-grants every declared runtime permission,
        // which would silently opt the user into READ_PHONE_STATE / ANSWER_PHONE_CALLS and
        // break the companion's in-app call-opt-in privacy model. Only the notification
        // permission the foreground service needs is pre-granted after a successful install.
        adb.executeADBCommand(
            arguments: ["-s", deviceID, "install", "-r", apk.path]
        ) { [weak self] success, output, errorOutput in
            guard let self else { return }
            if success && (output?.contains("Success") ?? false) {
                // Phone/call permissions stay ungranted and are requested by the companion's
                // own opt-in UI; this grant is the only one AndroLaunch performs on the user's behalf.
                self.grantDefaultAccess(deviceID: deviceID) {
                    self.readyDevices.remove(deviceID)
                    self.prepare(deviceID: deviceID) { _ in
                        completion(.success(()))
                    }
                }
            } else {
                let raw =
                    (errorOutput?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? errorOutput! : output) ?? "Install failed."
                completion(
                    .failure(
                        NSError(
                            domain: "AndroLaunch.Companion", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: Self.explain(raw)])))
            }
        }
    }

    /// Grants the permissions the companion needs to be useful immediately after
    /// an ADB install: notification permission, the notification listener, media
    /// read access and All-files access. Phone/call permissions stay opt-in in the
    /// companion UI; ADB `-g` is intentionally not used so those are never silent.
    private func grantDefaultAccess(deviceID: String, completion: @escaping () -> Void) {
        let key = "companion.defaultAccess.\(deviceID)"
        if UserDefaults.standard.bool(forKey: key) {
            completion()
            return
        }
        let commands: [[String]] = [
            ["shell", "pm", "grant", Self.packageName,
             "android.permission.POST_NOTIFICATIONS"],
            ["shell", "pm", "grant", Self.packageName,
             "android.permission.READ_EXTERNAL_STORAGE"],
            ["shell", "pm", "grant", Self.packageName,
             "android.permission.READ_MEDIA_IMAGES"],
            ["shell", "pm", "grant", Self.packageName,
             "android.permission.READ_MEDIA_VIDEO"],
            ["shell", "appops", "set", Self.packageName,
             "MANAGE_EXTERNAL_STORAGE", "allow"],
            ["shell", "cmd", "notification", "allow_listener",
             "\(Self.packageName)/.NotificationRelay"],
        ]
        func run(_ index: Int) {
            guard index < commands.count else {
                UserDefaults.standard.set(true, forKey: key)
                completion()
                return
            }
            adb.executeADBCommand(
                arguments: ["-s", deviceID] + commands[index]
            ) { _, _, _ in
                run(index + 1)
            }
        }
        run(0)
    }

    /// Turns raw `adb install` output into something a user can act on.
    ///
    /// The blocked-install codes come from OEM policies (MIUI's "Install via USB",
    /// ColorOS, Samsung Knox), not from a broken APK, so saying "install failed"
    /// would send people looking in the wrong place.
    private static func explain(_ raw: String) -> String {
        let lowered = raw.lowercased()
        if lowered.contains("user_restricted") || lowered.contains("canceled by user") {
            return """
                The phone blocked the install. On MIUI/ColorOS this needs \
                Developer options → "Install via USB" turned on (it may ask you to sign \
                in), and the confirmation prompt on the phone has to be accepted. \
                Then choose Install AndroLaunch Comp again.
                """
        }
        if lowered.contains("update_incompatible") {
            return """
                A different build of AndroLaunch Comp is already installed. Uninstall it \
                on the phone ("AndroLaunch Comp") and install again.
                """
        }
        if lowered.contains("no space") || lowered.contains("insufficient") {
            return "The phone is out of storage for AndroLaunch Comp."
        }
        if lowered.contains("offline") || lowered.contains("device not found") {
            return "The device disconnected before AndroLaunch Comp could be installed."
        }
        return raw
    }

    // MARK: - Wire protocol

    /// Must run on `queue`.
    private func allocatePort(for deviceID: String) -> UInt16 {
        if let existing = ports[deviceID] { return existing }
        let port = nextPort
        nextPort = nextPort == .max ? 27777 : nextPort + 1
        ports[deviceID] = port
        return port
    }

    private func port(for deviceID: String) -> UInt16 {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return allocatePort(for: deviceID)
        }
        return queue.sync { allocatePort(for: deviceID) }
    }

    private struct CompanionError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// One request, one response, one connection.
    private func call(
        deviceID: String, command: String, argument: String = "",
        timeout: TimeInterval = 4,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let port = port(for: deviceID)
        let connection = NWConnection(
            host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)

        var finished = false
        let finish: (Result<String, Error>) -> Void = { result in
            guard !finished else { return }
            finished = true
            connection.cancel()
            completion(result)
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let id = CompanionAuth.requestID()
                let encodedArgument = Data(argument.utf8).base64EncodedString()
                let line = "\(id)\t\(command)\t\(encodedArgument)\n"
                connection.send(
                    content: Data(line.utf8),
                    completion: .contentProcessed { error in
                        if let error {
                            finish(.failure(error))
                        }
                    })
            case .failed(let error):
                finish(.failure(error))
            default:
                break
            }
        }

        var buffer = Data()

        // A single `receive` only reads up to `maximumLength`; multi-chunk
        // responses (app-icon batches, long notification lists) need to keep
        // reading until the newline terminator arrives or the peer closes.
        func receiveNextChunk() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
                data, _, isComplete, error in
                if finished { return }
                if let data { buffer.append(data) }
                if let newline = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[buffer.startIndex..<newline]
                    let line = String(decoding: lineData, as: UTF8.self)
                    finish(Self.parse(line: line))
                    return
                }
                if let error {
                    finish(.failure(error))
                    return
                }
                if isComplete {
                    finish(
                        .failure(
                            CompanionError(
                                message: "AndroLaunch Comp closed the connection.")))
                    return
                }
                receiveNextChunk()
            }
        }

        connection.start(queue: queue)
        receiveNextChunk()

        queue.asyncAfter(deadline: .now() + timeout) {
            finish(.failure(CompanionError(message: "AndroLaunch Comp did not answer in time.")))
        }
    }

    private static func parse(line: String) -> Result<String, Error> {
        let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            return .failure(CompanionError(message: "Malformed response from AndroLaunch Comp."))
        }
        let status = String(parts[1])
        let payload =
            parts.count > 2
            ? String(data: Data(base64Encoded: String(parts[2])) ?? Data(), encoding: .utf8) ?? ""
            : ""
        if status == "ok" { return .success(payload) }
        return .failure(CompanionError(message: payload.isEmpty ? "AndroLaunch Comp error." : payload))
    }
}
