//
//  MCPLogicTests.swift
//  CoreLogicTests
//
//  Pure-logic coverage for "Android Use": JSON-RPC framing and dispatch, tool
//  catalogue/schema consistency, argument validation and shell escaping, the
//  activity log format (metadata only), the stop sentinel, companion response
//  parsing and the enable-switch defaults.
//
//  No device, no ADB, no app run loop: every function here is deterministic.
//  Wire `runMCPLogicTests()` from `main.swift` (see scripts/test-macos-logic.sh).
//

import Foundation

// MARK: - Helpers

private func mcpFreshDefaults(_ label: String) -> UserDefaults {
    let name = "com.senpai.AndroLaunch.mcp-tests.\(label).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private func mcpResponseResult(_ response: [String: Any]?) -> [String: Any]? {
    response?["result"] as? [String: Any]
}

private func mcpResponseError(_ response: [String: Any]?) -> [String: Any]? {
    response?["error"] as? [String: Any]
}

private func mcpRequest(_ json: String) -> Result<MCPRequest, MCPFramingError> {
    MCPFraming.parseRequest(line: json)
}

private func mcpFramingError(_ json: String) -> MCPFramingError? {
    if case .failure(let error) = mcpRequest(json) { return error }
    return nil
}

private func mcpArguments(_ pairs: [String: Any]) -> [String: Any] { pairs }

// MARK: - Tests

func runMCPLogicTests() {
    mcpFramingTests()
    mcpDispatcherTests()
    mcpCatalogueTests()
    mcpPlannerTests()
    mcpEscapingTests()
    mcpActivityLogTests()
    mcpRuntimeTests()
    mcpCompanionWireTests()
}

// MARK: - Framing

private func mcpFramingTests() {
    suite("MCPFraming.parseRequest") {
        switch mcpRequest(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#
        ) {
        case .success(let request):
            expect(request.id == .number(1), "numeric id parses")
            expect(request.method == "initialize", "method parses")
            expect(
                request.params["protocolVersion"] as? String == "2025-06-18",
                "params object parses")
        case .failure(let error):
            expect(false, "initialize line parses (got \(error))")
        }

        switch mcpRequest(#"{"jsonrpc":"2.0","id":"req-7","method":"ping"}"#) {
        case .success(let request):
            expect(request.id == .string("req-7"), "string id parses")
            expect(request.params.isEmpty, "missing params defaults to empty")
        case .failure:
            expect(false, "string id request parses")
        }

        switch mcpRequest(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) {
        case .success(let request):
            expect(request.id == nil, "notification has no id")
            expect(request.method == "notifications/initialized", "notification method parses")
        case .failure:
            expect(false, "notification parses")
        }

        expect(
            mcpFramingError("{not json") == .malformedJSON,
            "malformed JSON is a parse error")
        expect(
            mcpFramingError("[1,2,3]") == .notAnObject,
            "JSON array is not a request object")
        expect(
            mcpFramingError(#"{"jsonrpc":"1.0","id":1,"method":"ping"}"#)
                == .invalidVersion("1.0"),
            "wrong JSON-RPC version is rejected")
        expect(
            mcpFramingError(#"{"jsonrpc":"2.0","id":1}"#) == .missingMethod,
            "missing method is rejected")
        expect(
            mcpFramingError(#"{"jsonrpc":"2.0","id":true,"method":"ping"}"#) == .invalidID,
            "boolean id is rejected")
        expect(mcpFramingError("   \n ") == .emptyLine, "blank line is a framing error")

        expect(
            MCPErrorCode.parseError == -32700 && MCPErrorCode.invalidRequest == -32600
                && MCPErrorCode.methodNotFound == -32601
                && MCPErrorCode.invalidParams == -32602,
            "JSON-RPC error codes")
    }

    suite("MCPFraming.encodeLine") {
        let response = MCPWire.result(id: .number(4), ["ok": true])
        guard let data = MCPFraming.encodeLine(response) else {
            expect(false, "response encodes")
            return
        }
        expect(data.last == 0x0A, "line ends with a newline")
        expect(data.filter { $0 == 0x0A }.count == 1, "exactly one line per response")
        let text = String(decoding: data, as: UTF8.self)
        expect(text.contains("\"jsonrpc\":\"2.0\""), "encodes jsonrpc version")
        expect(text.contains("\"id\":4"), "encodes numeric id")
    }
}

// MARK: - Dispatcher

private func mcpDispatcherTests() {
    suite("MCPDispatcher") {
        let initialize = mcpRequest(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#)
        if case .success(let request) = initialize {
            let response = MCPDispatcher.handle(request)
            let result = mcpResponseResult(response)
            expect(
                result?["protocolVersion"] as? String == MCPWire.supportedProtocolVersion,
                "initialize returns the supported protocol version")
            let serverInfo = result?["serverInfo"] as? [String: Any]
            expect(serverInfo?["name"] as? String == "androlaunch-android-use", "server name")
            let capabilities = result?["capabilities"] as? [String: Any]
            expect(capabilities?["tools"] != nil, "declares the tools capability")
            expect(result?["instructions"] as? String != nil, "returns usage instructions")
        } else {
            expect(false, "initialize request parses")
        }

        if case .success(let request) = mcpRequest(
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#) {
            let response = MCPDispatcher.handle(request)
            let tools = mcpResponseResult(response)?["tools"] as? [[String: Any]]
            expect(tools?.count == MCPToolCatalog.tools.count, "tools/list returns every tool")
            let names = Set(tools?.compactMap { $0["name"] as? String } ?? [])
            expect(names == Set(MCPToolCatalog.toolNames), "tools/list names match the catalogue")
            let schemasAreObjects = (tools ?? []).allSatisfy {
                ($0["inputSchema"] as? [String: Any])?["type"] as? String == "object"
            }
            expect(schemasAreObjects, "every tool schema is a JSON object schema")
        } else {
            expect(false, "tools/list request parses")
        }

        if case .success(let request) = mcpRequest(#"{"jsonrpc":"2.0","id":3,"method":"ping"}"#) {
            let response = MCPDispatcher.handle(request)
            expect(mcpResponseResult(response)?.isEmpty == true, "ping returns an empty result")
        } else {
            expect(false, "ping request parses")
        }

        if case .success(let request) = mcpRequest(
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) {
            expect(MCPDispatcher.handle(request) == nil, "initialized notification has no response")
        } else {
            expect(false, "initialized notification parses")
        }

        if case .success(let request) = mcpRequest(
            #"{"jsonrpc":"2.0","id":5,"method":"no/such/method"}"#) {
            let error = mcpResponseError(MCPDispatcher.handle(request))
            expect(error?["code"] as? Int == MCPErrorCode.methodNotFound, "unknown method error")
        }

        if case .success(let request) = mcpRequest(
            #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"nope","arguments":{}}}"#
        ) {
            let error = mcpResponseError(MCPDispatcher.handle(request))
            expect(error?["code"] as? Int == MCPErrorCode.invalidParams, "unknown tool error")
        }

        if case .success(let request) = mcpRequest(
            #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"arguments":{}}}"#) {
            let error = mcpResponseError(MCPDispatcher.handle(request))
            expect(error?["code"] as? Int == MCPErrorCode.invalidParams, "missing tool name error")
        }

        if case .success(let request) = mcpRequest(
            #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"phone_list_devices","arguments":{}}}"#
        ) {
            var calledTool: String?
            let response = MCPDispatcher.handle(request) { tool, _ in
                calledTool = tool
                return .text("stub result")
            }
            expect(calledTool == "phone_list_devices", "tools/call delegates to the executor")
            let result = mcpResponseResult(response)
            let content = result?["content"] as? [[String: Any]]
            expect(content?.first?["text"] as? String == "stub result", "text content is returned")
            expect(result?["isError"] as? Bool == false, "successful calls are not errors")
        }

        if case .success(let request) = mcpRequest(
            #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"phone_tap","arguments":{"x":1}}}"#
        ) {
            let response = MCPDispatcher.handle(request) { _, _ in .failure("bad") }
            let result = mcpResponseResult(response)
            expect(result?["isError"] as? Bool == true, "tool errors are surfaced via isError")
            let content = result?["content"] as? [[String: Any]]
            expect(content?.first?["text"] as? String == "bad", "error text is returned")
        }
    }
}

// MARK: - Catalogue

private func mcpCatalogueTests() {
    suite("MCPToolCatalog") {
        let expected: Set<String> = [
            "phone_list_devices", "phone_device_info", "phone_screenshot", "phone_tap",
            "phone_swipe", "phone_input_text", "phone_press_key", "phone_shell",
            "phone_list_apps", "phone_launch_app", "phone_clipboard_get",
            "phone_clipboard_set", "phone_notifications", "phone_open_url", "phone_ui_dump",
        ]
        expect(Set(MCPToolCatalog.toolNames) == expected, "exactly the v1 tool set is exposed")
        expect(MCPToolCatalog.toolNames.count == 15, "fifteen tools")
        expect(
            MCPToolCatalog.toolNames != MCPToolCatalog.toolNames.sorted(),
            "stable order is not alphabetical")

        let listing = MCPToolCatalog.tools.map(\.wireObject)
        let allHaveDescriptions = listing.allSatisfy {
            ($0["description"] as? String)?.isEmpty == false
        }
        expect(allHaveDescriptions, "every tool has a description")

        if let tap = MCPToolCatalog.tool(named: "phone_tap") {
            expect(tap.required == ["x", "y"], "phone_tap requires x and y")
            expect(tap.properties["serial"] != nil, "device tools accept an optional serial")
        } else {
            expect(false, "phone_tap is in the catalogue")
        }

        if let shell = MCPToolCatalog.tool(named: "phone_shell") {
            expect(shell.required == ["command"], "phone_shell requires command")
            let max = shell.properties["command"]?["maxLength"] as? Int
            expect(max == 4096, "shell command length is bounded")
        }

        expect(
            MCPToolCatalog.tool(named: "phone_missing") == nil, "unknown tool lookup is nil")
    }
}

// MARK: - Planner

private func mcpPlannerTests() {
    suite("MCPToolPlanner") {
        guard let listPlan = try? MCPToolPlanner.plan(
            tool: "phone_list_devices", arguments: [:]) else {
            expect(false, "list devices plans")
            return
        }
        expect(listPlan == .adb(serial: nil, arguments: ["devices", "-l"], timeout: 15, requiresDevice: false), "list devices plan")

        guard let tapPlan = try? MCPToolPlanner.plan(
            tool: "phone_tap", arguments: ["x": 100, "y": 250, "serial": "R58M123"]) else {
            expect(false, "tap plans")
            return
        }
        if case .adb(let serial, let arguments, _, let requiresDevice) = tapPlan {
            expect(serial == "R58M123", "tap keeps the serial")
            expect(requiresDevice, "tap requires a device")
            expect(arguments == ["-s", "R58M123", "shell", "input tap 100 250"], "tap ADB arguments")
        } else {
            expect(false, "tap is an adb plan")
        }

        do {
            _ = try MCPToolPlanner.plan(tool: "phone_tap", arguments: ["y": 1])
            expect(false, "tap without x throws")
        } catch let error as MCPToolError {
            expect(error == .missingArgument("x"), "tap without x reports the missing argument")
        } catch {
            expect(false, "unexpected tap error")
        }
        do {
            _ = try MCPToolPlanner.plan(tool: "phone_tap", arguments: ["x": "10", "y": 1])
            expect(false, "string x is rejected")
        } catch let error as MCPToolError {
            expect(error == .invalidArgument("x must be a number"), "string x reports a clear error")
        } catch {
            expect(false, "unexpected tap error")
        }
        do {
            _ = try MCPToolPlanner.plan(tool: "phone_tap", arguments: ["x": -4, "y": 1])
            expect(false, "negative coordinates are rejected")
        } catch {
            expect(true, "negative coordinates are rejected")
        }

        guard let swipe = try? MCPToolPlanner.plan(
            tool: "phone_swipe", arguments: ["x1": 1, "y1": 2, "x2": 3, "y2": 4]) else {
            expect(false, "swipe plans")
            return
        }
        if case .adb(_, let arguments, _, _) = swipe {
            expect(
                arguments.last == "input swipe 1 2 3 4 300", "swipe default duration is 300ms")
        } else {
            expect(false, "swipe is an adb plan")
        }

        guard let keyPlan = try? MCPToolPlanner.plan(
            tool: "phone_press_key", arguments: ["key": "home"]) else {
            expect(false, "key plans")
            return
        }
        if case .adb(_, let arguments, _, _) = keyPlan {
            expect(arguments.last == "input keyevent 3", "home maps to keycode 3")
        }

        guard let appPlan = try? MCPToolPlanner.plan(
            tool: "phone_launch_app", arguments: ["package": "com.android.settings"]) else {
            expect(false, "launch app plans")
            return
        }
        expect(appPlan == .launchApp(serial: nil, package: "com.android.settings"), "launch plan")

        do {
            _ = try MCPToolPlanner.plan(tool: "phone_launch_app", arguments: ["package": "not a package"])
            expect(false, "invalid package is rejected")
        } catch {
            expect(true, "invalid package is rejected")
        }

        do {
            _ = try MCPToolPlanner.plan(
                tool: "phone_clipboard_set", arguments: ["text": "hi", "serial": "abc;rm -rf"])
            expect(false, "shell characters in serial are rejected")
        } catch {
            expect(true, "shell characters in serial are rejected")
        }

        guard let urlPlan = try? MCPToolPlanner.plan(
            tool: "phone_open_url", arguments: ["url": "https://example.com/a?b=1&c=2"]) else {
            expect(false, "open URL plans")
            return
        }
        if case .adb(_, let arguments, _, _) = urlPlan {
            expect(
                arguments.last?.contains("android.intent.action.VIEW") == true,
                "open URL uses a VIEW intent")
            expect(
                arguments.last?.contains("'https://example.com/a?b=1&c=2'") == true,
                "open URL is shell-quoted")
        }
        do {
            _ = try MCPToolPlanner.plan(tool: "phone_open_url", arguments: ["url": "file:///etc/passwd"])
            expect(false, "non-http URL is rejected")
        } catch {
            expect(true, "non-http URL is rejected")
        }

        guard let notifications = try? MCPToolPlanner.plan(
            tool: "phone_notifications", arguments: [:]) else {
            expect(false, "notifications plan")
            return
        }
        expect(notifications == .notifications(serial: nil), "notifications plan uses the companion")

        guard let clipboard = try? MCPToolPlanner.plan(
            tool: "phone_clipboard_get", arguments: ["serial": "192.168.1.5:5555"]) else {
            expect(false, "clipboard plan")
            return
        }
        expect(
            clipboard == .companion(serial: "192.168.1.5:5555", command: "clip.get", argument: ""),
            "clipboard read plan")

        guard let screenshot = try? MCPToolPlanner.plan(
            tool: "phone_screenshot", arguments: [:]) else {
            expect(false, "screenshot plan")
            return
        }
        expect(screenshot == .screenshot(serial: nil), "screenshot plan")

        expect(
            (try? MCPToolPlanner.plan(tool: "phone_unknown", arguments: [:])) == nil,
            "unknown tool throws")
    }
}

// MARK: - Escaping

private func mcpEscapingTests() {
    suite("MCPInputEscaping") {
        expect(MCPInputEscaping.shellQuote("plain") == "'plain'", "plain shell quote")
        expect(
            MCPInputEscaping.shellQuote("it's") == "'it'\\''s'", "single quote is escaped")
        expect(
            MCPInputEscaping.shellQuote("$(rm -rf ~)") == "'$(rm -rf ~)'",
            "shell metacharacters are literal inside quotes")

        if let input = try? MCPInputEscaping.inputText("hello world") {
            expect(input == "'hello%sworld'", "spaces become %s inside the quoted input text")
        } else {
            expect(false, "single-line text escapes")
        }
        do {
            _ = try MCPInputEscaping.inputText("line one\nline two")
            expect(false, "newlines are rejected")
        } catch {
            expect(true, "newlines are rejected")
        }

        expect((try? MCPInputEscaping.keyEvent("home")) == "3", "home key")
        expect((try? MCPInputEscaping.keyEvent("KEYCODE_BACK")) == "4", "KEYCODE_ prefixed key")
        expect((try? MCPInputEscaping.keyEvent("Recents")) == "187", "case-insensitive key")
        expect((try? MCPInputEscaping.keyEvent("27")) == "27", "numeric keycode passes through")
        expect(
            (try? MCPInputEscaping.keyEvent("9999")) == nil, "out-of-range keycode is rejected")
        expect((try? MCPInputEscaping.keyEvent("bogus")) == nil, "unknown key is rejected")

        expect(
            MCPTextSanitizer.detail("line one\nline two") == "line one line two",
            "activity detail is forced onto one line")
        let long = String(repeating: "x", count: 400)
        let truncated = MCPTextSanitizer.detail(long, max: 100)
        expect(truncated.count == 101 && truncated.hasSuffix("…"), "activity detail is bounded")
    }
}

// MARK: - Activity log

private func mcpActivityLogTests() {
    suite("MCPActivityLog") {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-activity-tests-\(UUID().uuidString)", isDirectory: true)
        let logURL = directory.appendingPathComponent("mcp-activity.jsonl")
        let sentinelURL = directory.appendingPathComponent("mcp-stop.sentinel")
        let log = MCPActivityLog(fileURL: logURL, sentinelURL: sentinelURL)

        expect(log.read(limit: 100).isEmpty, "missing log reads as empty")
        expect(!log.stopRequested, "no stop sentinel by default")

        log.append(
            tool: "phone_list_devices", device: nil, ok: true, durationMs: 42,
            detail: "Completed")
        log.append(
            tool: "phone_shell", device: "R58M123", ok: false, durationMs: 900,
            detail: "Android command failed")

        let records = log.read(limit: 100)
        expect(records.count == 2, "both records read back")
        expect(records[0].tool == "phone_list_devices" && records[0].ok, "first record round-trips")
        expect(records[1].device == "R58M123" && records[1].ok == false, "second record round-trips")
        expect(records[1].durationMs == 900, "duration round-trips")
        expect(records[0].date.timeIntervalSince1970 > 0, "timestamp decodes as a date")

        if let data = try? Data(contentsOf: logURL),
            let text = String(data: data, encoding: .utf8)
        {
            expect(text.split(separator: "\n").count == 2, "one JSON object per line")
            let lowered = text.lowercased()
            expect(!lowered.contains("\"payload\""), "no payload field is persisted")
            expect(!lowered.contains("\"text\""), "no typed text is persisted")
            expect(!lowered.contains("\"command\""), "no shell command is persisted")
            expect(text.contains("\"duration_ms\":42"), "duration_ms uses the documented key")
        } else {
            expect(false, "activity log file exists")
        }

        guard let line = MCPActivityLog.encodeLine(records[0]),
            let decoded = MCPActivityLog.decode(line: String(decoding: line, as: UTF8.self))
        else {
            expect(false, "record line round-trips")
            return
        }
        expect(decoded == records[0], "record JSON round-trips")

        expect(MCPActivityLog.decode(line: "not json") == nil, "malformed log lines are dropped")

        log.requestStop()
        expect(log.stopRequested, "stop sentinel is written")
        log.clearStop()
        expect(!log.stopRequested, "stop sentinel is cleared")

        log.clear()
        expect(log.read(limit: 100).isEmpty, "clear removes the log")

        try? FileManager.default.removeItem(at: directory)
    }

    suite("MCPActivityRecency") {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-activity-tests-\(UUID().uuidString)", isDirectory: true)
        let logURL = directory.appendingPathComponent("mcp-activity.jsonl")
        let log = MCPActivityLog(
            fileURL: logURL, sentinelURL: directory.appendingPathComponent("sentinel"))
        for index in 0..<12 {
            log.append(
                tool: "phone_tap", device: "S", ok: true, durationMs: index,
                detail: "Completed")
        }
        expect(log.read(limit: 5).count == 5, "limit returns the tail")
        expect(log.read(limit: 5).last?.durationMs == 11, "tail keeps chronological order")
        try? FileManager.default.removeItem(at: directory)
    }
}

// MARK: - Runtime defaults

private func mcpRuntimeTests() {
    suite("MCPRuntime") {
        let defaults = mcpFreshDefaults("runtime")
        expect(!MCPRuntime.isEnabled(defaults: defaults), "Android Use is off by default")
        MCPRuntime.setEnabled(true, defaults: defaults)
        expect(MCPRuntime.isEnabled(defaults: defaults), "enable switch persists")
        MCPRuntime.setEnabled(false, defaults: defaults)
        expect(!MCPRuntime.isEnabled(defaults: defaults), "disable switch persists")
        expect(
            MCPRuntime.supportDirectory.lastPathComponent == "AndroLaunch",
            "activity files live under Application Support/AndroLaunch")
        expect(
            MCPRuntime.activityLogURL.lastPathComponent == "mcp-activity.jsonl",
            "documented log file name")
        expect(
            MCPRuntime.stopSentinelURL.lastPathComponent == "mcp-stop.sentinel",
            "documented stop sentinel name")
    }
}

// MARK: - Companion + ADB wire helpers

private func mcpCompanionWireTests() {
    suite("MCPADB wire helpers") {
        let line = MCPADBClient.companionRequestLine(command: "clip.set", argument: "hello")
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
        expect(parts.count == 3, "companion request has id, command and argument")
        expect(parts[1] == "clip.set", "companion command is plain")
        expect(
            String(
                data: Data(
                    base64Encoded: String(parts[2]).trimmingCharacters(
                        in: .whitespacesAndNewlines)) ?? Data(),
                encoding: .utf8) == "hello",
            "companion argument is base64")

        expect(
            (try? MCPADBClient.parseCompanionResponse("id\tok\taGVsbG8=")) == "hello",
            "ok response decodes the payload")
        do {
            _ = try MCPADBClient.parseCompanionResponse("id\terror\tZm9jdXNfcmVxdWlyZWQ=")
            expect(false, "error response throws")
        } catch {
            expect(true, "error response throws")
        }

        let deviceList = """
            List of devices attached
            R58M12ABCDE            device usb:341001X product:husky model:Pixel_9_Pro device:husky transport_id:1
            192.168.1.23:5555      device product:e3q model:SM_S938B device:e3q transport_id:2
            emulator-5554          offline transport_id:3
            """
        let devices = MCPADBClient.parseDevices(deviceList)
        expect(devices.count == 3, "three device rows parse")
        expect(devices[0].serial == "R58M12ABCDE" && devices[0].isReady, "USB device parses")
        expect(devices[0].model == "Pixel 9 Pro", "model underscores become spaces")
        expect(devices[0].transportLabel == "USB", "USB transport label")
        expect(devices[1].transportLabel == "Wi-Fi", "host:port transport label")
        expect(devices[2].isReady == false, "offline device is not ready")
        expect(
            MCPADBClient.parseDevices("adbaemon-start\nList of devices attached\n").isEmpty,
            "noise lines do not become devices")

        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
                        0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
                        0, 0, 0x04, 0x38, 0, 0, 0x09, 0x60])
        expect(MCPToolExecutor.pngDimensions(png)?.0 == 1080, "PNG width parses")
        expect(MCPToolExecutor.pngDimensions(png)?.1 == 2400, "PNG height parses")
        expect(MCPToolExecutor.pngDimensions(Data()) == nil, "empty data has no dimensions")

        expect(
            MCPToolExecutor.launchComponent(
                from: "priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=true\n"
                    + "com.android.settings/.Settings")
                == "com.android.settings/.Settings",
            "launch component parses")

        expect(
            MCPToolExecutor.formatPackages("package:com.android.settings\npackage:com.whatsapp")
                == "2 package(s):\ncom.android.settings\ncom.whatsapp",
            "package list is sorted and counted")

        let notificationJSON = """
            [{"pkg":"com.whatsapp","title":"Alice","text":"See you at 8"}]
            """
        expect(
            MCPToolExecutor.formatNotificationJSON(notificationJSON)?.contains("Alice") == true,
            "companion notification JSON formats")
        expect(
            MCPToolExecutor.formatNotificationJSON("not json") == nil,
            "invalid notification JSON returns nil for the dumpsys fallback")

        expect(
            MCPToolExecutor.activityDetail(for: MCPToolError.executionFailed("secret text"))
                == "Android command failed",
            "raw command output is not persisted in the activity log")
        expect(
            MCPToolExecutor.activityDetail(for: MCPToolError.stopped) == "Stopped by user",
            "stop is recorded honestly")
        expect(
            MCPToolExecutor.activityDetail(for: MCPToolError.disabled) == "Android Use is off",
            "disabled calls are recorded honestly")
    }

    suite("MCPADB device resolution rules") {
        let ready = MCPADBDevice(
            serial: "A", state: "device", model: "Pixel", product: nil, transportID: "1")
        let unauthorised = MCPADBDevice(
            serial: "B", state: "unauthorized", model: "Galaxy", product: nil, transportID: "2")
        // resolveSerial needs a client, so exercise the pure parser's state rules instead.
        expect(ready.isReady, "device state means ready")
        expect(!unauthorised.isReady, "unauthorized is not ready")

        expect(MCPDeviceID.isValid("R58M12ABCDE"), "USB serials are valid")
        expect(MCPDeviceID.isValid("192.168.1.5:5555"), "host:port serials are valid")
        expect(
            MCPDeviceID.isValid("adb-R58M12ABCDE-xyz._adb-tls-connect._tcp"),
            "mDNS serials are valid")
        expect(!MCPDeviceID.isValid(""), "empty serials are invalid")
        expect(!MCPDeviceID.isValid("a b"), "spaces in serials are invalid")
        expect(!MCPDeviceID.isValid("a;b"), "shell characters in serials are invalid")

        expect(MCPPackageName.isValid("com.android.settings"), "package names are valid")
        expect(!MCPPackageName.isValid("settings"), "single-segment packages are invalid")
        expect(!MCPPackageName.isValid("com..settings"), "empty package segments are invalid")
        expect(MCPURL.isOpenable("https://example.com"), "https URLs are openable")
        expect(MCPURL.isOpenable("http://192.168.1.2:8080/x"), "http URLs are openable")
        expect(!MCPURL.isOpenable("javascript:alert(1)"), "javascript URLs are rejected")
        expect(!MCPURL.isOpenable("https://"), "hostless URLs are rejected")
    }
}
