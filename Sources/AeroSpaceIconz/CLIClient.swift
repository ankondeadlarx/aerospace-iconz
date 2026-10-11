import Foundation
import IconzCore
import Synchronization

enum CLIError: Error {
    case exitStatus(Int32)
}

/// `AeroSpaceClient` backed by the `aerospace` CLI.
struct CLIClient: AeroSpaceClient {
    let executable: URL

    init(candidates: [String]) {
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

    func focus(workspace: WorkspaceName) async throws {
        _ = try await run(["workspace", workspace.rawValue])
    }

    func events() -> AsyncStream<AeroSpaceEvent> {
        AsyncStream { continuation in
            let (process, output) = makeProcess(CLIParsing.subscribeArguments)

            // Finish only once every line has been delivered (pipe EOF) and the process is
            // gone and untracked (termination). Either can happen first.
            let finished = Countdown(2) { continuation.finish() }
            let lines = LineSplitter()
            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    finished.tick()
                    return
                }
                for line in lines.append(data) {
                    if let event = CLIParsing.event(fromLine: line) { continuation.yield(event) }
                }
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
                // Read before waiting so a full pipe can't deadlock the child.
                let data = output.fileHandleForReading.readDataToEndOfFile()
                exited.wait()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: CLIError.exitStatus(process.terminationStatus))
                }
            }
        }
    }
}

/// Splits a byte stream into newline-terminated lines. Only touched from the pipe's
/// readability handler, which runs serially.
private final class LineSplitter: @unchecked Sendable {
    private var buffer = Data()

    func append(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines
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

final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}

/// Live `aerospace subscribe` children, so they can be killed synchronously when the app
/// exits. Otherwise they outlive us until their next write hits the closed pipe.
enum Subscriptions {
    private static let boxes = Mutex<[ObjectIdentifier: ProcessBox]>([:])

    static func add(_ box: ProcessBox) {
        boxes.withLock { $0[ObjectIdentifier(box)] = box }
    }

    static func remove(_ box: ProcessBox) {
        _ = boxes.withLock { $0.removeValue(forKey: ObjectIdentifier(box)) }
    }

    static var liveCount: Int { boxes.withLock { $0.count } }

    static func terminateAll() {
        let live = boxes.withLock { Array($0.values) }
        for box in live where box.process.isRunning { box.process.terminate() }
    }
}
