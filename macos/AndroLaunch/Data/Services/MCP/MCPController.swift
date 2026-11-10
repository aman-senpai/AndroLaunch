//
//  MCPController.swift
//  AndroLaunch
//
//  "Android Use": the in-app side of the local stdio MCP server. The server
//  itself is this same binary launched with `--mcp-server` (see MCPServer.swift);
//  this controller owns the persisted enable switch, the copied command, the
//  Stop sentinel and the activity log the Settings screen displays.
//

import AppKit
import Combine
import Foundation

// MARK: - Activity row

struct MCPActivity: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let tool: String
    let device: String?
    let ok: Bool
    let detail: String

    init(record: MCPActivityRecord) {
        self.date = record.date
        self.tool = record.tool
        self.device = record.device
        self.ok = record.ok
        self.detail = record.detail
    }

    init(date: Date, tool: String, device: String?, ok: Bool, detail: String) {
        self.date = date
        self.tool = tool
        self.device = device
        self.ok = ok
        self.detail = detail
    }

    /// "12:41:09" in the user's locale — compact enough for a dense log row.
    var timeText: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    var outcomeText: String { ok ? "OK" : "Failed" }
}

// MARK: - Controller

final class MCPController: ObservableObject {
    static let shared = MCPController()
    /// Deterministic instance for `ImageRenderer` snapshots and previews.
    static let preview = MCPController(isPreview: true)

    @Published private(set) var isEnabled: Bool
    @Published private(set) var activities: [MCPActivity] = []
    /// The server is a per-client stdio process, so "running" means the switch is
    /// on and this build's executable can actually serve it.
    @Published private(set) var isServerRunning: Bool
    @Published private(set) var lastError: String?
    @Published private(set) var lastCopiedAt: Date?

    private let log: MCPActivityLog
    private let defaults: UserDefaults
    private let isPreview: Bool

    init(
        log: MCPActivityLog = MCPActivityLog(),
        defaults: UserDefaults = .standard,
        isPreview: Bool = false
    ) {
        self.log = log
        self.defaults = defaults
        self.isPreview = isPreview
        if isPreview {
            self.isEnabled = true
            self.isServerRunning = true
            self.activities = []
        } else {
            let enabled = MCPRuntime.isEnabled(defaults: defaults)
            self.isEnabled = enabled
            self.isServerRunning = enabled && Self.executableSupportsServer
            self.activities = log.read(limit: 100).reversed().map(MCPActivity.init)
        }
    }

    // MARK: Command

    /// Absolute command a user can paste into an MCP client configuration.
    var command: String {
        if isPreview {
            return "/Applications/AndroLaunch.app/Contents/MacOS/AndroLaunch --mcp-server"
        }
        let executable =
            Bundle.main.executablePath
            ?? "/Applications/AndroLaunch.app/Contents/MacOS/AndroLaunch"
        let quoted = executable.contains(" ") ? "\"\(executable)\"" : executable
        return "\(quoted) --mcp-server"
    }

    var executablePath: String {
        Bundle.main.executablePath
            ?? "/Applications/AndroLaunch.app/Contents/MacOS/AndroLaunch"
    }

    var executableSupportsServer: Bool { Self.executableSupportsServer }

    var activityLogPath: String { log.fileURL.path }

    var lastErrorText: String? {
        if let lastError { return lastError }
        if !Self.executableSupportsServer {
            return "This build cannot start Android Use: the app executable was not found."
        }
        return nil
    }

    // MARK: Lifecycle

    func setEnabled(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard Self.executableSupportsServer else {
            lastError = "This build cannot start Android Use: the app executable was not found."
            isEnabled = false
            isServerRunning = false
            return
        }
        guard !isPreview else {
            isEnabled = true
            isServerRunning = true
            return
        }
        log.clearStop()
        MCPRuntime.setEnabled(true, defaults: defaults)
        isEnabled = true
        isServerRunning = true
        lastError = nil
        refreshActivity()
    }

    func stop() {
        guard !isPreview else {
            isEnabled = false
            isServerRunning = false
            return
        }
        // Disable first, then drop the sentinel: a running server exits even if it
        // is blocked in an ADB command, and a new client cannot start control work.
        MCPRuntime.setEnabled(false, defaults: defaults)
        log.requestStop()
        isEnabled = false
        isServerRunning = false
        lastError = nil
        refreshActivity()
    }

    func clearActivity() {
        guard !isPreview else {
            activities = []
            return
        }
        log.clear()
        activities = []
    }

    func refreshActivity() {
        guard !isPreview else { return }
        activities = log.read(limit: 100).reversed().map(MCPActivity.init)
    }

    func copyCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        lastCopiedAt = Date()
    }

    func revealActivityLog() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: log.fileURL.path) {
            activities = []
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([log.fileURL])
    }

    private static var executableSupportsServer: Bool {
        guard let path = Bundle.main.executablePath else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }
}
