//
//  ClaudeQuotaWidget.swift
//  AIQuotaWidget
//

import SwiftUI
import WidgetKit

struct ClaudeQuotaProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: Date(), result: .ok(QuotaSnapshot.preview))
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        if context.isPreview {
            completion(QuotaEntry(date: Date(), result: .ok(QuotaSnapshot.preview)))
        } else {
            completion(QuotaEntry(date: Date(), result: QuotaStore.load(.claude), error: QuotaStore.loadError(.claude)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        completion(QuotaTimeline.build(for: .claude))
    }
}

struct ClaudeQuotaWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: QuotaEntry

    var body: some View {
        QuotaCardView(
            providerTitle: "Claude Code",
            accent: .amber,
            entry: entry,
            family: family
        )
    }
}

struct ClaudeQuotaWidget: Widget {
    let kind: String = "ClaudeQuotaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudeQuotaProvider()) { entry in
            ClaudeQuotaWidgetEntryView(entry: entry)
                .quotaContainerBackground()
        }
        .configurationDisplayName("Claude Code quotas")
        .description("Claude Code 5-hour and weekly quota usage and time until reset.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemMedium) {
    ClaudeQuotaWidget()
} timeline: {
    QuotaEntry(date: .now, result: .ok(QuotaSnapshot.preview))
    QuotaEntry(date: .now, result: .missing)
}
