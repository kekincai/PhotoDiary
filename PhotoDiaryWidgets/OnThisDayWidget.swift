import WidgetKit
import SwiftUI
import UIKit

// MARK: 那年今日（主屏中、大尺寸）
//
// 照片铺满，底部压一层暗色，写日期和标题（大尺寸多几行预览）；点开是这一篇。
// 往年的今天没有日记时只有一句标题，点开是回顾。颜色交给照片，不用主题色。

nonisolated struct MemoryEntry: TimelineEntry {
    var date: Date
    var memory: WidgetMemory?
    var language: String?
}

/// WidgetKit 在后台队列上调这些方法，provider 必须是 nonisolated（工程默认主线程隔离）。
nonisolated struct OnThisDayProvider: TimelineProvider {
    func placeholder(in context: Context) -> MemoryEntry {
        MemoryEntry(date: .now, memory: WidgetMemory(id: "", day: DayStamp(year: 2024, month: 1, day: 1)!, title: "——", preview: ""))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (MemoryEntry) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let first = snapshot?.timeline(from: .now).first
        completion(MemoryEntry(date: .now, memory: first?.memory, language: snapshot?.language))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<MemoryEntry>) -> Void) {
        guard let snapshot = WidgetSnapshot.load() else {
            completion(Timeline(entries: [MemoryEntry(date: .now)], policy: .never))
            return
        }
        let entries = snapshot.timeline(from: .now).map {
            MemoryEntry(date: $0.date, memory: $0.memory, language: snapshot.language)
        }
        // 排完一周之后 App 还没开过：回到空的样子。
        let end = Calendar.diary.date(byAdding: .day, value: WidgetSnapshot.days, to: snapshot.today.date) ?? .now
        let tail = MemoryEntry(date: Calendar.diary.startOfDay(for: end), memory: nil, language: snapshot.language)
        completion(Timeline(entries: entries.isEmpty ? [MemoryEntry(date: .now, language: snapshot.language)] : entries + [tail],
                            policy: .never))
    }
}

struct OnThisDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnThisDay", provider: OnThisDayProvider()) { entry in
            OnThisDayView(entry: entry)
        }
        .configurationDisplayName("那年今日")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct OnThisDayView: View {
    let entry: MemoryEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let _ = WidgetLanguage.apply(entry.language)
        Group {
            if let memory = entry.memory {
                memoryView(memory)
            } else {
                Text(String(localized: "往年的今天还没有日记", bundle: .app, locale: .app))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .containerBackground(.fill.tertiary, for: .widget)
                    .widgetURL(DeepLink.onThisDay.url)
            }
        }
        .environment(\.locale, Locale.app)
    }

    private func memoryView(_ memory: WidgetMemory) -> some View {
        let large = family == .systemLarge
        let years = max(1, DayStamp(entry.date).year - memory.day.year)
        let heading = String(localized: "\(years) 年前的今天", bundle: .app, locale: .app)
        let title = memory.title.isEmpty ? memory.preview : memory.title
        return VStack(alignment: .leading, spacing: 3) {
            Spacer(minLength: 0)
            Text(heading)
                .font(.caption.weight(.semibold))
                .opacity(0.85)
            if !title.isEmpty {
                Text(title)
                    .font(large ? .title3 : .headline)
                    .fontDesign(.serif)
                    .lineLimit(large ? 3 : 2)
            }
            if large, !memory.preview.isEmpty, memory.preview != title {
                Text(memory.preview)
                    .font(.subheadline)
                    .fontDesign(.serif)
                    .lineLimit(3)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(16)
        .containerBackground(for: .widget) { PhotoBackground(id: memory.id) }
        .widgetURL(DeepLink.entry(memory.id).url)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: [heading, DiaryDates.full(memory.day), title].filter { !$0.isEmpty }.joined(separator: "，")))
    }
}

/// 共享容器里的照片，铺满；底部压暗，白字才看得清。
private struct PhotoBackground: View {
    let id: String

    var body: some View {
        ZStack {
            Color.black
            if let url = WidgetSnapshot.thumbnailURL(for: id), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .widgetAccentedRenderingMode(.desaturated)
                    .scaledToFill()
            }
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
        }
    }
}
