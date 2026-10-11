import Foundation
import IconzCore

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

    func focus(workspace: String) async throws {
        _ = try await run(["workspace", workspace])
    }

    func events() -> AsyncStream<AeroSpaceEvent> {
        AsyncStream { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = CLIParsing.subscribeArguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice

            let lines = LineSplitter()
            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    continuation.finish()
                    return
                }
                for line in lines.append(data) {
                    if let event = CLIParsing.event(fromLine: line) { continuation.yield(event) }
                }
            }
            let box = ProcessBox(process)
            process.terminationHandler = { _ in
                Subscriptions.remove(box)
                continuation.finish()
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

    private func run(_ arguments: [String]) async throws -> Data {
        let executable = executable
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
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

final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}

/// Live `aerospace subscribe` children, so they can be killed synchronously when the app
/// exits. Otherwise they outlive us until their next write hits the closed pipe.
enum Subscriptions {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var boxes: [ObjectIdentifier: ProcessBox] = [:]

    static func add(_ box: ProcessBox) {
        lock.withLock { boxes[ObjectIdentifier(box)] = box }
    }

    static func remove(_ box: ProcessBox) {
        _ = lock.withLock { boxes.removeValue(forKey: ObjectIdentifier(box)) }
    }

    static var liveCount: Int { lock.withLock { boxes.count } }

    static func terminateAll() {
        let live = lock.withLock { Array(boxes.values) }
        for box in live where box.process.isRunning { box.process.terminate() }
    }
}
