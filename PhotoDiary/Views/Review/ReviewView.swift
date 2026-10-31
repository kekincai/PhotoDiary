import SwiftUI
import Photos

/// 回顾：参照照片 App 的精选集。那年今日、本周写作、还没写的照片、标签。
struct ReviewView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                OnThisDaySection()
                WeekSection()
                UnwrittenSection()
                TagsSection()
            }
            .padding(.top, 8)
            .padding(.bottom, 150)
        }
        .background(Color(.systemBackground))
        .navigationTitle("回顾")
        .toolbarTitleDisplayMode(.large)
    }
}

// MARK: 那年今日：横向翻页的大卡片，露出下一张的边缘

private struct OnThisDaySection: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @State private var page: String?

    var body: some View {
        let memories = store.onThisDay
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: String(localized: "那年今日"))
                .padding(.horizontal, 20)
            if memories.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("往年的今天还没有日记")
                        .font(.headline)
                    Text("今天写下的，明年的这一天会出现在这里。")
                        .font(.subheadline)
                        .foregroundStyle(Color.meta)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Color.tile, in: .rect(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(memories) { entry in
                            card(entry)
                                .containerRelativeFrame(.horizontal) { width, _ in
                                    memories.count > 1 ? width - 60 : width - 32
                                }
                                .frame(height: 420)
                                .id(entry.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $page)
                .scrollIndicators(.hidden)

                if memories.count > 1 {
                    PageDots(count: memories.count, index: memories.firstIndex { $0.id == page } ?? 0)
                }
            }
        }
    }

    private func card(_ entry: DiaryEntry) -> some View {
        NavigationLink(value: Route.entry(entry.id)) {
            Color.black
                .overlay { AssetImage(id: entry.id, allowNetwork: true) }
                .overlay(alignment: .bottom) {
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0), location: 0),
                        .init(color: .black.opacity(0.35), location: 0.4),
                        .init(color: .black.opacity(0.72), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: 260)
                }
                .overlay(alignment: .bottomLeading) { caption(entry) }
                .clipShape(.rect(cornerRadius: 26, style: .continuous))
                .contentShape(.rect(cornerRadius: 26))
        }
        .buttonStyle(.press)
        .overlay(alignment: .bottomTrailing) {
            Button {
                router.editor = EditorRequest(assetID: entry.id, mode: .append)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.press)
            .glassEffect(.regular.interactive(), in: .circle)
            .environment(\.colorScheme, .dark)
            .padding(.trailing, 16)
            .padding(.bottom, 20)
            .accessibilityLabel("追加感想")
        }
    }

    private func caption(_ entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(DiaryDates.onThisDay(entry.day))
                .font(.footnote.weight(.semibold))
                .tracking(0.3)
                .opacity(0.88)
            Text(entry.title)
                .font(.diary(23, bold: true, relativeTo: .title2))
                .lineSpacing(8)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            if let detail = detail(entry) {
                Text(detail)
                    .font(.footnote)
                    .opacity(0.82)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(.leading, 22)
        .padding(.trailing, 72)
        .padding(.bottom, 22)
    }

    /// Höfn í Hornafirði · 2 段
    private func detail(_ entry: DiaryEntry) -> String? {
        var parts: [String] = []
        if let place = entry.placeName { parts.append(place) }
        if entry.segments.count > 1 { parts.append(String(localized: "\(entry.segments.count) 段")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color.ink.opacity(0.65) : Color.ink.opacity(0.18))
                    .frame(width: i == index ? 16 : 6, height: 6)
            }
        }
        .animation(.snappy, value: index)
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("第 \(index + 1) 篇，共 \(count) 篇")
    }
}

// MARK: 本周写作：按说明里的写作日期，写过的日子下面有一个点

private struct WeekSection: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.brand) private var brand

    var body: some View {
        let week = store.weekWriting
        let today = DayStamp.today
        let names = DiaryDates.weekdaySymbols
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: headline)
                .contentTransition(.numericText())
                .padding(.horizontal, 20)
            HStack(spacing: 0) {
                ForEach(Array(week.enumerated()), id: \.offset) { i, item in
                    let isToday = item.day == today
                    VStack(spacing: 6) {
                        Text(names[i])
                            .font(.caption)
                            .foregroundStyle(Color.meta)
                        Text("\(item.day.day)")
                            .font(.system(size: 16, weight: isToday ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(isToday ? .white : (item.day > today ? Color(.tertiaryLabel) : Color.ink))
                            .frame(width: 34, height: 34)
                            .background(isToday ? brand : .clear, in: .circle)
                        Circle()
                            .fill(item.wrote ? brand : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.wrote ? Text("\(DiaryDates.short(item.day))，写了日记") : Text(DiaryDates.short(item.day)))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 14)
            .background(Color.tile, in: .rect(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private var headline: String {
        let n = store.writtenThisWeek
        return n == 0 ? String(localized: "这周还没写") : String(localized: "这周写了 \(n) 篇")
    }
}

// MARK: 还没写的照片：横排，点“写”直接打开编辑器

private struct UnwrittenSection: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @State private var photos: [(id: String, date: Date?)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { router.showAddFromPhotos = true } label: {
                SectionTitle(title: String(localized: "还没写的照片"), chevron: true)
            }
            .buttonStyle(.press)
            .padding(.horizontal, 20)
            Text("趁还记得，写下当时的感受")
                .font(.subheadline)
                .foregroundStyle(Color.meta)
                .padding(.horizontal, 20)
                .padding(.top, 6)
            if !photos.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(photos, id: \.id) { photo in
                            tile(photo)
                        }
                    }
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollIndicators(.hidden)
                .frame(height: 150)
                .padding(.top, 12)
            }
        }
        .task(id: store.diaries.count) {
            let recent = await Task.detached { AssetImages.recentAssets(limit: 60) }.value
            photos = Array(recent.filter { store.entry($0.id) == nil }.prefix(12))
        }
    }

    private func tile(_ photo: (id: String, date: Date?)) -> some View {
        let label = photo.date.map(dateLabel)
        return Button {
            router.editor = EditorRequest(assetID: photo.id, mode: .new)
        } label: {
            AssetImage(id: photo.id, pointSize: CGSize(width: 150, height: 150))
                .frame(width: 150, height: 150)
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if let label {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 6)
                            .padding(.leading, 10)
                            .padding(.top, 8)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Text("写")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .glassEffect(.regular, in: .capsule)
                        .environment(\.colorScheme, .dark)
                        .padding(8)
                }
        }
        .buttonStyle(.press)
        .accessibilityLabel(label.map { Text("给\($0)的照片写日记") } ?? Text("给这张照片写日记"))
    }

    private func dateLabel(_ date: Date) -> String {
        let day = DayStamp(date)
        return day == .today ? String(localized: "今天") : DiaryDates.short(day)
    }
}

// MARK: 标签：两列封面（前 4 个）

private struct TagsSection: View {
    @Environment(DiaryStore.self) private var store
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)

    var body: some View {
        let tags = store.tagCounts
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: Route.tags) {
                SectionTitle(title: String(localized: "标签"), chevron: !tags.isEmpty)
            }
            .buttonStyle(.press)
            .disabled(tags.isEmpty)
            .padding(.horizontal, 20)
            if tags.isEmpty {
                Text("在说明里写 #话题#，就会出现在这里")
                    .font(.subheadline)
                    .foregroundStyle(Color.meta)
                    .padding(.horizontal, 20)
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(tags.prefix(4), id: \.name) { tag in
                        NavigationLink(value: Route.tag(tag.name)) {
                            TagCover(name: tag.name, detail: String(localized: "\(tag.count) 篇"))
                        }
                        .buttonStyle(.press)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
