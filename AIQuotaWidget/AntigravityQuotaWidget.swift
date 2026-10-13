//
//  AntigravityQuotaWidget.swift
//  AIQuotaWidget
//

import SwiftUI
import WidgetKit

struct AntigravityQuotaProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: Date(), result: .ok(QuotaSnapshot.preview))
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        if context.isPreview {
            completion(QuotaEntry(date: Date(), result: .ok(QuotaSnapshot.preview)))
        } else {
            completion(QuotaEntry(date: Date(), result: QuotaStore.load(.antigravity), error: QuotaStore.loadError(.antigravity)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        completion(QuotaTimeline.build(for: .antigravity))
    }
}

struct AntigravityQuotaWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: QuotaEntry

    var body: some View {
        AntigravityQuotaCardView(
            entry: entry,
            family: family
        )
    }
}

struct AntigravityQuotaWidget: Widget {
    let kind: String = "AntigravityQuotaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AntigravityQuotaProvider()) { entry in
            AntigravityQuotaWidgetEntryView(entry: entry)
                .quotaContainerBackground()
        }
        .configurationDisplayName("Antigravity quotas")
        .description("Gemini, Claude and GPT model quota usage in Antigravity and time until reset.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview("Antigravity Medium", as: .systemMedium) {
    AntigravityQuotaWidget()
} timeline: {
    QuotaEntry(date: .now, result: .ok(QuotaSnapshot.preview))
    QuotaEntry(date: .now, result: .missing)
    QuotaEntry(date: .now, result: .missing, error: .notInstalled("agy"))
    QuotaEntry(date: .now, result: .stale(QuotaSnapshot.preview), error: .unparsable("agy"))
}

#Preview("Antigravity Small", as: .systemSmall) {
    AntigravityQuotaWidget()
} timeline: {
    QuotaEntry(date: .now, result: .ok(QuotaSnapshot.preview))
}

#Preview("Antigravity Large", as: .systemLarge) {
    AntigravityQuotaWidget()
} timeline: {
    QuotaEntry(date: .now, result: .ok(QuotaSnapshot.preview))
}
