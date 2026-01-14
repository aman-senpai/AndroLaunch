import Foundation
import Combine

protocol CommandExecutorProtocol {
    func execute(_ command: String) -> AnyPublisher<String, Error>
    func executeAsync(_ command: String) -> AnyPublisher<String, Error>
}

final class CommandExecutor: CommandExecutorProtocol {
    func execute(_ command: String) -> AnyPublisher<String, Error> {
        return Future<String, Error> { promise in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", command]

                try process.run()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                if let errorString = String(data: errorData, encoding: .utf8), !errorString.isEmpty {
                    promise(.failure(ADBError.commandFailed(errorString)))
                    return
                }

                if let outputString = String(data: outputData, encoding: .utf8) {
                    promise(.success(outputString))
                } else {
                    promise(.failure(ADBError.unknown("Failed to decode command output")))
                }
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    func executeAsync(_ command: String) -> AnyPublisher<String, Error> {
        return Future<String, Error> { promise in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", command]

                try process.run()

                // Set up async reading
                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.count > 0 {
                        if let output = String(data: data, encoding: .utf8) {
                            promise(.success(output))
                        }
                    }
                }

                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.count > 0 {
                        if let error = String(data: data, encoding: .utf8) {
                            promise(.failure(ADBError.commandFailed(error)))
                        }
                    }
                }
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }
}