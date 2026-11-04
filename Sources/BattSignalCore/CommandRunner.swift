import Foundation

struct CommandResult: Sendable {
    let status: Int32
    let output: Data
    let errorOutput: String
    let timedOut: Bool
}

enum CommandRunner {
    /// Runs a command off the main thread, reading stdout and stderr concurrently so a chatty process can't block.
    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                var environment = ProcessInfo.processInfo.environment
                environment["NO_COLOR"] = "1"
                process.environment = environment

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                let errorOutput = Locked(Data())
                let killedForTimeout = Locked(false)
                stderr.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    errorOutput.mutate { $0.append(chunk) }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let killer = DispatchWorkItem {
                    guard process.isRunning else { return }
                    killedForTimeout.mutate { $0 = true }
                    process.terminate()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

                let output = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                killer.cancel()
                stderr.fileHandleForReading.readabilityHandler = nil

                continuation.resume(returning: CommandResult(
                    status: process.terminationStatus,
                    output: output,
                    errorOutput: String(decoding: errorOutput.value.suffix(400), as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    timedOut: killedForTimeout.value
                ))
            }
        }
    }
}

private final class Locked<Value>: @unchecked Sendable {
    private var stored: Value
    private let lock = NSLock()

    init(_ value: Value) {
        stored = value
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.withLock { body(&stored) }
    }

    var value: Value {
        lock.withLock { stored }
    }
}

func locateExecutable(_ name: String) -> URL? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        .map { "\($0)/\(name)" }
        .first { FileManager.default.isExecutableFile(atPath: $0) }
        .map { URL(fileURLWithPath: $0) }
}
