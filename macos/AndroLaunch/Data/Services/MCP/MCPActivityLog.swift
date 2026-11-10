//
//  MCPActivityLog.swift
//  AndroLaunch
//
//  Append-only JSONL activity log for Android Use. One record per tool call:
//  tool name, device serial, duration, ok/error and a bounded human detail.
//  Payload text (typed text, shell commands, clipboard contents) is deliberately
//  never stored; see `MCPTextSanitizer.detail`.
//
//  The file also carries the cross-process control channel used by the Settings
//  "Stop" button: a sentinel file the stdio server checks before every call and
//  while an ADB command is running.
//

import Foundation

// MARK: - Record

struct MCPActivityRecord: Codable, Equatable, Identifiable {
    /// ISO-8601 timestamp with milliseconds, UTC.
    let time: String
    let tool: String
    let device: String?
    let ok: Bool
    let durationMs: Int
    let detail: String

    var id: String { "\(time)|\(tool)|\(device ?? "-")|\(durationMs)" }

    var date: Date {
        MCPActivityRecord.isoFormatter.date(from: time) ?? Date(timeIntervalSince1970: 0)
    }

    enum CodingKeys: String, CodingKey {
        case time
        case tool
        case device
        case ok
        case durationMs = "duration_ms"
        case detail
    }

    init(
        date: Date = Date(), tool: String, device: String?, ok: Bool, durationMs: Int,
        detail: String
    ) {
        self.time = MCPActivityRecord.isoFormatter.string(from: date)
        self.tool = tool
        self.device = device
        self.ok = ok
        self.durationMs = max(0, durationMs)
        self.detail = MCPTextSanitizer.detail(detail)
    }

    init(time: String, tool: String, device: String?, ok: Bool, durationMs: Int, detail: String) {
        self.time = time
        self.tool = tool
        self.device = device
        self.ok = ok
        self.durationMs = max(0, durationMs)
        self.detail = MCPTextSanitizer.detail(detail)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// MARK: - Log

final class MCPActivityLog {
    /// Keep the file useful for "last 100 calls" without growing forever.
    static let maximumStoredRecords = 500
    static let maximumLogBytes = 768 * 1024

    let fileURL: URL
    let sentinelURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = MCPRuntime.activityLogURL,
        sentinelURL: URL = MCPRuntime.stopSentinelURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.sentinelURL = sentinelURL
        self.fileManager = fileManager
    }

    // MARK: Write

    static func encodeLine(_ record: MCPActivityRecord) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(record) else { return nil }
        var line = data
        line.append(0x0A)
        return line
    }

    static func decode(line: String) -> MCPActivityRecord? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MCPActivityRecord.self, from: data)
    }

    func append(_ record: MCPActivityRecord) throws {
        try ensureDirectory()
        let line = Self.encodeLine(record) ?? Data()
        guard !line.isEmpty else { return }
        if !fileManager.fileExists(atPath: fileURL.path) {
            try line.write(to: fileURL)
        } else {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        }
        trimIfNeeded()
    }

    func append(tool: String, device: String?, ok: Bool, durationMs: Int, detail: String) {
        try? append(
            MCPActivityRecord(
                tool: tool, device: device, ok: ok, durationMs: durationMs, detail: detail))
    }

    // MARK: Read

    func read(limit: Int = 100) -> [MCPActivityRecord] {
        guard limit > 0, let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return []
        }
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
        let tail = lines.suffix(limit)
        return tail.compactMap { Self.decode(line: String($0)) }
    }

    var recordCount: Int {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return 0 }
        return data.reduce(into: 0) { count, byte in
            if byte == 0x0A { count += 1 }
        }
    }

    func clear() {
        try? fileManager.removeItem(at: fileURL)
    }

    // MARK: Retention

    private func trimIfNeeded() {
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
            let size = attributes[.size] as? NSNumber,
            size.intValue > Self.maximumLogBytes
        else { return }
        let records = read(limit: Self.maximumStoredRecords)
        var data = Data()
        for record in records {
            if let line = Self.encodeLine(record) { data.append(line) }
        }
        try? data.write(to: fileURL)
    }

    // MARK: Stop sentinel

    var stopRequested: Bool {
        fileManager.fileExists(atPath: sentinelURL.path)
    }

    func requestStop() {
        try? ensureDirectory()
        try? Data("stop\n".utf8).write(to: sentinelURL)
    }

    func clearStop() {
        try? fileManager.removeItem(at: sentinelURL)
    }

    private func ensureDirectory() throws {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }
    }
}
