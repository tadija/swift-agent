import Foundation
import ProcessSupport
#if os(Linux)
import Glibc
#else
import Darwin
#endif

public enum AgentError: Error, CustomStringConvertible {
    case message(String)
    public var description: String { switch self { case .message(let value): return value } }
}

public enum Cancellation {
    public nonisolated(unsafe) static var requested: Int32 = 0
    public nonisolated(unsafe) static var stopFile: URL?
    public static var shouldStop: Bool {
        requested != 0 || stopFile.map { FileManager.default.fileExists(atPath: $0.path) } == true
    }
    public static func install() {
        signal(SIGINT) { _ in Cancellation.requested = 1 }
        signal(SIGTERM) { _ in Cancellation.requested = 1 }
    }
}

public struct CommandResult {
    public let status: Int32
    public let output: String
    public let timedOut: Bool
    public let outputTruncated: Bool
    public let outputIsUTF8: Bool
    public init(status: Int32, output: String, timedOut: Bool, outputTruncated: Bool = false, outputIsUTF8: Bool = true) {
        self.status = status
        self.output = output
        self.timedOut = timedOut
        self.outputTruncated = outputTruncated
        self.outputIsUTF8 = outputIsUTF8
    }
}

/// Files rather than pipes avoid deadlocks when a child produces large output.
public final class CommandRunner {
    public init() {}
    public func run(_ executable: String, _ arguments: [String], cwd: URL,
                    timeout: TimeInterval = 1800, environment: [String: String] = [:],
                    cancellable: Bool = true) throws -> CommandResult {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw AgentError.message("Cannot create command log")
        }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close(); try? FileManager.default.removeItem(at: temporary) }
        let input = open("/dev/null", O_RDONLY | O_CLOEXEC)
        guard input >= 0 else { throw AgentError.message("Cannot open /dev/null") }
        defer { close(input) }
        let inherited = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        let environmentValues = inherited.merging(environment) { _, new in new }.map { "\($0.key)=\($0.value)" }
        let argumentPointers = ([executable] + arguments).map { strdup($0) } + [nil]
        let environmentPointers = environmentValues.map { strdup($0) } + [nil]
        defer {
            argumentPointers.forEach { free($0) }
            environmentPointers.forEach { free($0) }
        }
        var pid: pid_t = 0
        let spawnResult = argumentPointers.withUnsafeBufferPointer { argv in
            environmentPointers.withUnsafeBufferPointer { envp in
                swift_agent_spawn(executable, argv.baseAddress!, envp.baseAddress!, cwd.path, input, output.fileDescriptor, &pid)
            }
        }
        guard spawnResult == 0 else { throw AgentError.message("Cannot launch \(executable): \(String(cString: strerror(spawnResult)))") }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var expired = false
        var status: Int32 = 0
        var pollInterval: TimeInterval = 0.001
        while true {
            let waited = waitpid(pid, &status, WNOHANG)
            if waited == pid { break }
            if waited == -1 {
                if errno == EINTR { continue }
                throw AgentError.message("Cannot wait for child process")
            }
            if ProcessInfo.processInfo.systemUptime >= deadline || (cancellable && Cancellation.shouldStop) {
                expired = ProcessInfo.processInfo.systemUptime >= deadline
                kill(-pid, SIGTERM)
                let grace = ProcessInfo.processInfo.systemUptime + 1
                var reaped = false
                while ProcessInfo.processInfo.systemUptime < grace {
                    if waitpid(pid, &status, WNOHANG) == pid { reaped = true; break }
                    Thread.sleep(forTimeInterval: 0.02)
                }
                kill(-pid, SIGKILL)
                if !reaped {
                    while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
                }
                break
            }
            // Reap short Git commands promptly; back off for long harness/test runs.
            Thread.sleep(forTimeInterval: pollInterval)
            pollInterval = min(pollInterval * 2, 0.02)
        }
        // Clean up ordinary background children even after the main command exited.
        kill(-pid, SIGKILL)
        let reader = try FileHandle(forReadingFrom: temporary)
        defer { try? reader.close() }
        let size = try reader.seekToEnd()
        try reader.seek(toOffset: size > 1_048_576 ? size - 1_048_576 : 0)
        let data = try reader.read(upToCount: 1_048_576) ?? Data()
        let exitCode: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        return CommandResult(status: exitCode,
                             output: String(decoding: data, as: UTF8.self), timedOut: expired,
                             outputTruncated: size > 1_048_576, outputIsUTF8: String(data: data, encoding: .utf8) != nil)
    }
}
