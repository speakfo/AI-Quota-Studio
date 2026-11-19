//
//  QuotaWidgetViews.swift
//  AIQuotaWidget
//
//  Shared layout for the Claude Code, Antigravity and Codex widgets.
//

import SwiftUI
import WidgetKit

// MARK: - Palette

extension Color {
    static let amber = Color(red: 0.95, green: 0.65, blue: 0.15)
    static let codexGreen = Color(red: 0.36, green: 0.82, blue: 0.68)
    // Named `quotaBackground`, not `widgetBackground`: the asset catalog already
    // generates `Color.widgetBackground` from WidgetBackground.colorset.
    static let quotaBackground = Color(red: 0.08, green: 0.10, blue: 0.16)

    /// Bar color by remaining quota: the less is left, the more alarming.
    static func quotaLevel(remaining: Double) -> Color {
        switch remaining {
        case ..<15: return Color(red: 0.94, green: 0.33, blue: 0.31)
        case ..<40: return Color(red: 0.95, green: 0.65, blue: 0.15)
        default: return Color(red: 0.30, green: 0.80, blue: 0.50)
        }
    }
}

// MARK: - Timeline entry

struct QuotaEntry: TimelineEntry {
    let date: Date
    let result: QuotaLoadResult
    /// Why the last collection failed; nil — it succeeded.
    var error: CollectorError? = nil
}

// MARK: - Single window row

struct QuotaRowView: View {
    let title: String
    let status: QuotaWindowStatus?
    let now: Date
    var compact: Bool = false
    /// The plan has no such window: the row is dimmed and explains why instead of "no data".
    var missingNote: String? = nil

    private var levelColor: Color {
        guard let status else { return .gray }
        return .quotaLevel(remaining: status.remainingPercent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                // Show usage, like /usage in Claude Code, so the numbers match
                // and nobody has to subtract in their head.
                Text(compact ? L10n.tr("used (short)") : L10n.tr("used"))
                    .font(.system(size: compact ? 8 : 9))
                    .foregroundColor(.gray)
                if let status {
                    Text(verbatim: "\(Int(status.usedPercent.rounded()))%")
                        .font(.system(size: compact ? 11 : 13, weight: .bold))
                        .foregroundColor(levelColor)
                } else {
                    Text(verbatim: "—")
                        .font(.system(size: compact ? 11 : 13, weight: .bold))
                        .foregroundColor(.gray)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    if let status {
                        Capsule()
                            .fill(levelColor)
                            .frame(width: geo.size.width * CGFloat(status.usedPercent) / 100)
                    }
                }
            }
            .frame(height: compact ? 5 : 6)

            Text(footnote)
                .font(.system(size: compact ? 8 : 9))
                .foregroundColor(.gray)
                .lineLimit(1)
        }
        .opacity(status == nil && missingNote != nil ? 0.55 : 1)
    }

    private var footnote: String {
        guard let status else { return missingNote ?? L10n.tr("no data") }
        if status.didResetSinceMeasurement { return L10n.tr("window reset") }
        return L10n.tr("resets in %@", QuotaFormat.countdown(to: status.resetsAt, now: now))
    }
}

// MARK: - Compact single window row (Small widget with several model groups)

struct CompactQuotaRowView: View {
    let title: String
    let status: QuotaWindowStatus?
    let now: Date

    private var levelColor: Color {
        guard let status else { return .gray }
        return .quotaLevel(remaining: status.remainingPercent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let countdown = status.map({ QuotaFormat.countdown(to: $0.resetsAt, now: now) }), countdown != "—" {
                    Text(verbatim: "· \(countdown)")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                if let status {
                    Text(verbatim: "\(Int(status.usedPercent.rounded()))%")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(levelColor)
                } else {
                    Text(verbatim: "—")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.gray)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    if let status {
                        Capsule()
                            .fill(levelColor)
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(status.usedPercent) / 100)))
                    }
                }
            }
            .frame(height: 3.5)
        }
    }
}

// MARK: - Provider card (Claude Code, Codex)

struct QuotaCardView: View {
    let providerTitle: String
    let accent: Color
    let entry: QuotaEntry
    let family: WidgetFamily
    /// Which windows to show. Defaults to 5 hours and week, even when empty.
    var rows: (QuotaSnapshot) -> [QuotaRow] = { $0.defaultRows }

    private var compact: Bool { family == .systemSmall }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : (family == .systemLarge ? 16 : 10)) {
            HStack(alignment: .firstTextBaseline) {
                Text(providerTitle)
                    .font(.system(size: compact ? 13 : (family == .systemLarge ? 17 : 15), weight: .bold))
                    .foregroundColor(accent)
                Spacer()
                StatusBadge(entry: entry, compact: compact)
            }

            if case .missing = entry.result {
                MissingDataView(compact: compact, error: entry.error)
            } else if let snapshot = entry.result.snapshot {
                let items = rows(snapshot)
                ForEach(items.indices, id: \.self) { index in
                    QuotaRowView(
                        title: items[index].title,
                        status: items[index].window?.status(now: entry.date),
                        now: entry.date,
                        compact: compact,
                        missingNote: items[index].missingNote
                    )
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Antigravity card (Gemini + Claude & GPT)

struct AntigravityQuotaCardView: View {
    let entry: QuotaEntry
    let family: WidgetFamily

    private var compact: Bool { family == .systemSmall }

    /// One model family: its 5-hour and weekly limits plus single-model limits.
    private struct ModelGroup {
        let title: String
        let color: Color
        let fiveHour: QuotaWindow?
        let sevenDay: QuotaWindow?
        let models: [ModelQuota]
    }

    private static let claudeGptColor = Color(red: 0.85, green: 0.65, blue: 0.95)

    private func modelGroups(_ snapshot: QuotaSnapshot?) -> [ModelGroup] {
        [
            ModelGroup(
                title: L10n.tr("Gemini models"),
                color: .cyan,
                fiveHour: snapshot?.fiveHour,
                sevenDay: snapshot?.sevenDay,
                models: snapshot?.modelQuotas(claudeGpt: false) ?? []
            ),
            ModelGroup(
                title: L10n.tr("Claude and GPT models"),
                color: Self.claudeGptColor,
                fiveHour: snapshot?.fiveHourClaudeGpt,
                sevenDay: snapshot?.sevenDayClaudeGpt,
                models: snapshot?.modelQuotas(claudeGpt: true) ?? []
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : (family == .systemLarge ? 14 : 8)) {
            // Widget title (large, to stand out above the model groups)
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "Antigravity")
                    .font(.system(size: compact ? 13 : (family == .systemLarge ? 17 : 15), weight: .bold))
                    .foregroundColor(.cyan)
                Spacer()
                StatusBadge(entry: entry, compact: compact)
            }

            if case .missing = entry.result {
                MissingDataView(compact: compact, error: entry.error)
            } else {
                let groups = modelGroups(entry.result.snapshot)

                switch family {
                case .systemSmall:
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(groups.indices, id: \.self) { index in
                            smallGroup(groups[index])
                        }
                    }

                case .systemMedium:
                    // Model limits make a third row; full rows would not fit the height.
                    let dense = groups.contains { !$0.models.isEmpty }
                    HStack(alignment: .top, spacing: 12) {
                        mediumGroup(groups[0], dense: dense)
                        Divider()
                            .opacity(0.2)
                        mediumGroup(groups[1], dense: dense)
                    }

                default:
                    // Large
                    // Model limits add rows: switch every row to the compact style to keep the height.
                    let dense = groups.contains { !$0.models.isEmpty }
                    VStack(alignment: .leading, spacing: 14) {
                        largeGroup(groups[0], dense: dense)
                        Divider()
                            .opacity(0.3)
                        largeGroup(groups[1], dense: dense)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func groupHeader(_ group: ModelGroup, dot: CGFloat, fontSize: CGFloat, tinted: Bool, minScale: CGFloat = 1) -> some View {
        HStack(spacing: dot - 1) {
            Circle().fill(group.color).frame(width: dot, height: dot)
            Text(group.title)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundColor(tinted ? group.color : .white)
                .lineLimit(1)
                .minimumScaleFactor(minScale)
        }
    }

    /// Small: no room for model rows, only the family limits.
    private func smallGroup(_ group: ModelGroup) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            groupHeader(group, dot: 4, fontSize: 9.5, tinted: false, minScale: 0.75)
            CompactQuotaRowView(title: L10n.tr("5h"), status: group.fiveHour?.status(now: entry.date), now: entry.date)
            CompactQuotaRowView(title: L10n.tr("7d"), status: group.sevenDay?.status(now: entry.date), now: entry.date)
        }
    }

    private func mediumGroup(_ group: ModelGroup, dense: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            groupHeader(group, dot: 5, fontSize: 11.5, tinted: false, minScale: 0.85)
            if dense {
                CompactQuotaRowView(title: L10n.tr("5h"), status: group.fiveHour?.status(now: entry.date), now: entry.date)
                CompactQuotaRowView(title: L10n.tr("7d"), status: group.sevenDay?.status(now: entry.date), now: entry.date)
                ForEach(group.models) { model in
                    CompactQuotaRowView(title: model.title(compact: true), status: model.window.status(now: entry.date), now: entry.date)
                }
            } else {
                QuotaRowView(title: L10n.tr("5 hours"), status: group.fiveHour?.status(now: entry.date), now: entry.date, compact: true)
                QuotaRowView(title: L10n.tr("Week"), status: group.sevenDay?.status(now: entry.date), now: entry.date, compact: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func largeGroup(_ group: ModelGroup, dense: Bool) -> some View {
        VStack(alignment: .leading, spacing: dense ? 6 : 8) {
            groupHeader(group, dot: 6, fontSize: 13.5, tinted: true)
            QuotaRowView(title: L10n.tr("5 hours"), status: group.fiveHour?.status(now: entry.date), now: entry.date, compact: dense)
            QuotaRowView(title: L10n.tr("Week"), status: group.sevenDay?.status(now: entry.date), now: entry.date, compact: dense)
            ForEach(group.models) { model in
                QuotaRowView(title: model.title(compact: false), status: model.window.status(now: entry.date), now: entry.date, compact: true)
            }
        }
    }
}

// MARK: - Empty state

struct MissingDataView: View {
    let compact: Bool
    var error: CollectorError? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(error?.shortMessage.capitalizingFirstLetter ?? L10n.tr("No data"))
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .foregroundColor(error == nil ? .white : .orange)
            Text(hint)
                .font(.system(size: compact ? 8 : 9))
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hint: String {
        switch error {
        case .notInstalled:
            return compact ? L10n.tr("Install the CLI") : L10n.tr("Install the CLI and sign in — AI Quota Studio will find it on its own.")
        case .unparsable(let cli):
            return compact ? L10n.tr("Sign in") : L10n.tr("Run %@ in Terminal and sign in.", cli)
        case .noResponse:
            return compact ? L10n.tr("Will retry later") : L10n.tr("AI Quota Studio will retry on the next poll.")
        case nil:
            return compact ? L10n.tr("Open AI Quota Studio") : L10n.tr("Launch AI Quota Studio: it collects quotas from claude, agy and codex.")
        }
    }
}

// MARK: - Header status

/// A failure reason beats the "stale" mark: it explains why the data is old.
struct StatusBadge: View {
    let entry: QuotaEntry
    let compact: Bool

    var body: some View {
        if let text {
            Text(text)
                .font(.system(size: compact ? 8 : 9, weight: .medium))
                .foregroundColor(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var text: String? {
        // Without data, MissingDataView already shows the reason.
        if case .missing = entry.result { return nil }
        if let error = entry.error { return error.shortMessage }
        if entry.result.isStale { return compact ? L10n.tr("stale") : L10n.tr("data is stale") }
        return nil
    }
}

private extension String {
    var capitalizingFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Background

extension View {
    /// Desktop widgets clip a plain `.background(...)`; the gradient has
    /// to go through containerBackground to reach the widget surface.
    func quotaContainerBackground() -> some View {
        containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color.quotaBackground, Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
