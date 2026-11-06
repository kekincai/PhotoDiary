import WidgetKit
import SwiftUI

// MARK: 写今天（锁屏圆形）
//
// 一支笔；今天写过了换成对勾。点开直接是最新一张照片的编辑器。

nonisolated struct WriteTodayEntry: TimelineEntry {
    var date: Date
    var wrote: Bool
    var language: String?
}

nonisolated struct WriteTodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> WriteTodayEntry {
        WriteTodayEntry(date: .now, wrote: false)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (WriteTodayEntry) -> Void) {
        let snapshot = WidgetSnapshot.load()
        completion(WriteTodayEntry(date: .now, wrote: snapshot?.wrote(on: .today) ?? false, language: snapshot?.language))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WriteTodayEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let now = WriteTodayEntry(date: .now, wrote: snapshot?.wrote(on: .today) ?? false, language: snapshot?.language)
        // 零点以后就是新的一天，还没写。
        let midnight = Calendar.diary.date(byAdding: .day, value: 1, to: Calendar.diary.startOfDay(for: .now)) ?? .now
        let next = WriteTodayEntry(date: midnight, wrote: false, language: snapshot?.language)
        completion(Timeline(entries: [now, next], policy: .never))
    }
}

struct WriteTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WriteToday", provider: WriteTodayProvider()) { entry in
            WriteTodayView(entry: entry)
        }
        .configurationDisplayName("写日记")
        .supportedFamilies([.accessoryCircular])
    }
}

struct WriteTodayView: View {
    let entry: WriteTodayEntry

    var body: some View {
        let _ = WidgetLanguage.apply(entry.language)
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: entry.wrote ? "checkmark" : "square.and.pencil")
                .font(.title2.weight(.medium))
                .widgetAccentable()
        }
        .containerBackground(.clear, for: .widget)
        .widgetURL(DeepLink.writeLatest.url)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: entry.wrote
            ? String(localized: "今天写过了", bundle: .app, locale: .app)
            : String(localized: "写日记", bundle: .app, locale: .app)))
    }
}
