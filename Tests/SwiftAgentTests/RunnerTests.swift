import XCTest
@testable import SwiftAgent

final class RunnerTests: RepositoryTestCase {
    func testScheduleLifecyclePreservesRepository() throws {
        let scheduler = try Scheduler(dataDirectory: data)
        let schedule = try scheduler.add(repository: checkout, executable: "/usr/local/bin/swift-agent", at: "00:00", duration: "4h")
        XCTAssertEqual(try scheduler.list().map(\.id), [schedule.id])
        let script = try String(contentsOf: scheduler.directory.appendingPathComponent(schedule.id + ".sh"), encoding: .utf8)
        XCTAssertFalse(script.contains("--count"))
        XCTAssertTrue(script.contains("--duration '4h'"))
        XCTAssertTrue(script.contains(checkout.path))
        XCTAssertThrowsError(try scheduler.remove("../unknown"))
        try scheduler.remove(schedule.id)
        XCTAssertTrue(try scheduler.list().isEmpty)
        XCTAssertEqual(try git(["status", "--porcelain"]), "")
    }
    func testExpiredDeadlineDoesNotInvokeHarness() throws {
        let config = try Configuration.load(repository: Repository(at: checkout), agent: .testAgent)
        let records = try Runner(agent: .testAgent).runSession(at: checkout, configuration: config,
            harness: FakeHarness { _ in XCTFail("Expired session invoked harness"); return self.success() },
            dataDirectory: data, deadline: Date(timeIntervalSinceNow: -1))
        XCTAssertTrue(records.isEmpty)
        try assertNoCommit()
    }
    func testStopWithoutActiveSessionIsRejected() throws {
        XCTAssertThrowsError(try Runner(agent: .testAgent).stop(at: checkout))
    }

    func testSessionStopsAtSaturation() throws {
        var config = try Configuration.load(repository: Repository(at: checkout), agent: .testAgent)
        config.maxIterations = 100
        let records = try Runner(agent: .testAgent).runSession(at: checkout, configuration: config,
            harness: FakeHarness(action: { _ in self.success() }), dataDirectory: data)
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.outcome == "no_candidate" })
        try assertNoCommit()
    }

    func testSessionCountUsesFreshWorktrees() throws {
        var config = try Configuration.load(repository: Repository(at: checkout), agent: .testAgent)
        config.maxIterations = 2
        var seen: Set<URL> = []
        let records = try Runner(agent: .testAgent).runSession(at: checkout, configuration: config,
            harness: FakeHarness(action: { cwd in
                seen.insert(cwd)
                try self.write("value.txt", UUID().uuidString, at: cwd)
                return self.success()
            }), dataDirectory: data)
        XCTAssertEqual(Set(records.map(\.sessionID)).count, 1)
        XCTAssertTrue(records.allSatisfy { $0.harness == "fake" })
        XCTAssertEqual(seen.count, 2)
        XCTAssertEqual(records.filter { $0.outcome == "committed" }.count, 2)
        XCTAssertEqual(try git(["rev-list", "--all", "--count"]), "3")
    }

    func testSuccessPreservesDirtyCheckoutAndProducesExactlyOneCommit() throws {
        let head = try git(["rev-parse", "HEAD"])
        try write("value.txt", "user staged\n")
        try git(["add", "value.txt"])
        try write("value.txt", "user unstaged\n")
        try write("personal.txt", "untracked\n")
        let status = try git(["status", "--porcelain"])
        let index = try git(["diff", "--cached"])
        var progress: [String] = []
        let record = try Runner(agent: .testAgent).run(at: checkout, harness: FakeHarness { cwd in
            let active = try XCTUnwrap(Runner(agent: .testAgent).status(at: self.checkout, dataDirectory: self.data))
            XCTAssertEqual(active.phase, "Harness")
            XCTAssertEqual(try String(contentsOf: cwd.appendingPathComponent("value.txt")), "before\n")
            try self.write("value.txt", "after\n", at: cwd)
            return self.success()
        }, dataDirectory: data, onProgress: { progress.append($0) })
        XCTAssertEqual(record.outcome, "committed", record.detail ?? "")
        XCTAssertNotNil(record.commit)
        XCTAssertEqual(try git(["rev-list", "--all", "--count"]), "2")
        XCTAssertEqual(try git(["rev-parse", "HEAD"]), head)
        XCTAssertEqual(try git(["status", "--porcelain"]), status)
        XCTAssertEqual(try git(["diff", "--cached"]), index)
        XCTAssertEqual(try String(contentsOf: checkout.appendingPathComponent("value.txt")), "user unstaged\n")
        XCTAssertEqual(try Runner(agent: .testAgent).status(at: checkout, dataDirectory: data)?.commit, record.commit)
        XCTAssertTrue(try git(["log", "-1", "--format=%s", record.branch]).hasPrefix("swift-agent: "))
        let phases = ["Setup", "Baseline", "Harness", "Review", "Verification", "Publication", "Cleanup"]
        XCTAssertEqual(progress, phases.map { $0 + "…" })
        let timings = record.phaseSeconds
        XCTAssertEqual(Set(timings.keys), Set(phases))
        XCTAssertTrue(timings.values.allSatisfy { $0 >= 0 && $0.isFinite })
        XCTAssertLessThanOrEqual(timings.values.reduce(0, +), try XCTUnwrap(record.finished).timeIntervalSince(record.started))
        XCTAssertNil(record.phase)
        XCTAssertEqual(try Runner(agent: .testAgent).status(at: checkout, dataDirectory: data)?.phaseSeconds, timings)
    }

    func testCommitIdentitiesSetAuthorAndCommitterWithoutChangingGitConfig() throws {
        let inheritedAuthor = ProcessInfo.processInfo.environment["GIT_AUTHOR_NAME"]
        for (index, identity) in ["Swift Agent <swift-agent@localhost>", "Custom Scout <custom@example.invalid>", "git"].enumerated() {
            var config = try Configuration.load(repository: Repository(at: checkout), agent: .testAgent)
            if index != 0 { config.commitIdentity = identity }
            config.branch = "identity-\(index)"
            let record = try Runner(agent: .testAgent).run(at: checkout, configuration: config, harness: FakeHarness { cwd in
                XCTAssertEqual(ProcessInfo.processInfo.environment["GIT_AUTHOR_NAME"], inheritedAuthor)
                try self.write("value.txt", "identity change\n", at: cwd)
                return self.success()
            }, dataDirectory: data)
            XCTAssertEqual(record.outcome, "committed", record.detail ?? "")
            let expected = identity == "git" ? "SwiftAgent Test <test@example.invalid>" : identity
            XCTAssertEqual(try git(["show", "-s", "--format=%an <%ae>|%cn <%ce>", try XCTUnwrap(record.commit)]), expected + "|" + expected)
            XCTAssertEqual(try git(["config", "user.name"]), "SwiftAgent Test")
            XCTAssertEqual(try git(["config", "user.email"]), "test@example.invalid")
        }
    }

    func testCommitIdentityConfigAndValidation() throws {
        try write("swift-agent.json", #"{"commitIdentity":"Config Scout <config@example.invalid>"}"#)
        let loaded = try Configuration.load(repository: Repository(at: checkout), agent: .testAgent)
        XCTAssertEqual(loaded.commitIdentity, "Config Scout <config@example.invalid>")
        XCTAssertEqual(try loaded.commitEnvironment()["GIT_AUTHOR_EMAIL"], "config@example.invalid")
        for identity in ["", "Scout", "<email>", "Scout <>", "Scout <a b>", "Scout <a> trailing", "Scout\nOther <email>", "Scout <a\0b>", "Scout <<email>>"] {
            var config = Configuration(agent: .testAgent)
            config.commitIdentity = identity
            XCTAssertThrowsError(try config.validate(), identity)
        }
        var config = Configuration(agent: .testAgent)
        config.commitIdentity = "git"
        XCTAssertEqual(try config.commitEnvironment(), [:])
    }

    func testBaselineAndVerificationCanBeConfiguredOrSkippedIndependently() throws {
        let before = "test $(cat value.txt) = before"
        let after = "test $(cat value.txt) = after"
        for (index, commands) in [([], [after]), ([before], []), ([], []), ([before], [after])].enumerated() {
            var config = Configuration(agent: .testAgent)
            config.branch = "checks-\(index)"
            config.baseline = commands.0
            config.verification = commands.1
            let record = try Runner(agent: .testAgent).run(at: checkout, configuration: config, harness: FakeHarness { cwd in
                try self.write("value.txt", "after\n", at: cwd)
                return self.success()
            }, dataDirectory: data)
            XCTAssertEqual(record.outcome, "committed", record.detail ?? "")
            XCTAssertEqual(record.baselineChecks.map(\.command), commands.0)
            XCTAssertEqual(record.checks.map(\.command), commands.1)
            XCTAssertTrue((record.baselineChecks + record.checks).allSatisfy { $0.status == 0 })
            XCTAssertEqual(record.phaseSeconds["Baseline"] == nil, commands.0.isEmpty)
            XCTAssertEqual(record.phaseSeconds["Verification"] == nil, commands.1.isEmpty)
        }
    }

    func testExplicitEmptyVerificationOverridesSwiftDetectionAndDefaultsBaselineToEmpty() throws {
        try write("Package.swift", "Not a Swift manifest; explicit [] must prevent swift test\n")
        try write("swift-agent.json", #"{"verification":[]}"#)
        try git(["add", "."])
        try git(["commit", "-m", "Configure skipped tests"])
        let record = try run { cwd in
            try self.write("value.txt", "after\n", at: cwd)
            return self.success()
        }
        XCTAssertEqual(record.outcome, "committed", record.detail ?? "")
        XCTAssertTrue(record.baselineChecks.isEmpty)
        XCTAssertTrue(record.checks.isEmpty)
    }

    func testSkippingCommandsKeepsProtectedPathGuards() throws {
        try write("swift-agent.json", #"{"baseline":[],"verification":[]}"#)
        try git(["commit", "-am", "Skip commands"])
        let record = try run { cwd in
            try self.write(".env", "fixture-not-a-secret", at: cwd)
            return self.success()
        }
        XCTAssertEqual(record.outcome, "rejected")

        XCTAssertEqual(try git(["rev-list", "--all", "--count"]), "2")
        XCTAssertEqual(try git(["branch", "--list", "swift-agent/project"]), "")
    }

    func testBaselineConfigRejectsEmptyCommandsButAcceptsEmptyArray() throws {
        try write("swift-agent.json", #"{"baseline":[],"verification":[]}"#)
        let config = try Configuration.load(repository: Repository(at: checkout), agent: .testAgent)
        XCTAssertEqual(config.baseline, [])
        XCTAssertEqual(config.verification, [])
        try write("swift-agent.json", #"{"baseline":["  "],"verification":[]}"#)
        XCTAssertThrowsError(try Configuration.load(repository: Repository(at: checkout), agent: .testAgent))
    }

    func testHarnessFailureDoesNotCommitAndCleansWorktree() throws {
        let record = try run { cwd in
            try self.write("value.txt", "after\n", at: cwd)
            return CommandResult(status: 1, output: "failure", timedOut: false)
        }
        XCTAssertEqual(record.outcome, "harness_failed")
        XCTAssertNotNil(record.phaseSeconds["Harness"])
        XCTAssertNotNil(record.phaseSeconds["Cleanup"])
        XCTAssertNil(record.phaseSeconds["Verification"])
        XCTAssertNil(record.phase)
        try assertNoCommit()
    }
    func testVerificationFailureDoesNotCommit() throws {
        let record = try run { cwd in
            try self.write("value.txt", "", at: cwd)
            return self.success()
        }
        XCTAssertEqual(record.outcome, "verification_failed")
        XCTAssertEqual(record.baselineChecks.first?.status, 0)
        XCTAssertNotEqual(record.checks.first?.status, 0)
        try assertNoCommit()
    }
    func testPreexistingFailureCanBeFixed() throws {
        try write("value.txt", "")
        try git(["commit", "-am", "Introduce failure"])
        let record = try run { cwd in
            try self.write("value.txt", "fixed\n", at: cwd)
            return self.success()
        }
        XCTAssertEqual(record.outcome, "committed", record.detail ?? "")
        XCTAssertNotEqual(record.baselineChecks.first?.status, 0)
        XCTAssertEqual(record.checks.first?.status, 0)
    }
    func testConfiguredProtectedGlobBlocksPublication() throws {
        try write("swift-agent.json", #"{"verification":["true"],"protectedPaths":["*.txt"]}"#)
        let record = try run { cwd in
            try self.write("value.txt", "changed", at: cwd)
            return self.success()
        }
        XCTAssertEqual(record.outcome, "rejected")
        XCTAssertTrue(record.detail?.contains("Configured protected path") == true)
        try assertNoCommit()
    }
    func testProtectedPathIsRejected() throws {
        let record = try run { cwd in
            try self.write(".env", "PASSWORD=private", at: cwd)
            return self.success()
        }
        XCTAssertEqual(record.outcome, "rejected")
        try assertNoCommit()
    }
    func testAgentCommitIsRejected() throws {
        let record = try run { cwd in
            try self.write("value.txt", "agent\n", at: cwd)
            try self.git(["commit", "-am", "Forbidden agent commit"], at: cwd)
            return self.success()
        }
        XCTAssertEqual(record.outcome, "rejected")
        try assertNoCommit()
    }
    func testTimeoutDoesNotCommit() throws {
        let record = try run { _ in CommandResult(status: 9, output: "", timedOut: true) }
        XCTAssertEqual(record.outcome, "timed_out")
        try assertNoCommit()
    }
    func testCancellationDoesNotCommit() throws {
        let record = try run { cwd in
            try self.write("value.txt", "after\n", at: cwd)
            Cancellation.requested = 1
            return self.success()
        }
        XCTAssertEqual(record.outcome, "cancelled")
        XCTAssertEqual(try git(["rev-list", "--all", "--count"]), "1")
        Cancellation.requested = 0
        let store = try StateStore(repository: Repository(at: checkout), dataDirectory: data)
        let partial = store.directory.appendingPathComponent("worktree-" + record.id).appendingPathComponent("value.txt")
        XCTAssertEqual(try String(contentsOf: partial, encoding: .utf8), "after\n")
    }
    func testMissingVerificationRefusesBeforeHarness() throws {
        try FileManager.default.removeItem(at: checkout.appendingPathComponent("swift-agent.json"))
        try git(["commit", "-am", "Remove configuration"])
        let record = try run { _ in XCTFail("Harness should not run"); return self.success() }
        XCTAssertEqual(record.outcome, "rejected")
        XCTAssertTrue(record.detail?.contains("No meaningful verification") == true)
    }
    func testSecondRunContinuesOnSwiftAgentBranch() throws {
        let first = try run { cwd in try self.write("value.txt", "first\n", at: cwd); return self.success() }
        let second = try run { cwd in
            XCTAssertEqual(try String(contentsOf: cwd.appendingPathComponent("value.txt")), "first\n")
            try self.write("value.txt", "second\n", at: cwd)
            return self.success()
        }
        XCTAssertEqual(second.outcome, "committed", second.detail ?? "")
        XCTAssertEqual(second.baseline, first.commit)
        XCTAssertEqual(try git(["rev-list", "--all", "--count"]), "3")
    }
    func testDivergenceRefusesToRewriteBranch() throws {
        let first = try run { cwd in try self.write("value.txt", "first\n", at: cwd); return self.success() }
        try write("other.txt", "development\n")
        try git(["add", "."])
        try git(["commit", "-m", "Development diverges"])
        XCTAssertThrowsError(try run { _ in XCTFail("Must not invoke harness"); return self.success() })
        XCTAssertEqual(try git(["rev-parse", first.branch]), first.commit)
    }
    func testRepositoryLockSpansDifferentStateRoots() throws {
        let repo = try Repository(at: checkout)
        let lock = try RepositoryLock(at: repo.commonDirectory.appendingPathComponent("swift-agent.lock"))
        defer { lock.release() }
        XCTAssertThrowsError(try run { _ in self.success() })
    }
    func testInterruptedRecordIsReconciledBeforeRestart() throws {
        let repo = try Repository(at: checkout)
        let store = try StateStore(repository: repo, dataDirectory: data)
        try store.save(Record(id: "interrupted-test", sessionID: "interrupted-session", harness: "fixture", repository: checkout.path, branch: "swift-agent/project", started: Date(), outcome: "running"))
        let record = try run { _ in self.success() }
        XCTAssertEqual(record.outcome, "no_candidate")
        let recovered = try JSONDecoder().decode(Record.self, from: Data(contentsOf: store.directory.appendingPathComponent("interrupted-test.json")))
        XCTAssertEqual(recovered.outcome, "interrupted")
    }
    func testBaselineMutationIsRejected() throws {
        var configuration = Configuration(agent: .testAgent)
        configuration.verification = ["printf generated >> value.txt"]
        let record = try Runner(agent: .testAgent).run(at: checkout, configuration: configuration,
            harness: FakeHarness { _ in self.success() }, dataDirectory: data)
        XCTAssertEqual(record.outcome, "rejected")
        try assertNoCommit()
    }
    func testUnknownConfigurationKeyIsRejected() throws {
        try write("swift-agent.json", "{\"verificaton\":[\"true\"]}")
        XCTAssertThrowsError(try Configuration.load(repository: Repository(at: checkout), agent: .testAgent))
    }

    func testExistingUnownedBranchIsNeverAdopted() throws {
        try git(["branch", "swift-agent/project"])
        XCTAssertThrowsError(try run { _ in XCTFail("Must not invoke harness"); return self.success() })
        XCTAssertEqual(try git(["rev-parse", "swift-agent/project"]), try git(["rev-parse", "HEAD"]))
    }
    func testForceAdoptsDivergedBranchAndPreservesItsHistory() throws {
        try git(["checkout", "-b", "existing"])
        try write("value.txt", "existing work\n")
        try git(["commit", "-am", "Existing branch work"])
        let tip = try git(["rev-parse", "HEAD"])
        try git(["checkout", "main"])
        try write("main.txt", "development work\n")
        try git(["add", "."])
        try git(["commit", "-m", "Diverge from target"])
        let head = try git(["rev-parse", "HEAD"])
        var config = try Configuration.load(repository: Repository(at: checkout), agent: .testAgent)
        config.branch = "existing"
        let record = try Runner(agent: .testAgent).run(at: checkout, configuration: config, harness: FakeHarness { cwd in
            XCTAssertEqual(try String(contentsOf: cwd.appendingPathComponent("value.txt")), "existing work\n")
            try self.write("value.txt", "improved\n", at: cwd)
            return self.success()
        }, dataDirectory: data, force: true)
        XCTAssertEqual(record.outcome, "committed", record.detail ?? "")
        XCTAssertEqual(record.baseline, tip)
        XCTAssertEqual(try git(["rev-parse", "existing^"]), tip)
        XCTAssertEqual(try git(["rev-parse", "HEAD"]), head)
        XCTAssertEqual(try git(["status", "--porcelain"]), "")
    }

    func testForceAdoptsExternallyChangedBranchWithoutChanges() throws {
        let first = try run { cwd in try self.write("value.txt", "first\n", at: cwd); return self.success() }
        try git(["update-ref", "refs/heads/" + first.branch, "HEAD"])
        XCTAssertThrowsError(try run { _ in XCTFail("Must require explicit adoption"); return self.success() })
        let record = try Runner(agent: .testAgent).run(at: checkout, harness: FakeHarness { _ in self.success() }, dataDirectory: data, force: true)
        XCTAssertEqual(record.outcome, "no_candidate")
        XCTAssertEqual(try run { _ in self.success() }.outcome, "no_candidate")
    }

    func testForceRejectsCheckedOutTargetIncludingLinkedWorktrees() throws {
        var config = try Configuration.load(repository: Repository(at: checkout), agent: .testAgent)
        config.branch = "main"
        let harness = FakeHarness { _ in XCTFail("Checked-out target invoked harness"); return self.success() }
        XCTAssertThrowsError(try Runner(agent: .testAgent).run(at: checkout, configuration: config, harness: harness, dataDirectory: data, force: true))
        let linked = temporary.appendingPathComponent("linked-force")
        try git(["worktree", "add", "-b", "existing", linked.path])
        config.branch = "existing"
        XCTAssertThrowsError(try Runner(agent: .testAgent).run(at: checkout, configuration: config, harness: harness, dataDirectory: data, force: true))
    }

    func testForceDoesNotOverwriteConcurrentBranchChanges() throws {
        try git(["branch", "existing"])
        let original = try git(["rev-parse", "HEAD"])
        var config = try Configuration.load(repository: Repository(at: checkout), agent: .testAgent)
        config.branch = "existing"
        let record = try Runner(agent: .testAgent).run(at: checkout, configuration: config, harness: FakeHarness { cwd in
            try self.write("value.txt", "improvement\n", at: cwd)
            // Simulate another process deleting the target while the harness runs.
            try self.git(["update-ref", "-d", "refs/heads/existing"])
            return self.success()
        }, dataDirectory: data, force: true)
        XCTAssertNotEqual(record.outcome, "committed")
        XCTAssertEqual(try git(["branch", "--list", "existing"]), "")
        XCTAssertEqual(try git(["rev-parse", "HEAD"]), original)
    }

    func testLinkedWorktreeUsesSameRepositoryIdentityAndLock() throws {
        let linked = temporary.appendingPathComponent("linked")
        try git(["worktree", "add", "--detach", linked.path])
        defer { _ = try? git(["worktree", "remove", "--force", linked.path]) }
        let main = try Repository(at: checkout)
        let other = try Repository(at: linked)
        XCTAssertEqual(main.commonDirectory, other.commonDirectory)
        let lock = try RepositoryLock(at: main.commonDirectory.appendingPathComponent("swift-agent.lock"))
        defer { lock.release() }
        XCTAssertThrowsError(try Runner(agent: .testAgent).run(at: linked, harness: FakeHarness { _ in self.success() }, dataDirectory: data))
    }
    func testDetachedDevelopmentCheckoutIsSupported() throws {
        try git(["checkout", "--detach"])
        let record = try run { cwd in try self.write("value.txt", "after\n", at: cwd); return self.success() }
        XCTAssertEqual(record.outcome, "committed", record.detail ?? "")
        XCTAssertEqual(try git(["rev-parse", "--abbrev-ref", "HEAD"]), "HEAD")
    }
    func testNonRepositoryIsRejected() throws {
        XCTAssertThrowsError(try Repository(at: temporary))
    }
    func testEmptyRepositoryIsRejected() throws {
        let empty = temporary.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try git(["init"], at: empty)
        XCTAssertThrowsError(try Repository(at: empty))
    }
    func testConfigurationRejectsBooleanLimits() throws {
        try write("swift-agent.json", "{\"timeoutSeconds\":true}")
        XCTAssertThrowsError(try Configuration.load(repository: Repository(at: checkout), agent: .testAgent))
    }
    func testNewSymlinkIsRejected() throws {
        let record = try run { cwd in
            try FileManager.default.createSymbolicLink(atPath: cwd.appendingPathComponent("link").path, withDestinationPath: "/etc/passwd")
            return self.success()
        }
        XCTAssertEqual(record.outcome, "rejected")
        try assertNoCommit()
    }
    func testFinalVerificationMutationIsRejected() throws {
        // The baseline is read-only; the changed content triggers a side effect in the final check.
        var config = Configuration(agent: .testAgent)
        config.verification = ["if grep -q after value.txt; then printf mutated >> value.txt; fi"]
        let record = try Runner(agent: .testAgent).run(at: checkout, configuration: config, harness: FakeHarness { cwd in
            try self.write("value.txt", "after\n", at: cwd)
            return self.success()
        }, dataDirectory: data)
        XCTAssertEqual(record.outcome, "rejected")
        try assertNoCommit()
    }

    func testProtectedRenameIsRejected() throws {
        try write(".env", "fixture-not-a-secret")
        try git(["add", ".env"])
        try git(["commit", "-m", "Add protected fixture"])
        let record = try run { cwd in
            try self.git(["mv", ".env", "renamed.txt"], at: cwd)
            return self.success()
        }
        XCTAssertEqual(record.outcome, "rejected")
    }

    func testHarnessLaunchErrorIsRecordedAsHarnessFailure() throws {
        let record = try run { _ in throw AgentError.message("fake harness disappeared") }
        XCTAssertEqual(record.outcome, "harness_failed")
        XCTAssertTrue(record.detail?.contains("disappeared") == true)
        try assertNoCommit()
    }
    func testCorruptHistoryBlocksUnsafeRestart() throws {
        let store = try StateStore(repository: Repository(at: checkout), dataDirectory: data)
        try Data("invalid JSON".utf8).write(to: store.directory.appendingPathComponent("latest.json"))
        XCTAssertThrowsError(try run { _ in XCTFail("Must not resume with corrupt history"); return self.success() })
    }

    func testFinalVerificationCannotRelyOnIgnoredHarnessArtifacts() throws {
        try write(".gitignore", "local-input.txt\n")
        try git(["add", ".gitignore"])
        try git(["commit", "-m", "Ignore local input"])
        let baseline = try git(["rev-parse", "HEAD"])

        var config = Configuration(agent: .testAgent)
        config.verification = ["test $(cat value.txt) = before || test -f local-input.txt"]
        let record = try Runner(agent: .testAgent).run(at: checkout, configuration: config, harness: FakeHarness { cwd in
            try self.write("value.txt", "after\n", at: cwd)
            try self.write("local-input.txt", "local input\n", at: cwd)
            return self.success()
        }, dataDirectory: data)

        XCTAssertEqual(record.outcome, "verification_failed", record.detail ?? "")
        XCTAssertEqual(try git(["rev-list", "--all", "-1"]), baseline)
        XCTAssertTrue(try git(["branch", "--list", record.branch]).isEmpty)
        XCTAssertEqual(try git(["worktree", "list", "--porcelain"]).components(separatedBy: "worktree ").count, 2)
    }

    func testTrackedBuildChangesAreRejected() throws {
        try FileManager.default.createDirectory(at: checkout.appendingPathComponent(".build"), withIntermediateDirectories: true)
        try write(".build/tracked.txt", "original\n")
        try git(["add", "-f", ".build/tracked.txt"])
        try git(["commit", "-m", "Track a build fixture"])
        let record = try run { cwd in
            try self.write(".build/tracked.txt", "changed\n", at: cwd)
            try self.write("value.txt", "after\n", at: cwd)
            return self.success()
        }
        XCTAssertEqual(record.outcome, "rejected")
        XCTAssertTrue(try git(["branch", "--list", record.branch]).isEmpty)
    }

    func testRefusesDataDirectoryInsideCheckoutBeforeWritingState() throws {
        let inside = checkout.appendingPathComponent("state")
        let alias = temporary.appendingPathComponent("checkout-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: checkout)
        for location in [inside, alias.appendingPathComponent("state")] {
            XCTAssertThrowsError(try Runner(agent: .testAgent).run(at: checkout, harness: FakeHarness { _ in
                XCTFail("Harness should not run")
                return self.success()
            }, dataDirectory: location))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: inside.path))
        XCTAssertTrue(try git(["status", "--porcelain"]).isEmpty)
    }

}
