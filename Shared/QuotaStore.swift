//
//  QuotaStore.swift
//  Shared
//
//  Quota cache storage in the shared App Group container.
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
    /// From the AIQuotaAppGroup Info.plist key, filled from APP_GROUP_ID in Config/Base.xcconfig.
    nonisolated static let appGroupID = Bundle.main.object(forInfoDictionaryKey: "AIQuotaAppGroup") as? String ?? ""
    /// Subdirectory inside the container, to keep its root clean.
    static let directoryName = "AIQuota"
    /// Past this threshold data is considered stale and flagged in the UI.
    static let staleThreshold: TimeInterval = 6 * 60 * 60

    /// The App Group directory is the only place both the app and the
    /// sandboxed widget can see. nil if the target lacks the entitlement
    /// `com.apple.security.application-groups`.
    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(directoryName, isDirectory: true)
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

    /// Errors go to the App Group so the widget sees them too, not just the menu.
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
