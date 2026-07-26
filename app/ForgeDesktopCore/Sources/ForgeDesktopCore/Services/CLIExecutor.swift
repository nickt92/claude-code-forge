import Foundation
import os

public protocol CLIExecutor: Sendable {
    func run(executable: String, arguments: [String], workingDirectory: String?, timeout: TimeInterval?) async throws -> Data
    func stream(executable: String, arguments: [String], workingDirectory: String?, timeout: TimeInterval?) -> AsyncThrowingStream<Data, Error>
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

    public func stream(executable: String, arguments: [String], workingDirectory: String?) -> AsyncThrowingStream<Data, Error> {
        stream(executable: executable, arguments: arguments, workingDirectory: workingDirectory, timeout: nil)
    }

    public func stream(executable: String, arguments: [String], workingDirectory: String?, timeout: TimeInterval?) -> AsyncThrowingStream<Data, Error> {
        // Default: collect all output via run(), then yield as a single chunk
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let data = try await self.run(executable: executable, arguments: arguments, workingDirectory: workingDirectory, timeout: timeout)
                    continuation.yield(data)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
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
    private static let logger = Logger(subsystem: "com.forge.desktop", category: "CLIExecutor")

    public init() {}

    public func stream(executable: String, arguments: [String], workingDirectory: String?, timeout: TimeInterval?) -> AsyncThrowingStream<Data, Error> {
        Self.logger.debug("Streaming: \(executable) \(arguments.joined(separator: " "), privacy: .public)")

        return AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            if let dir = workingDirectory {
                guard FileManager.default.fileExists(atPath: dir) else {
                    continuation.finish(throwing: ForgeError.unexpected("Working directory does not exist: \(dir)"))
                    return
                }
                process.currentDirectoryURL = URL(fileURLWithPath: dir, isDirectory: true)
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Buffer for partial line reads
            let lineBuffer = LineBuffer()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }

                let lines = lineBuffer.append(data)
                for line in lines {
                    continuation.yield(line)
                }
            }

            let timeoutGuard = StreamTimeoutGuard(process: process)

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil

                // Flush remaining buffer
                if let remaining = lineBuffer.flush() {
                    continuation.yield(remaining)
                }

                guard timeoutGuard.markFinished() else { return }

                if proc.terminationStatus != 0 {
                    let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrString = String(data: stderr, encoding: .utf8) ?? ""
                    Self.logger.error("Stream exit \(proc.terminationStatus): \(stderrString, privacy: .public)")
                    continuation.finish(throwing: ForgeError.cliExitCode(
                        Int(proc.terminationStatus),
                        stderr: stderrString
                    ))
                } else {
                    continuation.finish()
                }
            }

            // Timeout
            if let timeout {
                let item = DispatchWorkItem {
                    guard timeoutGuard.markFinished() else { return }
                    timeoutGuard.terminate()
                    continuation.finish(throwing: ForgeError.claudeTimeout)
                }
                timeoutGuard.setItem(item)
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
            }

            continuation.onTermination = { @Sendable _ in
                timeoutGuard.cancel()
                timeoutGuard.terminate()
            }

            do {
                try process.run()
            } catch {
                timeoutGuard.cancel()
                continuation.finish(throwing: ForgeError.cliNotFound)
            }
        }
    }

    public func run(executable: String, arguments: [String], workingDirectory: String?, timeout: TimeInterval?) async throws -> Data {
        Self.logger.debug("Running: \(executable) \(arguments.joined(separator: " "), privacy: .public)")
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
                let stderrString = String(data: stderr, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    if !stderrString.isEmpty {
                        Self.logger.info("stderr (exit 0): \(stderrString, privacy: .public)")
                    }
                    guard_.resume(with: .success(stdout))
                } else {
                    // The forge CLI's fail() writes user-facing errors to STDOUT.
                    // With an empty stderr, surface stdout instead of discarding
                    // the only explanation the user would ever get.
                    var detail = stderrString
                    if detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detail = String(data: stdout, encoding: .utf8) ?? ""
                    }
                    Self.logger.error("Exit \(proc.terminationStatus): \(detail, privacy: .public)")
                    guard_.resume(with: .failure(ForgeError.cliExitCode(
                        Int(proc.terminationStatus),
                        stderr: detail
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

/// Thread-safe timeout guard for streaming processes.
private final class StreamTimeoutGuard: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var item: DispatchWorkItem?
    private var finished = false

    init(process: Process) {
        self.process = process
    }

    func setItem(_ item: DispatchWorkItem) {
        lock.withLock { self.item = item }
    }

    func cancel() {
        lock.withLock { item?.cancel() }
    }

    /// Marks the stream as finished. Returns `true` if this was the first call.
    func markFinished() -> Bool {
        lock.withLock {
            guard !finished else { return false }
            finished = true
            item?.cancel()
            return true
        }
    }

    func terminate() {
        lock.withLock {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}

/// Splits incoming data into newline-delimited chunks for streaming.
final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) -> [Data] {
        lock.withLock {
            buffer.append(data)
            var lines: [Data] = []
            let newline = UInt8(ascii: "\n")

            while let index = buffer.firstIndex(of: newline) {
                let line = buffer[buffer.startIndex...index]
                lines.append(Data(line))
                buffer.removeSubrange(buffer.startIndex...index)
            }
            return lines
        }
    }

    func flush() -> Data? {
        lock.withLock {
            guard !buffer.isEmpty else { return nil }
            let remaining = buffer
            buffer = Data()
            return remaining
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

    public func stream(executable: String, arguments: [String], workingDirectory: String?, timeout: TimeInterval?) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            switch result {
            case .success(let data):
                // Yield line-by-line to simulate streaming
                let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
                for line in lines {
                    var lineData = Data(line)
                    lineData.append(UInt8(ascii: "\n"))
                    continuation.yield(lineData)
                }
                continuation.finish()
            case .failure(let error):
                continuation.finish(throwing: error)
            }
        }
    }
}
