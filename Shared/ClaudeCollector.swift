//
//  ClaudeCollector.swift
//  Shared
//
//  Claude Code quota collector.
//

import Foundation
import os

private let logger = Logger(subsystem: "AIQuotaStudio", category: "ClaudeCollector")

enum ClaudeCollector {
    static func fetch(timeout: TimeInterval = 20) -> Result<QuotaSnapshot, CollectorError> {
        guard let binary = CLILocator.find("claude") else {
            return .failure(.notInstalled("claude"))
        }
        logger.debug("Running claude at \(binary)")

        guard let rawString = CLIRunner.run(
            binary: binary,
            arguments: ["-p", "/usage", "--output-format", "json"],
            timeout: timeout
        ) else {
            return .failure(.noResponse("claude"))
        }
        guard let snapshot = parse(rawString) else {
            return .failure(.unparsable("claude"))
        }
        return .success(snapshot)
    }

    static func parse(_ output: String) -> QuotaSnapshot? {
        var text = output

        // Extract JSON substring if wrapped in warnings/logs
        if let start = output.firstIndex(of: "{"),
           let end = output.lastIndex(of: "}"),
           start <= end {
            let jsonSub = String(output[start...end])
            if let data = jsonSub.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? String {
                text = result
            }
        }

        let sessionPattern = #"Current session:\s*(\d+(?:\.\d+)?)%\s*used(?:\s*·\s*resets\s+([A-Za-z]+\s+\d+\s+at\s+\d+(?::\d+)?(?:am|pm))\s*\(([^)]+)\))?"#
        let weekPattern = #"Current week(?:\s*\([^)]*\))?:\s*(\d+(?:\.\d+)?)%\s*used(?:\s*·\s*resets\s+([A-Za-z]+\s+\d+\s+at\s+\d+(?::\d+)?(?:am|pm))\s*\(([^)]+)\))?"#

        var windows: [String: QuotaWindow] = [:]

        if let mSess = firstMatch(pattern: sessionPattern, in: text),
           let usedStr = mSess[1], let used = Double(usedStr) {
            let dateStr = mSess.count > 2 ? mSess[2] : nil
            let tzStr = mSess.count > 3 ? mSess[3] : nil
            windows[QuotaSnapshot.fiveHourKey] = QuotaWindow(
                usedPercentage: used,
                resetsAt: parseDate(dateStr: dateStr, tzStr: tzStr)
            )
        }

        if let mWeek = firstMatch(pattern: weekPattern, in: text),
           let usedStr = mWeek[1], let used = Double(usedStr) {
            let dateStr = mWeek.count > 2 ? mWeek[2] : nil
            let tzStr = mWeek.count > 3 ? mWeek[3] : nil
            windows[QuotaSnapshot.sevenDayKey] = QuotaWindow(
                usedPercentage: used,
                resetsAt: parseDate(dateStr: dateStr, tzStr: tzStr)
            )
        }

        guard !windows.isEmpty else { return nil }
        return QuotaSnapshot(updatedAt: Date(), source: "claude-usage", windows: windows)
    }

    static func parseDate(dateStr: String?, tzStr: String?) -> Date? {
        guard let dateStr = dateStr, let tzStr = tzStr,
              let tz = TimeZone(identifier: tzStr) else { return nil }

        var clean = dateStr.replacingOccurrences(of: " at ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        // Only normalize round hours like "3pm" or "11am" (without colon) to "3:00pm", "11:00am"
        let range = NSRange(clean.startIndex..., in: clean)
        if let regex = try? NSRegularExpression(pattern: #"(?<!:)\b(\d{1,2})(am|pm)\b"#, options: .caseInsensitive) {
            clean = regex.stringByReplacingMatches(in: clean, range: range, withTemplate: "$1:00$2")
        }

        let now = Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let fullStr = "\(clean) \(year)"

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = tz

        // Try standard format with minutes (e.g. "Aug 28 1:39pm 2026")
        formatter.dateFormat = "MMM d h:mma yyyy"
        if var date = formatter.date(from: fullStr) {
            if date < now.addingTimeInterval(-3600) {
                if let nextYear = calendar.date(byAdding: .year, value: 1, to: date) {
                    date = nextYear
                }
            }
            return date
        }

        // Fallback format with spaces or without minutes
        let fallbackFormats = [
            "MMM d h:mm a yyyy",
            "MMM d ha yyyy",
            "MMM d h a yyyy"
        ]
        for fmt in fallbackFormats {
            formatter.dateFormat = fmt
            if var date = formatter.date(from: fullStr) {
                if date < now.addingTimeInterval(-3600) {
                    if let nextYear = calendar.date(byAdding: .year, value: 1, to: date) {
                        date = nextYear
                    }
                }
                return date
            }
        }

        return nil
    }

    private static func firstMatch(pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsString = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) else { return nil }

        var results: [String?] = []
        for i in 0..<match.numberOfRanges {
            let r = match.range(at: i)
            if r.location != NSNotFound {
                results.append(nsString.substring(with: r))
            } else {
                results.append(nil)
            }
        }
        return results
    }
}
