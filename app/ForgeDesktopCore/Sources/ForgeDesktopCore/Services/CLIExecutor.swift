import Foundation

public protocol CLIExecutor: Sendable {
    func run(executable: String, arguments: [String], workingDirectory: String?, timeout: TimeInterval?) async throws -> Data
}

extension CLIExecutor {
    public func run(executable: String, arguments: [String]) async throws -> Data {
        try await run(executable: executable, arguments: arguments, workingDirectory: nil, timeout: nil)
    }

    public func run(executable: String, arguments: [String], workingDirectory: String?) async throws -> Data {
        try await run(executable: executable, arguments: arguments, workingDirectory: workingDirectory, timeout: nil)
    }

    public func run(executable: String, arguments: [String], timeout: TimeInterval?) async throws -> Data {
        try await run(executable: executable, arguments: arguments, workingDirectory: nil, timeout: timeout)
    }
}

/// Thread-safe continuation guard to prevent double-resume in Process + timeout races.
private final class ContinuationGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<Data, Error>
    private var timeoutItem: DispatchWorkItem?

    init(continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func setTimeoutItem(_ item: DispatchWorkItem) {
        lock.withLock { timeoutItem = item }
    }

    func resume(with result: Result<Data, Error>) {
        lock.withLock {
            guard !resumed else { return }
            resumed = true
            continuation.resume(with: result)
        }
    }

    func cancelTimeout() {
        lock.withLock { timeoutItem?.cancel() }
    }
}

public struct ProcessExecutor: CLIExecutor {
    public init() {}

    public func run(executable: String, arguments: [String], workingDirectory: String?, timeout: TimeInterval?) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        if let dir = workingDirectory {
            guard FileManager.default.fileExists(atPath: dir) else {
                throw ForgeError.unexpected("Working directory does not exist: \(dir)")
            }
            process.currentDirectoryURL = URL(fileURLWithPath: dir, isDirectory: true)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            let guard_ = ContinuationGuard(continuation: continuation)

            if let timeout {
                let item = DispatchWorkItem { [process] in
                    if process.isRunning {
                        process.terminate()
                    }
                    guard_.resume(with: .failure(ForgeError.claudeTimeout))
                }
                guard_.setTimeoutItem(item)
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
            }

            process.terminationHandler = { proc in
                guard_.cancelTimeout()
                let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                if proc.terminationStatus == 0 {
                    guard_.resume(with: .success(stdout))
                } else {
                    let stderrString = String(data: stderr, encoding: .utf8) ?? ""
                    guard_.resume(with: .failure(ForgeError.cliExitCode(
                        Int(proc.terminationStatus),
                        stderr: stderrString
                    )))
                }
            }

            do {
                try process.run()
            } catch {
                guard_.cancelTimeout()
                guard_.resume(with: .failure(ForgeError.cliNotFound))
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

    public func run(executable: String, arguments: [String], workingDirectory: String?, timeout: TimeInterval?) async throws -> Data {
        try result.get()
    }
}
