import Foundation
import Combine

protocol CommandExecutorProtocol {
    func execute(_ command: String) -> AnyPublisher<String, Error>
}

/// Runs a shell command and reports success from the process exit status.
///
/// `adb` writes plenty of *non-fatal* text to stderr (e.g. the `* daemon started
/// successfully` notice), so stderr content must never be treated as failure on its
/// own. Only a non-zero exit status is a failure; stderr is then surfaced as the
/// diagnostic message instead of being swallowed.
final class CommandExecutor: CommandExecutorProtocol {
    private let workQueue = DispatchQueue(
        label: "com.androlaunch.command-executor", qos: .userInitiated)

    func execute(_ command: String) -> AnyPublisher<String, Error> {
        let queue = workQueue
        return Future<String, Error> { promise in
            // Never block the caller (this is invoked from the main queue by the
            // pairing service); do the process work on a background queue and let
            // subscribers hop back with `receive(on:)`.
            queue.async {
                let process = Process()
                let outputPipe = Pipe()
                let errorPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", command]
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                } catch {
                    // Unblock the stderr drain below before bailing out.
                    try? outputPipe.fileHandleForWriting.close()
                    try? errorPipe.fileHandleForWriting.close()
                    promise(.failure(error))
                    return
                }

                // Drain stderr concurrently: the child can block on a full stderr
                // pipe while we are still reading stdout to EOF, and vice versa.
                var errorData = Data()
                let errorDrained = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .userInitiated).async {
                    errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    errorDrained.signal()
                }

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                errorDrained.wait()
                process.waitUntilExit()

                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    promise(.success(output))
                } else {
                    let detail =
                        errorOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? output.trimmingCharacters(in: .whitespacesAndNewlines)
                        : errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    promise(
                        .failure(
                            ADBError.commandFailed(
                                detail.isEmpty ? "exit code \(process.terminationStatus)" : detail)))
                }
            }
        }.eraseToAnyPublisher()
    }
}
