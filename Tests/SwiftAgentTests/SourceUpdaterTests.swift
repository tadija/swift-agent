import Foundation
import XCTest
import SwiftAgent
@testable import SwiftAgentCLI

final class SourceUpdaterTests: XCTestCase {
    let files = FileManager.default
    let agent = AgentDefinition(name: "Fixture Agent", executableName: "fixture")
    let sha = String(repeating: "a", count: 40)

    func testConfiguration() throws {
        XCTAssertEqual(try SourceUpdateConfiguration(repository: "https://example.com/product").reference, "main")
        for repository in ["", "relative", "-option", "http://example.com/a", "https://", "https://example.com/\n"] {
            XCTAssertThrowsError(try SourceUpdateConfiguration(repository: repository))
        }
        for reference in ["", "-option", "hello world", "main\n"] {
            XCTAssertThrowsError(try SourceUpdateConfiguration(repository: "file:///tmp/source", reference: reference))
        }
    }

    func fixture(_ body: (URL, URL, URL, SourceUpdater) throws -> Void) throws {
        let root = files.temporaryDirectory.appendingPathComponent("source update tests " + UUID().uuidString)
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: root); Cancellation.requested = 0 }
        let destination = root.appendingPathComponent("fixture")
        let build = root.appendingPathComponent("build")
        try files.createDirectory(at: build, withIntermediateDirectories: false)
        for (url, value) in [(destination, "old binary"), (build.appendingPathComponent("fixture"), "new binary")] {
            try Data(value.utf8).write(to: url)
            try files.setAttributes([.posixPermissions: 0o751], ofItemAtPath: url.path)
        }
        let updater = SourceUpdater(configuration: try .init(repository: "file:///trusted/source", reference: "refs/tags/v1"), agent: agent)
        try body(root, destination, build, updater)
    }

    func result(_ args: [String], _ build: URL) -> CommandResult {
        let output = args.contains("rev-parse") ? sha : args.last == "--show-bin-path" ? build.path : args.last == "--version" ? "Fixture Agent 1.0.0" : ""
        return CommandResult(status: 0, output: output, timedOut: false)
    }

    func testAtomicUpdateSymlinkPermissionsRevisionAndCleanup() throws {
        try fixture { root, destination, build, updater in
            let link = root.appendingPathComponent("link")
            try files.createSymbolicLink(at: link, withDestinationURL: destination)
            var calls: [[String]] = []
            var temporary: URL?
            try updater.update(executable: link) { args, cwd in
                calls.append(args)
                if temporary == nil { temporary = cwd }
                XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "old binary")
                return result(args, build)
            }
            XCTAssertTrue(calls.contains(["git", "fetch", "--", "origin", "refs/tags/v1"]))
            XCTAssertTrue(calls.contains(["git", "checkout", "--detach", sha]))
            XCTAssertTrue(calls.contains(["swift", "build", "-c", "release", "--product", "fixture"]))
            XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "new binary")
            XCTAssertEqual(try files.destinationOfSymbolicLink(atPath: link.path), destination.path)
            XCTAssertEqual((try files.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber)?.intValue, 0o751)
            XCTAssertFalse(files.fileExists(atPath: try XCTUnwrap(temporary).path))
            XCTAssertFalse(try files.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".fixture-update-") })
        }
    }

    func testFailuresPreserveInstallationAndCleanResources() throws {
        for failure in ["clone", "fetch", "rev-parse", "checkout", "build", "missing", "directory", "symlink", "empty", "noexec", "binpath", "version", "truncated", "utf8", "timeout", "cancel", "replace"] {
            try fixture { root, destination, build, updater in
                var temporary: URL?
                XCTAssertThrowsError(try updater.update(executable: destination) { args, cwd in
                    if temporary == nil { temporary = cwd }
                    if args.contains(failure) { return CommandResult(status: 1, output: "controlled failure", timedOut: false) }
                    if args.last == "--show-bin-path" {
                        if failure == "binpath" { return CommandResult(status: 0, output: "relative\npath", timedOut: false) }
                        let artifact = build.appendingPathComponent("fixture")
                        if ["missing", "directory", "symlink"].contains(failure) { try files.removeItem(at: artifact) }
                        if failure == "empty" { try Data().write(to: artifact) }
                        if failure == "noexec" { try files.setAttributes([.posixPermissions: 0o644], ofItemAtPath: artifact.path) }
                        if failure == "directory" { try files.createDirectory(at: artifact, withIntermediateDirectories: false) }
                        if failure == "symlink" { try files.createSymbolicLink(at: artifact, withDestinationURL: destination) }
                    }
                    if args.last == "--version" {
                        if failure == "cancel" { Cancellation.requested = 1 }
                        if failure == "replace" { try files.moveItem(at: destination, to: root.appendingPathComponent("saved")); try files.createDirectory(at: destination, withIntermediateDirectories: false) }
                        if failure == "version" { return CommandResult(status: 0, output: "Other Agent 1.0", timedOut: false) }
                        if failure == "truncated" { return CommandResult(status: 0, output: "Fixture Agent 1", timedOut: false, outputTruncated: true) }
                        if failure == "utf8" { return CommandResult(status: 0, output: "Fixture Agent 1", timedOut: false, outputIsUTF8: false) }
                        if failure == "timeout" { return CommandResult(status: 0, output: "", timedOut: true) }
                    }
                    return result(args, build)
                }, failure)
                let old = failure == "replace" ? root.appendingPathComponent("saved") : destination
                XCTAssertEqual(try String(contentsOf: old, encoding: .utf8), "old binary", failure)
                if let temporary { XCTAssertFalse(files.fileExists(atPath: temporary.path), failure) }
                XCTAssertFalse(try files.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".fixture-update-") }, failure)
            }
        }
    }

    func testOverlappingUpdateIsRejectedAndLockReleases() throws {
        try fixture { _, destination, build, updater in
            var nested = false
            try updater.update(executable: destination) { args, _ in
                if !nested {
                    nested = true
                    XCTAssertThrowsError(try updater.update(executable: destination) { _, _ in XCTFail("locked update launched a process"); return result([], build) })
                }
                return result(args, build)
            }
            try updater.update(executable: destination) { args, _ in result(args, build) }
        }
    }

    func testManagedPathsAndPermissionErrorsNeverLaunchProcesses() throws {
        let updater = SourceUpdater(configuration: try .init(repository: "file:///trusted/source"), agent: agent)
        for path in ["/usr/bin/fixture", "/opt/homebrew/Cellar/fixture", "/home/linuxbrew/.linuxbrew/Cellar/fixture", "/nix/store/fixture", "/tmp/source/.build/release/fixture"] {
            XCTAssertThrowsError(try updater.update(executable: URL(fileURLWithPath: path)) { _, _ in XCTFail("managed installation"); return result([], URL(fileURLWithPath: "/tmp")) })
        }
        try fixture { root, destination, _, updater in
            try files.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
            defer { try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
            if files.isWritableFile(atPath: root.path) { throw XCTSkip("privileged account bypasses directory permissions") }
            XCTAssertThrowsError(try updater.update(executable: destination) { _, _ in XCTFail("unwritable installation"); return result([], root) })
            XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "old binary")
        }
    }

    func testReplacementErrorPreservesOriginalAndCleansStaging() throws {
        try fixture { root, destination, build, updater in
            XCTAssertThrowsError(try updater.update(executable: destination, replace: { _, _ in -1 }) { args, _ in
                result(args, build)
            })
            XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "old binary")
            XCTAssertFalse(try files.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".fixture-update-") })
        }
    }

    func testSignalInterruptionTerminatesProcessAndPreservesInstallation() throws {
        try fixture { _, destination, build, updater in
            Cancellation.install()
            let runner = CommandRunner()
            var temporary: URL?
            let start = Date()
            XCTAssertThrowsError(try updater.update(executable: destination) { _, cwd in
                temporary = cwd
                return try runner.run("/bin/sh", ["-c", "kill -TERM \"$PPID\"; sleep 30"], cwd: cwd)
            })
            XCTAssertLessThan(Date().timeIntervalSince(start), 5)
            XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "old binary")
            XCTAssertFalse(files.fileExists(atPath: try XCTUnwrap(temporary).path))
            Cancellation.requested = 0
            try updater.update(executable: destination) { args, _ in result(args, build) }
        }
    }

    func testCLIWithoutSourceUpdates() throws {
        XCTAssertEqual(AgentCLI.run(agent: agent, arguments: ["--help"]), 0)
        XCTAssertEqual(AgentCLI.run(agent: agent, arguments: ["update"]), 1)
    }

    func testLocalRepositoryEndToEnd() throws {
        try fixture { root, destination, _, _ in
            let source = root.appendingPathComponent("source")
            try files.createDirectory(at: source.appendingPathComponent("Sources/fixture"), withIntermediateDirectories: true)
            try Data("""
            // swift-tools-version: 6.4
            import PackageDescription
            let package = Package(name: "fixture", targets: [.executableTarget(name: "fixture")])
            """.utf8).write(to: source.appendingPathComponent("Package.swift"))
            try Data("print(\"Fixture Agent 2.0.0\")\n".utf8).write(to: source.appendingPathComponent("Sources/fixture/main.swift"))
            let runner = CommandRunner()
            for args in [["init", "-b", "main"], ["add", "."], ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-m", "fixture"], ["tag", "v2"]] {
                XCTAssertEqual(try runner.run("/usr/bin/env", ["git"] + args, cwd: source).status, 0)
            }
            let revision = try runner.run("/usr/bin/env", ["git", "rev-parse", "HEAD"], cwd: source).output.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(try runner.run("/usr/bin/env", ["git", "checkout", "-b", "next"], cwd: source).status, 0)
            try Data("print(\"Fixture Agent 3.0.0\")\n".utf8).write(to: source.appendingPathComponent("Sources/fixture/main.swift"))
            XCTAssertEqual(try runner.run("/usr/bin/env", ["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-am", "next"], cwd: source).status, 0)
            for (reference, version) in [("refs/tags/v2", "2.0.0"), ("refs/heads/next", "3.0.0"), (revision, "2.0.0")] {
                let updater = SourceUpdater(configuration: try .init(repository: source.absoluteString, reference: reference), agent: agent)
                try updater.update(executable: destination)
                XCTAssertEqual(try runner.run(destination.path, ["--version"], cwd: root).output.trimmingCharacters(in: .whitespacesAndNewlines), "Fixture Agent " + version)
            }
        }
    }
}
