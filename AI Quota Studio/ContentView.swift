//
//  ContentView.swift
//  AI Quota Studio
//

import AppKit
import ServiceManagement
import SwiftUI
import WidgetKit

// MARK: - Menu bar popover

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    /// Re-renders the popover when the language changes in Settings.
    @AppStorage(L10n.languageKey, store: L10n.defaults) private var language = AppLanguage.english.rawValue

    @State private var claude = QuotaStore.load(.claude)
    @State private var claudeError = QuotaStore.loadError(.claude)
    @State private var antigravity = QuotaStore.load(.antigravity)
    @State private var antigravityError = QuotaStore.loadError(.antigravity)
    @State private var codex = QuotaStore.load(.codex)
    @State private var codexError = QuotaStore.loadError(.codex)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.medium")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundColor(.orange)
                Text(verbatim: "AI Quota Studio")
                    .font(.headline)
                Spacer()
            }

            VStack(spacing: 8) {
                if !Self.isAbsent(claude, claudeError) {
                    MenuBarProviderCard(title: "Claude Code", result: claude, error: claudeError)
                }
                if !Self.isAbsent(antigravity, antigravityError) {
                    MenuBarAntigravityCard(result: antigravity, error: antigravityError)
                }
                if !Self.isAbsent(codex, codexError) {
                    // On the free plan Codex has only a monthly window.
                    MenuBarProviderCard(title: "Codex", result: codex, error: codexError) { $0.codexRows }
                }
                if Self.isAbsent(claude, claudeError) && Self.isAbsent(antigravity, antigravityError)
                    && Self.isAbsent(codex, codexError) {
                    Label(L10n.tr("Neither claude, agy nor codex was found. Install at least one CLI and sign in to it."),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            HStack {
                Button {
                    openSettings()
                } label: {
                    Label(L10n.tr("Settings…"), systemImage: "gearshape")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text(L10n.tr("Quit"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 320)
        // Child views are cached by their inputs; a new identity redraws them in the new language.
        .id(language)
        .onAppear {
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quotaDidUpdate)) { _ in
            refreshState()
        }
    }

    private func reload() {
        QuotaBridge.shared.runCollector()
        refreshState()
    }

    private func refreshState() {
        claude = QuotaStore.load(.claude)
        claudeError = QuotaStore.loadError(.claude)
        antigravity = QuotaStore.load(.antigravity)
        antigravityError = QuotaStore.loadError(.antigravity)
        codex = QuotaStore.load(.codex)
        codexError = QuotaStore.loadError(.codex)
    }

    /// The CLI is not installed and there has never been data for it — hide the card.
    private static func isAbsent(_ result: QuotaLoadResult, _ error: CollectorError?) -> Bool {
        guard case .missing = result, case .notInstalled = error else { return false }
        return true
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Provider card

private struct MenuBarProviderCard: View {
    let title: String
    let result: QuotaLoadResult
    let error: CollectorError?
    /// Which windows to show. Defaults to 5 hours and week, even when empty.
    var rows: (QuotaSnapshot) -> [QuotaRow] = { $0.defaultRows }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: title, result: result)

            if let snapshot = result.snapshot {
                let items = rows(snapshot)
                HStack(spacing: 12) {
                    ForEach(items.indices, id: \.self) { index in
                        if index > 0 {
                            Divider()
                                .frame(height: 28)
                        }
                        QuotaMetricColumn(
                            label: items[index].title,
                            window: items[index].window,
                            missingNote: items[index].missingNote
                        )
                    }
                }
            } else if error == nil {
                NoDataYetLabel()
            }

            CollectorErrorLabel(error: error)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }
}

// MARK: - Antigravity card

private struct MenuBarAntigravityCard: View {
    let result: QuotaLoadResult
    let error: CollectorError?

    private static let claudeGptColor = Color(red: 0.85, green: 0.65, blue: 0.95)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: "Antigravity", result: result)

            if let snapshot = result.snapshot {
                VStack(alignment: .leading, spacing: 8) {
                    ModelGroup(
                        title: L10n.tr("Gemini models"),
                        color: .cyan,
                        fiveHour: snapshot.fiveHour,
                        sevenDay: snapshot.sevenDay
                    )

                    if snapshot.hasClaudeGpt {
                        Divider()
                            .opacity(0.4)

                        ModelGroup(
                            title: L10n.tr("Claude and GPT models"),
                            color: Self.claudeGptColor,
                            fiveHour: snapshot.fiveHourClaudeGpt,
                            sevenDay: snapshot.sevenDayClaudeGpt
                        )
                    }
                }
            } else if error == nil {
                NoDataYetLabel()
            }

            CollectorErrorLabel(error: error)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }

    private struct ModelGroup: View {
        let title: String
        let color: Color
        let fiveHour: QuotaWindow?
        let sevenDay: QuotaWindow?

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 5, height: 5)
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(color)
                }
                HStack(spacing: 12) {
                    QuotaMetricColumn(label: L10n.tr("5 hours"), window: fiveHour)
                    Divider()
                        .frame(height: 28)
                    QuotaMetricColumn(label: L10n.tr("7 days"), window: sevenDay)
                }
            }
        }
    }
}

// MARK: - Card building blocks

private struct CardHeader: View {
    let title: String
    let result: QuotaLoadResult

    var body: some View {
        HStack {
            Circle()
                .fill(result.snapshot != nil ? (result.isStale ? Color.orange : Color.green) : Color.gray)
                .frame(width: 6, height: 6)
            Text(verbatim: title)
                .font(.subheadline)
                .bold()
            Spacer()
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(result.isStale ? .orange : .secondary)
        }
    }

    private var subtitle: String {
        guard let snapshot = result.snapshot else { return L10n.tr("no data") }
        let age = QuotaFormat.age(snapshot.age())
        return result.isStale ? L10n.tr("stale · %@", age) : age
    }
}

private struct NoDataYetLabel: View {
    var body: some View {
        Text(L10n.tr("No data collected yet"))
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.vertical, 2)
    }
}

private struct CollectorErrorLabel: View {
    let error: CollectorError?

    var body: some View {
        if let error {
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct QuotaMetricColumn: View {
    let label: String
    let window: QuotaWindow?
    var missingNote: String? = nil

    var body: some View {
        let status = window?.status()
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(verbatim: status.map { "\(Int($0.usedPercent.rounded()))%" } ?? "—")
                    .font(.subheadline)
                    .bold()
                    .monospacedDigit()
                    .foregroundColor(status == nil ? .secondary : .primary)
            }
            Text(status.map { QuotaFormat.countdown(to: $0.resetsAt) } ?? missingNote ?? "—")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(status == nil && missingNote != nil ? 0.6 : 1)
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @AppStorage(L10n.languageKey, store: L10n.defaults) private var language = AppLanguage.english.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var refreshInterval = QuotaConfig.refreshIntervalMinutes

    private static let intervals: [(minutes: Int, title: String)] = [
        (1, "1 minute"), (2, "2 minutes"), (5, "5 minutes (default)"),
        (10, "10 minutes"), (15, "15 minutes"), (30, "30 minutes"), (60, "1 hour")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "gauge.medium")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "AI Quota Studio").font(.title3).bold()
                    Text(L10n.tr("Autonomous quota tracking for Claude Code, Antigravity and Codex."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            SettingsSection(title: L10n.tr("Language")) {
                Picker(L10n.tr("Interface language:"), selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(verbatim: option.nativeName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            SettingsSection(title: L10n.tr("Auto-refresh interval")) {
                Picker(L10n.tr("Polling frequency:"), selection: $refreshInterval) {
                    ForEach(Self.intervals, id: \.minutes) { interval in
                        Text(L10n.tr(interval.title)).tag(interval.minutes)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: refreshInterval) { _, newValue in
                    QuotaConfig.refreshIntervalMinutes = newValue
                    QuotaBridge.shared.runCollector(force: true)
                }
                Text(L10n.tr("The app polls quotas in the background and updates the widgets."))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            SettingsSection(title: L10n.tr("Startup")) {
                Toggle(L10n.tr("Launch at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        try? enabled ? SMAppService.mainApp.register()
                                     : SMAppService.mainApp.unregister()
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                Text(L10n.tr("The app runs in the menu bar, without a Dock icon."))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 400)
        .id(language)
        .onChange(of: language) { _, newValue in
            // Mirrors the choice to settings.json, which the widget reads on its next render.
            L10n.language = AppLanguage(rawValue: newValue) ?? .english
            WidgetCenter.shared.reloadAllTimelines()
        }
        .navigationTitle(L10n.tr("AI Quota Studio Settings"))
        .onAppear {
            refreshInterval = QuotaConfig.refreshIntervalMinutes
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).bold()
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }
}

#Preview {
    MenuBarContentView()
}
