//
//  CLILocator.swift
//  Shared
//
//  Locates the claude, agy and codex executables.
//

import Foundation
import os

private let logger = Logger(subsystem: "AIQuotaStudio", category: "CLILocator")

/// A menu bar app starts with a trimmed PATH (`/usr/bin:/bin:…`), so CLIs
/// installed via npm, nvm, volta or bun are not found by themselves.
/// First the usual directories are checked, then the user's login shell is asked:
/// it reads .zprofile/.zshrc and sees the same PATH as the terminal.
enum CLILocator {
    private static let lock = NSLock()
    private static var cache: [String: String] = [:]

    static func find(_ name: String) -> String? {
        lock.lock()
        let cached = cache[name]
        lock.unlock()
        if let cached, isExecutable(cached) {
            return cached
        }

        guard let found = knownLocation(name) ?? loginShellLookup(name) else {
            logger.error("\(name) not found in the usual directories or the login shell PATH")
            return nil
        }
        logger.debug("\(name) found: \(found)")

        lock.lock()
        cache[name] = found
        lock.unlock()
        return found
    }

    private static func knownLocation(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let directories = [
            "\(home)/.local/bin",
            "\(home)/.claude/local",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.volta/bin",
            "\(home)/.bun/bin"
        ]
        return directories
            .map { "\($0)/\(name)" }
            .first { isExecutable($0) }
    }

    /// Lookup in the PATH of an interactive login shell: this picks up both
    /// .zprofile and nvm, which is usually initialized in .zshrc. `whence -p` (zsh)
    /// and `type -P` (bash) look for an actual file, so aliases and wrapper
    /// functions like `agy() { … }` do not get in the way.
    private static func loginShellLookup(_ name: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        guard let output = CLIRunner.run(
            binary: shell,
            arguments: ["-l", "-i", "-c", "whence -p \(name) 2>/dev/null || type -P \(name) 2>/dev/null || command -v \(name)"],
            timeout: 10
        ) else {
            return nil
        }

        // rc files may print things — take the last line with an absolute path.
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("/") && isExecutable($0) }
    }

    private static func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}
