//
//  CodexCollector.swift
//  Shared
//
//  Codex quota collector via `codex app-server`.
//

import Foundation
import os

private let logger = Logger(subsystem: "AIQuotaStudio", category: "CodexCollector")

/// Codex has no `/usage` in non-interactive mode, but `codex app-server`
/// (JSON-RPC over stdio) answers `account/rateLimits/read` with live limits
/// straight from the server — without running a model or spending messages.
///
/// The set of windows depends on the plan: Plus/Pro get 5 hours (primary) and
/// a week (secondary), the free plan gets one 30-day window and `secondary: null`.
/// So windows are sorted by duration rather than by primary/secondary.
enum CodexCollector {
    private static let requestID = 2

    static func fetch(timeout: TimeInterval = 20) -> Result<QuotaSnapshot, CollectorError> {
        guard let binary = CLILocator.find("codex") else {
            return .failure(.notInstalled("codex"))
        }
        logger.debug("Running codex app-server at \(binary)")

        let requests = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"ai-quota-studio","title":"AI Quota Studio","version":"1.0"}}}"#,
            #"{"jsonrpc":"2.0","method":"initialized"}"#,
            #"{"jsonrpc":"2.0","id":\#(requestID),"method":"account/rateLimits/read"}"#
        ]

        guard let output = CLIRunner.run(
            binary: binary,
            arguments: ["app-server"],
            input: requests.joined(separator: "\n") + "\n",
            timeout: timeout,
            until: { response(in: $0) != nil }
        ) else {
            return .failure(.noResponse("codex"))
        }
        guard let snapshot = parse(output) else {
            return .failure(.unparsable("codex"))
        }
        return .success(snapshot)
    }

    static func parse(_ output: String) -> QuotaSnapshot? {
        guard let response = response(in: output),
              let result = response["result"] as? [String: Any],
              let limits = result["rateLimits"] as? [String: Any] else {
            return nil
        }

        var windows: [String: QuotaWindow] = [:]
        for name in ["primary", "secondary"] {
            guard let window = limits[name] as? [String: Any],
                  let used = (window["usedPercent"] as? NSNumber)?.doubleValue,
                  let minutes = (window["windowDurationMins"] as? NSNumber)?.intValue else { continue }

            let resetsAt = (window["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            windows[key(forMinutes: minutes)] = QuotaWindow(
                usedPercentage: min(max(used, 0), 100),
                resetsAt: resetsAt
            )
        }

        guard !windows.isEmpty else { return nil }
        return QuotaSnapshot(updatedAt: Date(), source: "codex-app-server", windows: windows)
    }

    /// 300 min → 5 hours, 10080 → week, 43200 → month. Unusual durations go
    /// to the nearest longer window.
    private static func key(forMinutes minutes: Int) -> String {
        switch minutes {
        case ..<(24 * 60): return QuotaSnapshot.fiveHourKey
        case ..<(14 * 24 * 60): return QuotaSnapshot.sevenDayKey
        default: return QuotaSnapshot.thirtyDayKey
        }
    }

    /// Our response among the JSON-RPC lines: the server sends notifications too.
    private static func response(in output: String) -> [String: Any]? {
        for line in output.split(separator: "\n") {
            guard line.contains("\"id\""),
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  (object["id"] as? NSNumber)?.intValue == requestID else { continue }
            return object
        }
        return nil
    }
}
