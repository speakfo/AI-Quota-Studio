//
//  QuotaStore.swift
//  Shared
//
//  Quota cache storage shared by the app and the widget.
//

import Foundation

enum QuotaProvider: String, CaseIterable {
    case claude
    case antigravity
    case codex

    var fileName: String { "\(rawValue)-quota.json" }
    /// Error of the last collection; no file means it succeeded.
    var errorFileName: String { "\(rawValue)-error.json" }
}

/// What could be read from the cache when the timeline was built.
enum QuotaLoadResult {
    case ok(QuotaSnapshot)
    /// The file exists but has not been updated for a while — the collector is not running.
    case stale(QuotaSnapshot)
    /// No file at all — the app has never collected data.
    case missing

    var snapshot: QuotaSnapshot? {
        switch self {
        case .ok(let s), .stale(let s): return s
        case .missing: return nil
        }
    }

    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}

enum QuotaStore {
    /// Subdirectory of Application Support shared by the app and the widget.
    static let directoryName = "AIQuota"
    /// Past this threshold data is considered stale and flagged in the UI.
    static let staleThreshold: TimeInterval = 6 * 60 * 60

    /// `~/Library/Application Support/AIQuota`. The app is not sandboxed and
    /// writes here; the sandboxed widget reads it through the
    /// `temporary-exception.files.home-relative-path.read-only` entitlement.
    /// An App Group would need a Team ID, which an ad-hoc signed build lacks:
    /// macOS silently denies access to the group container.
    nonisolated static let directory: URL? = realHomeDirectory?
        .appendingPathComponent("Library/Application Support", isDirectory: true)
        .appendingPathComponent(directoryName, isDirectory: true)

    /// The user's home even inside the sandbox, where `NSHomeDirectory()`
    /// points to the widget's container.
    nonisolated private static var realHomeDirectory: URL? {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
    }

    static func load(_ provider: QuotaProvider, now: Date = Date()) -> QuotaLoadResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        guard let url = directory?.appendingPathComponent(provider.fileName),
              let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(QuotaSnapshot.self, from: data) else {
            return .missing
        }
        return snapshot.age(now: now) > staleThreshold ? .stale(snapshot) : .ok(snapshot)
    }

    static func save(_ snapshot: QuotaSnapshot, provider: QuotaProvider) {
        write(snapshot, to: provider.fileName)
    }

    /// Errors go to the shared directory so the widget sees them too, not just the menu.
    static func saveError(_ error: CollectorError?, provider: QuotaProvider) {
        if let error {
            write(error, to: provider.errorFileName)
        } else if let url = directory?.appendingPathComponent(provider.errorFileName) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func loadError(_ provider: QuotaProvider) -> CollectorError? {
        guard let url = directory?.appendingPathComponent(provider.errorFileName),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CollectorError.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to fileName: String) {
        guard let directory else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }
}
