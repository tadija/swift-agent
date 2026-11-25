import XCTest
@testable import SwiftAgent


/// Real Swift build coverage, enabled explicitly in CI and before releases.
final class ExternalIntegrationTests: RepositoryTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["SWIFT_AGENT_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Run with SWIFT_AGENT_INTEGRATION_TESTS=1 to enable external integration tests")
        }
        try super.setUpWithError()
    }

    func testZeroConfigSwiftPackageDetectsAndRunsTests() throws {
        try FileManager.default.removeItem(at: checkout.appendingPathComponent("swift-agent.json"))
        try write("Package.swift", """
        // swift-tools-version: 6.4
        import PackageDescription
        let package = Package(name: "Fixture", targets: [
            .target(name: "Fixture"), .testTarget(name: "FixtureTests", dependencies: ["Fixture"])
        ])
        """)
        try FileManager.default.createDirectory(at: checkout.appendingPathComponent("Sources/Fixture"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: checkout.appendingPathComponent("Tests/FixtureTests"), withIntermediateDirectories: true)
        try write("Sources/Fixture/Value.swift", "public func value() -> Int { 1 }\n")
        try write("Tests/FixtureTests/ValueTests.swift", """
        import XCTest
        @testable import Fixture
        final class ValueTests: XCTestCase {
            func testValue() { XCTAssertEqual(Fixture.value(), 2) }
        }
        """)
        try git(["add", "--all"])
        try git(["commit", "-m", "Swift package with failing test"])
        let record = try run { cwd in
            try self.write("Sources/Fixture/Value.swift", "public func value() -> Int { 2 }\n", at: cwd)
            return self.success()
        }
        XCTAssertEqual(record.outcome, "committed", (record.detail ?? "") + "\n" + (record.checks.first?.output ?? ""))
        XCTAssertNotEqual(record.baselineChecks.first?.status, 0)
        XCTAssertEqual(record.checks.first?.status, 0)
        XCTAssertEqual(record.paths, ["Sources/Fixture/Value.swift"])
    }

}
