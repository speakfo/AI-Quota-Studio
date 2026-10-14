//
//  CLIRunner.swift
//  Shared
//
//  Single entry point for running external CLIs (claude, agy, codex) from the background app.
//

import Foundation
import os

private let logger = Logger(subsystem: "AIQuotaStudio", category: "CLIRunner")

/// Safe launching of the quota-collecting CLIs.
///
/// Solves three problems that made background `agy` polls open a Google
/// sign-in tab in the browser:
///
/// 1. **The CLI must not be able to open a browser.** When silent auth fails,
///    `agy` falls back to interactive OAuth and calls `open <url>`. A stub
///    `open` is put first in `PATH`, so a background process physically
///    cannot open a tab.
/// 2. **Wall-clock timeouts.** `DispatchTime` stops while the system sleeps,
///    so a hung process lived for tens of minutes instead of 30 seconds.
/// 3. **Hard termination.** SIGTERM, then SIGKILL if that did not help. Running
///    processes are registered so they can be killed before sleep.
enum CLIRunner {

    // MARK: - Browser stub

    private static let shimDirectoryName = "AIQuotaNoBrowser"

    /// Directory with the stub `open`, placed first in `PATH`.
    private static let shimDirectory: URL? = {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(shimDirectoryName, isDirectory: true)
        let script = directory.appendingPathComponent("open")
        let body = """
        #!/bin/sh
        # AI Quota Studio stub: the background quota collector must not open
        # a browser. Without it, agy opened a Google sign-in tab whenever its
        # silent auth failed.
        exit 0
        """

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            return directory
        } catch {
            logger.error("Failed to create the open stub: \(error.localizedDescription)")
            return nil
        }
    }()

    // MARK: - Registry of running processes

    private static let lock = NSLock()
    private static var active: [Process] = []

    private static func register(_ process: Process) {
        lock.lock()
        active.append(process)
        lock.unlock()
    }

    private static func unregister(_ process: Process) {
        lock.lock()
        active.removeAll { $0 === process }
        lock.unlock()
    }

    /// Kills all running CLIs. Called before the system sleeps: a process that
    /// survives sleep loses its connections and internal deadlines, after which
    /// `agy` decides it is signed out.
    static func terminateAll() {
        lock.lock()
        let processes = active
        lock.unlock()

        for process in processes where process.isRunning {
            logger.notice("Killing CLI before system sleep: pid \(process.processIdentifier)")
            process.terminate()
        }
    }

    // MARK: - Running

    /// Runs a CLI and returns its stdout.
    /// - Parameters:
    ///   - input: what to write to stdin. stdin stays open until the end — servers
    ///     like `codex app-server` exit on EOF before they get to answer.
    ///   - timeout: wall-clock limit; after it the process is killed.
    ///   - isComplete: for long-lived processes: once stdout satisfies it, the
    ///     process is killed and the collected output is returned.
    /// An empty directory of our own to run CLIs in.
    private static let workingDirectory: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AIQuotaCLI", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func run(
        binary: String,
        arguments: [String],
        input: String? = nil,
        timeout: TimeInterval,
        until isComplete: ((String) -> Bool)? = nil
    ) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        // Not the home directory: `claude` looks around its working directory, and
        // from `~` it touches ~/Documents, which pops up a privacy prompt.
        process.currentDirectoryURL = workingDirectory
        process.environment = environment(home: home.path, binary: binary)

        let stdin = input.map { _ in Pipe() }
        process.standardInput = stdin ?? FileHandle.nullDevice
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        let output = OutputBuffer()
        let finished = DispatchSemaphore(value: 0)
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                if output.markDone() { finished.signal() }
            } else if output.append(chunk, isComplete: isComplete) {
                finished.signal()
            }
        }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            logger.error("Failed to launch \(binary): \(error.localizedDescription)")
            return nil
        }

        register(process)
        defer {
            unregister(process)
            stdout.fileHandleForReading.readabilityHandler = nil
            try? stdin?.fileHandleForWriting.close()
        }

        if let input, let stdin {
            try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
        }

        // wallTimeout on purpose: plain DispatchTime does not advance while the system sleeps.
        let timedOut = finished.wait(wallTimeout: .now() + timeout) == .timedOut
        if timedOut {
            logger.warning("\(binary) exceeded \(timeout, format: .fixed(precision: 0)) s — killing it")
        }
        // A closed stdout usually means the process is exiting; give it a couple
        // of seconds to finish on its own. Long-lived ones (isComplete) are killed at once.
        if !timedOut && isComplete == nil {
            waitForExit(process, seconds: 2)
        }
        if process.isRunning {
            terminate(process, binary: binary)
        }
        if timedOut { return nil }

        guard let text = String(data: output.data, encoding: .utf8) else {
            logger.error("Could not decode \(binary) stdout as UTF-8")
            return nil
        }
        return text
    }

    /// SIGTERM, then SIGKILL if the process is still alive after 3 seconds.
    private static func terminate(_ process: Process, binary: String) {
        stop(process, hard: false)
        waitForExit(process, seconds: 3)
        if process.isRunning {
            logger.warning("\(binary) ignored SIGTERM — sending SIGKILL")
            stop(process, hard: true)
        }
    }

    private static func environment(home: String, binary: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        var parts: [String] = []
        // The stub goes first to shadow the system /usr/bin/open.
        if let shim = shimDirectory?.path {
            parts.append(shim)
        }
        // The CLI's own directory: npm installs via nvm keep node next to it,
        // and a `#!/usr/bin/env node` script cannot start without it.
        parts.append(URL(fileURLWithPath: binary).deletingLastPathComponent().path)
        parts += ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        if let existing = env["PATH"], !existing.isEmpty {
            parts.append(existing)
        }

        env["PATH"] = parts.joined(separator: ":")
        env["HOME"] = home
        // Some CLIs open links via $BROWSER, bypassing `open`.
        if let shim = shimDirectory?.appendingPathComponent("open").path {
            env["BROWSER"] = shim
        }
        return env
    }

    private static func waitForExit(_ process: Process, seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
    }

    private static func stop(_ process: Process, hard: Bool) {
        guard process.isRunning else { return }
        if hard {
            kill(process.processIdentifier, SIGKILL)
        } else {
            process.terminate()
        }
    }
}

/// stdout accumulator written by readabilityHandler from another thread.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var done = false

    var data: Data {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }

    /// true exactly once, when the output becomes "complete".
    func append(_ chunk: Data, isComplete: ((String) -> Bool)?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        buffer.append(chunk)
        guard !done, let isComplete, isComplete(String(decoding: buffer, as: UTF8.self)) else { return false }
        done = true
        return true
    }

    /// true if the output was never deemed complete before EOF.
    func markDone() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return false }
        done = true
        return true
    }
}

// MARK: - Collector errors

/// Why a collector returned no data — shown in the menu and the widget
/// instead of an empty card.
enum CollectorError: Error, Equatable, Codable {
    /// The CLI was found neither in the usual directories nor in the login shell PATH.
    case notInstalled(String)
    /// The CLI failed to start or did not finish within the timeout.
    case noResponse(String)
    /// The CLI answered, but there are no quotas in the output: usually not signed in.
    case unparsable(String)

    /// Localized; used in logs too, where the language does not matter.
    nonisolated var message: String {
        switch self {
        case .notInstalled(let cli): return L10n.tr("%@ not found — install the CLI or add it to PATH", cli)
        case .noResponse(let cli): return L10n.tr("%@ did not respond in time", cli)
        case .unparsable(let cli): return L10n.tr("%@ returned no quotas — sign in to %@", cli, cli)
        }
    }

    /// Short version for the widget header, which fits only a couple of words.
    var shortMessage: String {
        switch self {
        case .notInstalled(let cli): return L10n.tr("%@ not found", cli)
        case .noResponse(let cli): return L10n.tr("%@ not responding", cli)
        case .unparsable(let cli): return L10n.tr("sign in to %@", cli)
        }
    }
}
