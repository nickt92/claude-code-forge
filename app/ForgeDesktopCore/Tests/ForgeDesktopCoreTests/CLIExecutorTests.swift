import XCTest
@testable import ForgeDesktopCore

/// The pipe-drain contract.
///
/// `run()` used to read both pipes only inside `terminationHandler`, i.e. after
/// the process exited. A child that writes more than the pipe buffer — about
/// 64KB — blocks in `write()` and therefore never exits, so the handler never
/// runs and nothing ever drains the pipe. `forge analyze --json` and
/// `forge dashboard` both exceed that routinely, and the symptom was an app
/// wedged with `isBusy` stuck true and no way to cancel.
///
/// Every test here that pushes more than 64KB fails against that version by
/// hanging until the XCTest timeout.
final class CLIExecutorTests: XCTestCase {

    private let executor = ProcessExecutor()

    /// Writes `count` bytes to stdout without a shell in the middle.
    private func generator(bytes count: Int) -> (String, [String]) {
        ("/bin/dd", ["if=/dev/zero", "bs=1024", "count=\(count / 1024)", "status=none"])
    }

    func testLargeStdoutCompletesWithoutDeadlock() async throws {
        let (exe, args) = generator(bytes: 1_048_576)
        let data = try await executor.run(
            executable: exe, arguments: args, workingDirectory: nil, timeout: 30
        )
        XCTAssertEqual(data.count, 1_048_576)
    }

    func testLargeStderrCompletesWithoutDeadlock() async throws {
        // stderr alone can wedge it: the old code drained neither pipe early.
        let script = "/bin/dd if=/dev/zero bs=1024 count=1024 status=none >&2"
        let data = try await executor.run(
            executable: "/bin/sh", arguments: ["-c", script],
            workingDirectory: nil, timeout: 30
        )
        XCTAssertEqual(data.count, 0, "stdout should be empty")
    }

    func testLargeOutputOnBothPipesCompletes() async throws {
        let script = """
        /bin/dd if=/dev/zero bs=1024 count=512 status=none
        /bin/dd if=/dev/zero bs=1024 count=512 status=none >&2
        """
        let data = try await executor.run(
            executable: "/bin/sh", arguments: ["-c", script],
            workingDirectory: nil, timeout: 30
        )
        XCTAssertEqual(data.count, 524_288)
    }

    func testLargeOutputIsStillDeliveredOnNonZeroExit() async throws {
        // The failure path reads the same buffers, so it deadlocked too.
        let script = "/bin/dd if=/dev/zero bs=1024 count=256 status=none; exit 3"
        do {
            _ = try await executor.run(
                executable: "/bin/sh", arguments: ["-c", script],
                workingDirectory: nil, timeout: 30
            )
            XCTFail("expected a non-zero exit to throw")
        } catch let ForgeError.cliExitCode(code, _) {
            XCTAssertEqual(code, 3)
        }
    }

    func testStdoutIsCompleteNotTruncated() async throws {
        // Draining incrementally must not lose or reorder bytes.
        let script = "for i in $(seq 1 5000); do echo \"line $i\"; done"
        let data = try await executor.run(
            executable: "/bin/sh", arguments: ["-c", script],
            workingDirectory: nil, timeout: 30
        )
        let text = String(data: data, encoding: .utf8) ?? ""
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 5000)
        XCTAssertEqual(lines.first, "line 1")
        XCTAssertEqual(lines.last, "line 5000")
    }

    func testTimeoutTerminatesTheChildAndThrows() async throws {
        let start = Date()
        do {
            _ = try await executor.run(
                executable: "/bin/sleep", arguments: ["30"],
                workingDirectory: nil, timeout: 1
            )
            XCTFail("expected a timeout")
        } catch ForgeError.claudeTimeout {
            // The point is that it returns promptly rather than waiting for
            // EOF the killed child may never deliver.
            XCTAssertLessThan(Date().timeIntervalSince(start), 10)
        }
    }

    func testTimeoutDoesNotHangWhenTheChildIsAlsoWriting() async throws {
        // A child producing output while the timeout fires exercises the race
        // between the collector and the timeout path.
        let script = "while true; do /bin/dd if=/dev/zero bs=1024 count=64 status=none; done"
        do {
            _ = try await executor.run(
                executable: "/bin/sh", arguments: ["-c", script],
                workingDirectory: nil, timeout: 1
            )
            XCTFail("expected a timeout")
        } catch ForgeError.claudeTimeout {
            // expected
        }
    }

    func testFastExitIsNotLost() async throws {
        let data = try await executor.run(
            executable: "/bin/echo", arguments: ["hi"],
            workingDirectory: nil, timeout: 30
        )
        XCTAssertEqual(String(data: data, encoding: .utf8), "hi\n")
    }

    func testEmptyOutputResolves() async throws {
        let data = try await executor.run(
            executable: "/usr/bin/true", arguments: [],
            workingDirectory: nil, timeout: 30
        )
        XCTAssertEqual(data.count, 0)
    }

    func testMissingExecutableThrowsRatherThanHanging() async throws {
        do {
            _ = try await executor.run(
                executable: "/nonexistent/binary", arguments: [],
                workingDirectory: nil, timeout: 30
            )
            XCTFail("expected cliNotFound")
        } catch ForgeError.cliNotFound {
            // expected
        }
    }

    func testMissingWorkingDirectoryThrows() async throws {
        do {
            _ = try await executor.run(
                executable: "/bin/echo", arguments: ["hi"],
                workingDirectory: "/nonexistent/dir", timeout: 30
            )
            XCTFail("expected a thrown error")
        } catch {
            // expected
        }
    }

    func testStderrIsSurfacedOnFailureWhenStdoutIsEmpty() async throws {
        let script = "echo 'boom' >&2; exit 2"
        do {
            _ = try await executor.run(
                executable: "/bin/sh", arguments: ["-c", script],
                workingDirectory: nil, timeout: 30
            )
            XCTFail("expected a non-zero exit")
        } catch let ForgeError.cliExitCode(code, stderr) {
            XCTAssertEqual(code, 2)
            XCTAssertTrue(stderr.contains("boom"), "got: \(stderr)")
        }
    }

    func testStdoutIsSurfacedOnFailureWhenStderrIsEmpty() async throws {
        // forge's own fail() writes to stdout, so discarding it would leave the
        // user with an exit code and no explanation.
        let script = "echo 'the reason' ; exit 4"
        do {
            _ = try await executor.run(
                executable: "/bin/sh", arguments: ["-c", script],
                workingDirectory: nil, timeout: 30
            )
            XCTFail("expected a non-zero exit")
        } catch let ForgeError.cliExitCode(code, stderr) {
            XCTAssertEqual(code, 4)
            XCTAssertTrue(stderr.contains("the reason"), "got: \(stderr)")
        }
    }

    // ── stream() had the same bug on stderr ───────────────────

    func testStreamCompletesWhenStderrIsLarge() async throws {
        let script = """
        /bin/dd if=/dev/zero bs=1024 count=512 status=none >&2
        echo done
        """
        var lines: [String] = []
        for try await chunk in executor.stream(
            executable: "/bin/sh", arguments: ["-c", script],
            workingDirectory: nil, timeout: 30
        ) {
            if let s = String(data: chunk, encoding: .utf8) { lines.append(s) }
        }
        XCTAssertTrue(lines.contains { $0.contains("done") }, "got: \(lines)")
    }

    func testStreamSurfacesStderrOnFailure() async throws {
        let script = "echo 'stream boom' >&2; exit 5"
        do {
            for try await _ in executor.stream(
                executable: "/bin/sh", arguments: ["-c", script],
                workingDirectory: nil, timeout: 30
            ) {}
            XCTFail("expected a non-zero exit")
        } catch let ForgeError.cliExitCode(code, stderr) {
            XCTAssertEqual(code, 5)
            XCTAssertTrue(stderr.contains("stream boom"), "got: \(stderr)")
        }
    }
}
