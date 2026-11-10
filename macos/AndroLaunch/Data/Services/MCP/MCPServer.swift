//
//  MCPServer.swift
//  AndroLaunch
//
//  The stdio entry point for "Android Use". Launched by an MCP client as
//  `<AndroLaunch.app>/Contents/MacOS/AndroLaunch --mcp-server`, it speaks
//  line-delimited JSON-RPC 2.0 over stdin/stdout. Nothing is sent to stdout
//  except protocol messages; diagnostics go to stderr.
//
//  There is no network listener. The Settings switch is enforced per tools/call,
//  and the Settings Stop button writes a sentinel file that exits this process
//  immediately (including while a long ADB command is running).
//

import Foundation
#if canImport(Darwin)
    import Darwin
#endif

/// Entry point used by AppDelegate when the binary is launched with `--mcp-server`.
enum MCPServerMain {
    static func run() {
        MCPStdioServer().run()
    }
}

final class MCPStdioServer {
    private let log: MCPActivityLog
    private let executor: MCPToolExecutor
    private let output = FileHandle.standardOutput
    private var watchdog: DispatchSourceTimer?

    init(
        log: MCPActivityLog = MCPActivityLog(),
        executor: MCPToolExecutor? = nil
    ) {
        self.log = log
        self.executor = executor ?? MCPToolExecutor(log: log)
    }

    func run() {
        writeDiagnostic(
            "AndroLaunch Android Use MCP server ready (stdio). "
                + "Android Use is \(MCPRuntime.isEnabled() ? "enabled" : "disabled") in Settings.\n")

        startStopWatchdog()

        while let line = readLine(strippingNewline: true) {
            if log.stopRequested {
                writeDiagnostic("Stop requested from AndroLaunch Settings; exiting.\n")
                break
            }
            handle(line: line)
            if log.stopRequested {
                writeDiagnostic("Stop requested from AndroLaunch Settings; exiting.\n")
                break
            }
        }

        watchdog?.cancel()
        watchdog = nil
        // Eof or stop: the client owns the other end; exit cleanly.
        exit(0)
    }

    // MARK: - Message handling

    private func handle(line: String) {
        switch MCPFraming.parseRequest(line: line) {
        case .failure(let error):
            write(
                MCPWire.error(
                    id: nil, code: error.errorCode, message: error.errorMessage))
            return
        case .success(let request):
            let response = MCPDispatcher.handle(request) { tool, arguments in
                self.executor.call(tool: tool, arguments: arguments)
            }
            if let response { write(response) }
        }
    }

    private func write(_ object: [String: Any]) {
        guard let data = MCPFraming.encodeLine(object) else {
            writeDiagnostic("Failed to encode a JSON-RPC response.\n")
            return
        }
        output.write(data)
    }

    private func writeDiagnostic(_ message: String) {
        FileHandle.standardError.write(Data(message.utf8))
    }

    // MARK: - Stop control

    /// The Settings Stop button must interrupt an idle session too, so a small
    /// watchdog exits even when stdin is blocked waiting for the next request.
    private func startStopWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            guard let self, self.log.stopRequested else { return }
            self.writeDiagnostic("Stop requested from AndroLaunch Settings; exiting.\n")
            exit(0)
        }
        timer.resume()
        watchdog = timer
    }
}
