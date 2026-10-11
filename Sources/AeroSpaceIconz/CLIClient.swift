import Foundation
import IconzCore
import Synchronization

enum CLIError: Error, Equatable {
    case exitStatus(Int32)
    case timedOut
}

/// `AeroSpaceClient` backed by the `aerospace` CLI.
struct CLIClient: AeroSpaceClient {
    let executable: URL
    let timeout: Duration

    init(candidates: [String], timeout: Duration) {
        self.timeout = timeout
        let path = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
        executable = URL(fileURLWithPath: path)
    }

    func snapshot() async throws -> Snapshot {
        async let windows = run(CLIParsing.listWindowsArguments)
        async let workspaces = run(CLIParsing.listWorkspacesArguments)
        return Snapshot(
            workspaces: try CLIParsing.workspaces(from: try await workspaces),
            windows: try CLIParsing.windows(from: try await windows)
        )
    }

    func mode() async throws -> String? {
        try CLIParsing.mode(from: try await run(CLIParsing.listModesArguments))
    }

    func focus(workspace: WorkspaceName) async throws {
        _ = try await run(["workspace", workspace.rawValue])
    }

    func events() -> AsyncStream<AeroSpaceEvent> {
        AsyncStream { continuation in
            let (process, output) = makeProcess(CLIParsing.subscribeArguments)

            // Finish only once every line has been delivered (pipe EOF) and the process is
            // gone and untracked (termination). Either can happen first.
            let finished = Countdown(2) { continuation.finish() }
            let lines = Mutex(LineSplitter())
            let deliver: @Sendable ([String]) -> Void = { lines in
                for line in lines {
                    if let event = CLIParsing.event(fromLine: line) { continuation.yield(event) }
                }
            }
            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    deliver(lines.withLock { $0.finish() })
                    finished.tick()
                    return
                }
                deliver(lines.withLock { $0.append(data) })
            }
            let box = ProcessBox(process)
            process.terminationHandler = { _ in
                Subscriptions.remove(box)
                finished.tick()
            }
            continuation.onTermination = { _ in
                if box.process.isRunning { box.process.terminate() }
            }
            // Tracked before launch so an instant exit can't remove it before it's added.
            Subscriptions.add(box)

            do {
                try process.run()
            } catch {
                // No launch, so no termination handler will ever untrack it.
                Subscriptions.remove(box)
                continuation.finish()
            }
        }
    }

    /// An unlaunched `aerospace` process with stdout piped back and stderr discarded.
    private func makeProcess(_ arguments: [String]) -> (Process, Pipe) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        return (process, output)
    }

    private func run(_ arguments: [String]) async throws -> Data {
        let (process, output) = makeProcess(arguments)
        let box = ProcessBox(process)
        let timeout = timeout.timeInterval
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = box.process
                // Not waitUntilExit(): it polls the run loop and adds ~60 ms per call.
                let exited = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in exited.signal() }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                // A stuck call would block the read below, and with it every later refresh.
                let watchdog = DispatchWorkItem {
                    if box.process.isRunning { kill(box.process.processIdentifier, SIGKILL) }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                // Read before waiting so a full pipe can't deadlock the child.
                let data = output.fileHandleForReading.readDataToEndOfFile()
                exited.wait()
                watchdog.cancel()
                if process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGKILL {
                    continuation.resume(throwing: CLIError.timedOut)
                } else if process.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: CLIError.exitStatus(process.terminationStatus))
                }
            }
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}

/// Runs `action` once `tick()` has been called `count` times, from any threads.
private final class Countdown: Sendable {
    private let remaining: Mutex<Int>
    private let action: @Sendable () -> Void

    init(_ count: Int, action: @escaping @Sendable () -> Void) {
        remaining = Mutex(count)
        self.action = action
    }

    func tick() {
        let isLast = remaining.withLock { value in
            value -= 1
            return value == 0
        }
        if isLast { action() }
    }
}
