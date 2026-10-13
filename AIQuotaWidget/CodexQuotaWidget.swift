//
//  CodexQuotaWidget.swift
//  AIQuotaWidget
//

import SwiftUI
import WidgetKit

struct CodexQuotaProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: Date(), result: .ok(QuotaSnapshot.preview))
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        if context.isPreview {
            completion(QuotaEntry(date: Date(), result: .ok(QuotaSnapshot.preview)))
        } else {
            completion(QuotaEntry(date: Date(), result: QuotaStore.load(.codex), error: QuotaStore.loadError(.codex)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        completion(QuotaTimeline.build(for: .codex))
    }
}

struct CodexQuotaWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: QuotaEntry

    var body: some View {
        // Free plan: "5 hours: not in your plan" plus the month;
        // Plus/Pro: 5 hours and week.
        QuotaCardView(
            providerTitle: "Codex",
            accent: .codexGreen,
            entry: entry,
            family: family,
            rows: { $0.codexRows }
        )
    }
}

struct CodexQuotaWidget: Widget {
    let kind: String = "CodexQuotaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexQuotaProvider()) { entry in
            CodexQuotaWidgetEntryView(entry: entry)
                .quotaContainerBackground()
        }
        .configurationDisplayName("Codex quotas")
        .description("Codex quota usage and time until reset: 5 hours and week, or the monthly limit of the free plan.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    CodexQuotaWidget()
} timeline: {
    QuotaEntry(date: .now, result: .ok(QuotaSnapshot(
        updatedAt: .now,
        source: "preview",
        windows: [QuotaSnapshot.thirtyDayKey: QuotaWindow(usedPercentage: 64, resetsAt: .now.addingTimeInterval(12 * 86400))]
    )))
    QuotaEntry(date: .now, result: .ok(QuotaSnapshot.preview))
    QuotaEntry(date: .now, result: .missing, error: .notInstalled("codex"))
}
