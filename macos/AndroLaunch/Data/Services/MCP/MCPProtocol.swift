//
//  MCPProtocol.swift
//  AndroLaunch
//
//  The Model Context Protocol wire format for "Android Use": JSON-RPC 2.0,
//  one JSON object per line over stdio. Everything here is Foundation-only and
//  synchronous so the framing rules can be tested without a process, a device
//  or the app running.
//
//  Reference: MCP specification, stdio transport. We deliberately implement the
//  small, stable surface an AI client actually uses — initialize, tools/list,
//  tools/call, ping and the `notifications/initialized` notification — instead
//  of advertising capabilities we do not provide.
//

import Foundation

// MARK: - Identifiers

/// A JSON-RPC request id. MCP clients commonly send integers, but strings are
/// legal and must be echoed with the same type.
enum MCPRequestID: Equatable {
    case number(Int)
    case string(String)

    var jsonObject: Any {
        switch self {
        case .number(let value): return NSNumber(value: value)
        case .string(let value): return value
        }
    }

    static func parse(_ raw: Any) -> MCPRequestID? {
        if let number = raw as? NSNumber {
            // Reject booleans, which bridge to NSNumber as well.
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            let double = number.doubleValue
            guard double.rounded() == double,
                double >= Double(Int.min), double <= Double(Int.max)
            else { return nil }
            return .number(Int(double))
        }
        if let string = raw as? String { return .string(string) }
        return nil
    }
}

// MARK: - Requests

struct MCPRequest: Equatable {
    /// `nil` for notifications (JSON-RPC messages without an id).
    let id: MCPRequestID?
    let method: String
    let params: [String: Any]

    static func == (lhs: MCPRequest, rhs: MCPRequest) -> Bool {
        lhs.id == rhs.id
            && lhs.method == rhs.method
            && NSDictionary(dictionary: lhs.params).isEqual(to: rhs.params)
    }
}

enum MCPFramingError: Error, Equatable, CustomStringConvertible {
    case emptyLine
    case malformedJSON
    case notAnObject
    case invalidVersion(String)
    case missingMethod
    case invalidID

    var description: String {
        switch self {
        case .emptyLine: return "empty line"
        case .malformedJSON: return "line is not valid JSON"
        case .notAnObject: return "JSON-RPC message must be an object"
        case .invalidVersion(let value): return "unsupported jsonrpc version \(value)"
        case .missingMethod: return "missing method"
        case .invalidID: return "invalid request id"
        }
    }

    /// JSON-RPC error code and message used when this line cannot be handled.
    var errorCode: Int {
        switch self {
        case .emptyLine, .malformedJSON:
            return MCPErrorCode.parseError
        case .notAnObject, .invalidVersion, .missingMethod, .invalidID:
            return MCPErrorCode.invalidRequest
        }
    }

    var errorMessage: String { description }
}

enum MCPErrorCode {
    static let parseError = -32700
    static let invalidRequest = -32600
    static let methodNotFound = -32601
    static let invalidParams = -32602
    static let internalError = -32603
}

// MARK: - Framing

enum MCPFraming {
    /// Parses exactly one line into a request. Leading/trailing whitespace is
    /// ignored; a blank line is a framing error, not a request.
    static func parseRequest(line: String) -> Result<MCPRequest, MCPFramingError> {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyLine) }
        guard let data = trimmed.data(using: .utf8) else {
            return .failure(.malformedJSON)
        }
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            return .failure(.malformedJSON)
        }
        guard let object = raw as? [String: Any] else {
            return .failure(.notAnObject)
        }
        if let version = object["jsonrpc"] as? String, version != "2.0" {
            return .failure(.invalidVersion(version))
        }

        var id: MCPRequestID?
        if let rawID = object["id"], !(rawID is NSNull) {
            guard let parsed = MCPRequestID.parse(rawID) else {
                return .failure(.invalidID)
            }
            id = parsed
        }

        guard let method = object["method"] as? String, !method.isEmpty else {
            return .failure(.missingMethod)
        }

        var params: [String: Any] = [:]
        if let rawParams = object["params"] {
            if rawParams is NSNull {
                params = [:]
            } else if let dictionary = rawParams as? [String: Any] {
                params = dictionary
            } else {
                return .failure(.notAnObject)
            }
        }

        return .success(MCPRequest(id: id, method: method, params: params))
    }

    /// Serializes one response/notification object as a single JSON line with a
    /// trailing newline. Sorted keys keep captured transcripts deterministic.
    static func encodeLine(_ object: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        do {
            let data = try JSONSerialization.data(
                withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
            var line = data
            line.append(0x0A)
            return line
        } catch {
            return nil
        }
    }
}

// MARK: - Responses

enum MCPWire {
    static let supportedProtocolVersion = "2025-06-18"
    static let serverName = "androlaunch-android-use"
    static let serverVersion = "1.0.0"

    static let instructions = """
        AndroLaunch Android Use controls a connected Android device over local \
        ADB. No network port is opened; the server speaks JSON-RPC over stdio. \
        Start with phone_list_devices, then pass the device serial to other \
        tools. Android Use must be enabled in AndroLaunch → Settings → AI.
        """

    static func result(id: MCPRequestID?, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id?.jsonObject ?? NSNull(), "result": result]
    }

    static func error(
        id: MCPRequestID?, code: Int, message: String, data: Any? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = ["code": code, "message": message]
        if let data { payload["data"] = data }
        return ["jsonrpc": "2.0", "id": id?.jsonObject ?? NSNull(), "error": payload]
    }

    static func notification(_ method: String, params: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "method": method, "params": params]
    }

    static func textContent(_ text: String) -> [String: Any] {
        ["type": "text", "text": text]
    }

    static func imageContent(base64: String) -> [String: Any] {
        ["type": "image", "data": base64, "mimeType": "image/png"]
    }
}

// MARK: - Tool call result

/// One tool response in MCP's `content` shape. Kept independent of AppKit so a
/// dispatcher test can stub tool execution.
struct MCPCallResult: Equatable {
    let content: [[String: Any]]
    let isError: Bool

    static func text(_ text: String, isError: Bool = false) -> MCPCallResult {
        MCPCallResult(content: [MCPWire.textContent(text)], isError: isError)
    }

    static func image(base64: String, caption: String) -> MCPCallResult {
        MCPCallResult(
            content: [MCPWire.imageContent(base64: base64), MCPWire.textContent(caption)],
            isError: false)
    }

    static func failure(_ message: String) -> MCPCallResult {
        .text(message, isError: true)
    }

    static func == (lhs: MCPCallResult, rhs: MCPCallResult) -> Bool {
        lhs.isError == rhs.isError
            && NSArray(array: lhs.content).isEqual(to: rhs.content)
    }
}

// MARK: - Dispatcher

/// Pure request handling: maps a parsed request plus a tools catalogue and an
/// injected tool caller to a response object (or `nil` for notifications).
enum MCPDispatcher {
    static func handle(
        _ request: MCPRequest,
        catalogue: [MCPToolDefinition] = MCPToolCatalog.tools,
        callTool: ((String, [String: Any]) -> MCPCallResult)? = nil
    ) -> [String: Any]? {
        switch request.method {
        case "initialize":
            return MCPWire.result(id: request.id, initializeResult())

        case "notifications/initialized", "notifications/cancelled":
            // Notifications never get a response.
            return nil

        case "ping":
            guard request.id != nil else { return nil }
            return MCPWire.result(id: request.id, [:])

        case "tools/list":
            guard request.id != nil else { return nil }
            return MCPWire.result(id: request.id, [
                "tools": catalogue.map { $0.wireObject }
            ])

        case "tools/call":
            guard request.id != nil else { return nil }
            return handleToolCall(request, catalogue: catalogue, callTool: callTool)

        default:
            guard request.id != nil else { return nil }
            return MCPWire.error(
                id: request.id, code: MCPErrorCode.methodNotFound,
                message: "Method not found: \(request.method)")
        }
    }

    static func initializeResult() -> [String: Any] {
        [
            "protocolVersion": MCPWire.supportedProtocolVersion,
            "capabilities": [
                "tools": ["listChanged": false]
            ],
            "serverInfo": [
                "name": MCPWire.serverName,
                "version": MCPWire.serverVersion,
            ],
            "instructions": MCPWire.instructions,
        ]
    }

    private static func handleToolCall(
        _ request: MCPRequest,
        catalogue: [MCPToolDefinition],
        callTool: ((String, [String: Any]) -> MCPCallResult)?
    ) -> [String: Any] {
        guard let name = request.params["name"] as? String, !name.isEmpty else {
            return MCPWire.error(
                id: request.id, code: MCPErrorCode.invalidParams,
                message: "tools/call requires a tool name")
        }
        var arguments: [String: Any] = [:]
        if let raw = request.params["arguments"] {
            if raw is NSNull {
                arguments = [:]
            } else if let dictionary = raw as? [String: Any] {
                arguments = dictionary
            } else {
                return MCPWire.error(
                    id: request.id, code: MCPErrorCode.invalidParams,
                    message: "tools/call arguments must be an object")
            }
        }
        guard catalogue.contains(where: { $0.name == name }) else {
            return MCPWire.error(
                id: request.id, code: MCPErrorCode.invalidParams,
                message: "Unknown tool: \(name)")
        }
        guard let callTool else {
            return MCPWire.error(
                id: request.id, code: MCPErrorCode.internalError,
                message: "Tool execution is not available in this process")
        }
        let result = callTool(name, arguments)
        return MCPWire.result(id: request.id, [
            "content": result.content,
            "isError": result.isError,
        ])
    }
}

// MARK: - Runtime state shared with servers

/// Foundation-only names used by both the in-app controller and the stdio
/// server process.
enum MCPRuntime {
    /// UserDefaults key for the "Android Use" switch. Default is off.
    static let enabledDefaultsKey = "mcp.androidUse.enabled"

    static let supportDirectoryName = "AndroLaunch"
    static let activityLogFileName = "mcp-activity.jsonl"
    static let stopSentinelFileName = "mcp-stop.sentinel"

    /// `ANDROLAUNCH_MCP_SUPPORT_DIR` lets a headless test or an administrator
    /// point the activity log and stop sentinel at a different directory instead
    /// of the user's Application Support folder.
    static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["ANDROLAUNCH_MCP_SUPPORT_DIR"],
            !override.isEmpty
        {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(supportDirectoryName, isDirectory: true)
    }

    static var activityLogURL: URL {
        supportDirectory.appendingPathComponent(activityLogFileName)
    }

    static var stopSentinelURL: URL {
        supportDirectory.appendingPathComponent(stopSentinelFileName)
    }

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledDefaultsKey)
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: enabledDefaultsKey)
    }
}
