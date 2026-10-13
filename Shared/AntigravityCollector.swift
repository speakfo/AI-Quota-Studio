//
//  AntigravityCollector.swift
//  Shared
//
//  Antigravity (AGY) quota collector.
//

import Foundation
import os

private let logger = Logger(subsystem: "AIQuotaStudio", category: "AntigravityCollector")

enum AntigravityCollector {
    static func fetch(timeout: TimeInterval = 30) -> Result<QuotaSnapshot, CollectorError> {
        guard let binary = CLILocator.find("agy") else {
            return .failure(.notInstalled("agy"))
        }
        logger.debug("Running agy at \(binary)")

        guard let rawString = CLIRunner.run(
            binary: binary,
            arguments: ["--print-timeout", "30s", "-p", "/usage"],
            timeout: timeout
        ) else {
            return .failure(.noResponse("agy"))
        }
        guard let snapshot = parse(rawString) else {
            return .failure(.unparsable("agy"))
        }
        return .success(snapshot)
    }

    static func parse(_ output: String) -> QuotaSnapshot? {
        var text = output

        // 1. Try to check if output is JSON or wrapped JSON
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}"),
           start <= end {
            let jsonSub = String(text[start...end])
            if let data = jsonSub.data(using: .utf8),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // If agy returned structured json with command.data.groups
                if let command = root["command"] as? [String: Any],
                   let cmdData = command["data"] as? [String: Any],
                   let groups = cmdData["groups"] as? [[String: Any]],
                   let snapshot = parseJsonGroups(groups) {
                    return snapshot
                }

                // If it returned { "response": "..." }
                if let resp = root["response"] as? String {
                    text = resp
                }
            }
        }

        // 2. Parse TSV lines
        var windows: [String: QuotaWindow] = [:]
        for line in text.components(separatedBy: .newlines) {
            let cols = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard cols.count >= 3 else { continue }

            // The header line and anything that is not a percentage are filtered out here.
            let remainingStr = cols[2].replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
            guard let remaining = Double(remainingStr),
                  let key = windowKey(family: cols[0], window: cols[1]) else { continue }

            windows[key] = QuotaWindow(
                usedPercentage: usedPercent(remainingFraction: remaining / 100),
                resetsAt: cols.count >= 4 ? parseDate(cols[3]) : nil
            )
        }

        guard !windows.isEmpty else { return nil }
        return QuotaSnapshot(updatedAt: Date(), source: "antigravity-usage", windows: windows)
    }

    private static func parseJsonGroups(_ groups: [[String: Any]]) -> QuotaSnapshot? {
        var windows: [String: QuotaWindow] = [:]

        for group in groups {
            guard let name = group["name"] as? String,
                  let buckets = group["buckets"] as? [[String: Any]] else { continue }

            for bucket in buckets {
                guard let window = bucket["window"] as? String,
                      let remainingFraction = bucket["remaining_fraction"] as? Double,
                      let key = windowKey(family: name, window: window) else { continue }

                windows[key] = QuotaWindow(
                    usedPercentage: usedPercent(remainingFraction: remainingFraction),
                    resetsAt: (bucket["reset_time"] as? String).flatMap { parseDate($0) }
                )
            }
        }

        guard !windows.isEmpty else { return nil }
        return QuotaSnapshot(updatedAt: Date(), source: "antigravity-usage", windows: windows)
    }

    // MARK: - Shared parsing rules

    /// Key in `QuotaSnapshot.windows`: Gemini models go to the main windows,
    /// Claude/GPT to the `_claude_gpt` ones. nil — skip the line.
    private static func windowKey(family: String, window: String) -> String? {
        let suffix: String
        if family.localizedCaseInsensitiveContains("gemini") {
            suffix = ""
        } else if ["claude", "gpt", "opus", "3p"].contains(where: family.localizedCaseInsensitiveContains) {
            suffix = "_claude_gpt"
        } else {
            return nil
        }

        let base: String
        if window.localizedCaseInsensitiveContains("five") || window.localizedCaseInsensitiveContains("5h") {
            base = QuotaSnapshot.fiveHourKey
        } else if window.localizedCaseInsensitiveContains("week") || window.localizedCaseInsensitiveContains("7d") {
            base = QuotaSnapshot.sevenDayKey
        } else {
            return nil
        }
        return base + suffix
    }

    private static func usedPercent(remainingFraction: Double) -> Double {
        let used = ((1 - remainingFraction) * 100 * 100).rounded() / 100
        return min(max(used, 0), 100)
    }

    private static func parseDate(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
