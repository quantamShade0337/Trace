import Foundation
import Darwin

enum InspectorError: LocalizedError, Sendable {
    case invalidInput(String)
    case command(String)
    case timeout
    case outputLimit
    case storage(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let reason), .command(let reason), .storage(let reason): reason
        case .timeout: "The diagnostic timed out. Check connectivity or try a smaller hop limit."
        case .outputLimit: "The diagnostic exceeded the 4 MB output limit. Narrow the request and retry."
        }
    }
}

struct CommandResult: Sendable {
    let output: String
    let status: Int32
}

/// Owns a single child process on the concurrent executor. No shell is involved.
/// Both pipes are drained together, avoiding blocked stderr and unbounded buffers.
struct CommandRunner: Sendable {
    @concurrent
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15,
                    onLine: (@Sendable (String) async -> Void)? = nil) async throws -> CommandResult {
        try Task.checkCancellation()
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "LANG": "C"]
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        pipe.fileHandleForWriting.closeFile()
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        defer {
            if process.isRunning {
                process.terminate()
                // Only our own child is signalled; no privilege elevation or shell descendants.
                if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
            }
            pipe.fileHandleForReading.closeFile()
        }
        let clock = ContinuousClock()
        let start = clock.now
        var data = Data()
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            try Task.checkCancellation()
            if start.duration(to: clock.now) > .seconds(timeout) { throw InspectorError.timeout }
            var reachedEOF = false
            while true {
                let count = Darwin.read(descriptor, &buffer, buffer.count)
                if count == 0 { reachedEOF = true; break }
                if count < 0 {
                    if errno == EINTR { continue }
                    if errno == EAGAIN || errno == EWOULDBLOCK { break }
                    throw InspectorError.command("Could not read diagnostic output (errno \(errno)).")
                }
                data.append(contentsOf: buffer.prefix(count))
                guard data.count <= 4_194_304 else { throw InspectorError.outputLimit }
                if let onLine {
                    pending.append(contentsOf: buffer.prefix(count))
                    while let newline = pending.firstIndex(of: 10) {
                        let line = String(decoding: pending[..<newline], as: UTF8.self)
                        pending.removeSubrange(...newline)
                        await onLine(line)
                    }
                }
            }
            if !process.isRunning && reachedEOF { break }
            try await Task.sleep(for: .milliseconds(60))
        }
        if !pending.isEmpty, let onLine { await onLine(String(decoding: pending, as: UTF8.self)) }
        return CommandResult(output: String(decoding: data, as: UTF8.self), status: process.terminationStatus)
    }
}
