import Foundation
import Synchronization

/// Carries a `Process` into `@Sendable` closures; it's only started, signalled and read.
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
