import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Shared by final diff validation and the native agent's file-editing tools.
enum ChangePolicy {
    static func validate(path: String, protectedPaths: [String]) throws {
        let blocked = [".env", ".git", ".github", "secrets", "credentials", "package.resolved", "package-lock.json", "yarn.lock", "package.swift", "makefile", "agents.md", "claude.md"]
        guard !protectedPaths.contains(where: { fnmatch($0, path, 0) == 0 }) else {
            throw AgentError.message("Configured protected path: " + path)
        }
        let parts = path.lowercased().split(separator: "/").map(String.init)
        guard !parts.contains(where: { part in blocked.contains(part) || part.hasPrefix(".env.") || part.hasSuffix(".pem") || part.hasSuffix(".key") || [".build", "node_modules", "dist", "build"].contains(part) }) else {
            throw AgentError.message("Protected or generated path: \(path)")
        }
    }
}
