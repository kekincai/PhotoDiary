import SwiftUI

/// 首页：那年今日、本周写作、还没写的照片、最近的日记。
struct WatchHomeView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.hasSnapshot {
                    content
                } else {
                    waiting
                }
            }
            .navigationTitle("照片日记")
            .navigationDestination(for: String.self) { id in
                WatchEntryView(id: id)
            }
            .navigationDestination(for: WatchPhoto.self) { photo in
                WatchComposeView(assetID: photo.id, mode: .new, day: photo.day)
            }
            .navigationDestination(for: WatchWrite.self) { write in
                FailedWriteView(write: write)
            }
        }
    }

    private var content: some View {
        let memories = store.onThisDay()
        let week = store.week()
        return List {
            if !store.failed.isEmpty {
                Section("没写进照片说明") {
                    ForEach(store.failed) { write in
                        NavigationLink(value: write) {
                            Text(write.text)
                                .font(.system(.footnote, design: .serif))
                                .lineLimit(2)
                        }
                    }
                }
            }

            if let memory = memories.first {
                Section {
                    MemoryCard(entry: memory)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                WeekStrip(week: week.days, written: week.written)
            }

            if !store.unwritten.isEmpty {
                Section("还没写的照片") {
                    UnwrittenStrip(photos: store.unwritten)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section("最近") {
                ForEach(store.entries) { entry in
                    NavigationLink(value: entry.id) {
                        EntryRowWatch(entry: entry)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新", systemImage: "arrow.clockwise") { store.requestRefresh() }
                    .disabled(!store.isReachable)
            }
        }
    }

    private var waiting: some View {
        VStack(spacing: 10) {
            BrandMark(width: 56, palette: .dark, developed: 0.35, written: 0)
                .padding(.bottom, 6)
            Text("等待 iPhone")
                .font(.headline)
            Text("在 iPhone 上打开照片日记，最近的日记会自动同步到手表")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 6)
    }
}

// MARK: 那年今日

private struct MemoryCard: View {
    let entry: DiaryEntry
    @Environment(WatchStore.self) private var store

    var body: some View {
        NavigationLink(value: entry.id) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let image = store.image(entry.id) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(height: 150)
                .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(DiaryDates.onThisDay(entry.day))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(entry.title)
                        .font(.system(.headline, design: .serif, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(10)
            }
            .frame(height: 150)
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(DiaryDates.onThisDay(entry.day))：\(entry.title)"))
    }
}

// MARK: 本周

private struct WeekStrip: View {
    let week: [WatchWeekDay]
    let written: Int
    private let names = DiaryDates.weekdaySymbols

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(written == 0 ? String(localized: "这周还没写") : String(localized: "这周写了 \(written) 篇"))
                .font(.footnote.weight(.semibold))
            HStack(spacing: 0) {
                ForEach(Array(week.enumerated()), id: \.offset) { i, day in
                    let isToday = day.day == .today
                    VStack(spacing: 4) {
                        Text(i < names.count ? names[i] : "")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Circle()
                            .fill(day.wrote ? Color.accentColor : Color.white.opacity(0.12))
                            .frame(width: 14, height: 14)
                            .overlay {
                                if isToday { Circle().strokeBorder(Color.accentColor, lineWidth: 1.5).padding(-3) }
                            }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 4)
        // 七个圆点读出来没有意义：读“这周写了 2 篇”，再说写了哪几天。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(written == 0 ? String(localized: "这周还没写") : String(localized: "这周写了 \(written) 篇"))
        .accessibilityValue(writtenDays)
    }

    private var writtenDays: String {
        let days = week.filter(\.wrote).map { DiaryDates.weekday($0.day.date) }
        guard !days.isEmpty else { return "" }
        return String(localized: "写过的日子：\(days.formatted(.list(type: .and)))")
    }
}

// MARK: 还没写的照片

private struct UnwrittenStrip: View {
    let photos: [WatchPhoto]
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(photos) { photo in
                    NavigationLink(value: photo) {
                        ZStack(alignment: .bottomTrailing) {
                            Group {
                                if let image = store.image(photo.id) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else {
                                    Color.gray.opacity(0.3)
                                }
                            }
                            .frame(width: 72, height: 72)
                            .clipped()
                            Image(systemName: "mic.fill")
                                .font(.system(size: 10, weight: .bold))
                                .accessibilityHidden(true)
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.accentColor, in: .circle)
                                .padding(4)
                        }
                        .clipShape(.rect(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(photo.day.map { Text("给\(DiaryDates.short($0))的照片口述") } ?? Text("给这张照片口述"))
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: 一行

private struct EntryRowWatch: View {
    let entry: DiaryEntry
    @Environment(WatchStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let image = store.image(entry.id) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.3)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? entry.preview : entry.title)
                    .font(.system(.footnote, design: .serif, weight: .semibold))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        [DiaryDates.short(entry.day), entry.placeName].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: 没写进去的一段

/// iPhone 写不进去的一段（照片删了、改不了说明）：原文留在这里，看过再删。
private struct FailedWriteView: View {
    let write: WatchWrite
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(write.text)
                    .font(.system(.body, design: .serif))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("删掉这段", role: .destructive) {
                    store.dismissFailed(write.id)
                    dismiss()
                }
            }
        }
        .navigationTitle("没写进去")
    }
}
