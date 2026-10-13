//
//  QuotaBridge.swift
//  AI Quota Studio
//
//  Background scheduler that runs the quota collectors and publishes results.
//

import AppKit
import CoreGraphics
import Foundation
import WidgetKit
import os

private let logger = Logger(subsystem: "AIQuotaStudio", category: "QuotaBridge")

extension Notification.Name {
    static let quotaDidUpdate = Notification.Name("AIQuotaDidUpdateNotification")
}

final class QuotaBridge {
    static let shared = QuotaBridge()

    private var timer: Timer?
    private let pollInterval: TimeInterval = 30
    private var isCollecting = false

    /// The system is going to sleep — no CLI runs until it fully wakes up.
    private var isSystemAsleep = false
    /// Pause after wake-up: the network needs time to come back, otherwise
    /// the CLI hits its request timeout.
    private let wakeGracePeriod: TimeInterval = 20

    private var lastFetch: [QuotaProvider: Date] = [:]

    func start() {
        observePowerEvents()
        runCollector(force: true)

        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        runCollector()
    }

    // MARK: - Sleep and wake

    /// A closed-lid laptop wakes into DarkWake for a few seconds and goes back
    /// to sleep. An `agy` started then gets frozen mid TLS handshake: half an hour
    /// later it sees expired deadlines, decides it is signed out and opens a
    /// Google sign-in tab. So CLIs only run while the display is awake, and
    /// running ones are killed before sleep.
    private func observePowerEvents() {
        let center = NSWorkspace.shared.notificationCenter

        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isSystemAsleep = true
            CLIRunner.terminateAll()
        }

        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.isSystemAsleep = false
            DispatchQueue.main.asyncAfter(deadline: .now() + self.wakeGracePeriod) { [weak self] in
                self?.runCollector()
            }
        }
    }

    /// Whether a CLI may run now. `force` is only for user actions, when the
    /// machine is certainly awake.
    private func canCollect(force: Bool) -> Bool {
        if force { return true }
        if isSystemAsleep { return false }
        if CGDisplayIsAsleep(CGMainDisplayID()) != 0 {
            logger.debug("Skipping poll: display is asleep")
            return false
        }
        return true
    }

    /// Runs the due collectors on a background queue.
    func runCollector(force: Bool = false) {
        guard canCollect(force: force) else { return }
        guard !isCollecting else { return }
        isCollecting = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            defer {
                DispatchQueue.main.async {
                    self.isCollecting = false
                }
            }

            let interval = Double(QuotaConfig.refreshIntervalSeconds)
            let now = Date()

            var didRun = false
            for provider in QuotaProvider.allCases {
                if !force, let last = self.lastFetch[provider], now.timeIntervalSince(last) < interval {
                    continue
                }
                let result = Self.fetch(provider)
                switch result {
                case .success(let snapshot):
                    QuotaStore.save(snapshot, provider: provider)
                    QuotaStore.saveError(nil, provider: provider)
                case .failure(let error):
                    logger.error("\(provider.rawValue): \(error.message)")
                    QuotaStore.saveError(error, provider: provider)
                }
                // Failures wait for the interval too: otherwise a missing CLI would
                // spawn a login shell, and a broken agy its OAuth, every 30 seconds.
                self.lastFetch[provider] = Date()
                didRun = true
            }

            guard didRun else { return }
            DispatchQueue.main.async {
                WidgetCenter.shared.reloadAllTimelines()
                NotificationCenter.default.post(name: .quotaDidUpdate, object: nil)
            }
        }
    }

    private static func fetch(_ provider: QuotaProvider) -> Result<QuotaSnapshot, CollectorError> {
        switch provider {
        case .claude: return ClaudeCollector.fetch()
        case .antigravity: return AntigravityCollector.fetch()
        case .codex: return CodexCollector.fetch()
        }
    }
}
