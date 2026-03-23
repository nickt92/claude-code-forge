import Foundation

public protocol CLIExecutor: Sendable {
    func run(executable: String, arguments: [String]) async throws -> Data
}

public struct ProcessExecutor: CLIExecutor {
    public init() {}

    public func run(executable: String, arguments: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    let stderrString = String(data: stderr, encoding: .utf8) ?? ""
                    continuation.resume(throwing: ForgeError.cliExitCode(
                        Int(proc.terminationStatus),
                        stderr: stderrString
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ForgeError.cliNotFound)
            }
        }
    }
}

public final class MockExecutor: CLIExecutor, Sendable {
    private let result: Result<Data, Error>

    public init(data: Data) {
        self.result = .success(data)
    }

    public init(error: Error) {
        self.result = .failure(error)
    }

    public func run(executable: String, arguments: [String]) async throws -> Data {
        try result.get()
    }
}
