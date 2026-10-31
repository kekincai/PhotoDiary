import SwiftUI
import Photos

/// 回顾：那年今日、本周写作、还没写的照片、标签。
struct ReviewView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.brand) private var brand

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                OnThisDayCard()
                WeekStrip()
                links
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 130)
        }
        .background(Color.groupedBackground)
        .navigationTitle("回顾")
        .toolbarTitleDisplayMode(.large)
    }

    private var links: some View {
        VStack(spacing: 0) {
            Button { router.showAddFromPhotos = true } label: {
                CardRow(title: "还没写的照片", subtitle: "趁还记得，写下当时的感受") {
                    UnwrittenStack()
                }
            }
            .buttonStyle(.row())
            Rectangle().fill(Color.hairline).frame(height: 1).padding(.leading, 16)
            NavigationLink(value: Route.tags) {
                CardRow(title: "标签", subtitle: tagSummary) { EmptyView() }
            }
            .buttonStyle(.row())
        }
        .background(Color.card, in: .rect(cornerRadius: 20, style: .continuous))
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
    }

    private var tagSummary: String {
        let tags = store.tagCounts
        if tags.isEmpty { return "在说明里写 #话题#，就会出现在这里" }
        let names = tags.prefix(3).map(\.name).joined(separator: "、")
        return tags.count > 3 ? "\(names)等 \(tags.count) 个" : names
    }
}

/// 那年今日：可左右翻页，可直接追加感想。
private struct OnThisDayCard: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.brand) private var brand
    @State private var page: String?

    var body: some View {
        let memories = store.onThisDay
        if memories.isEmpty {
            empty
        } else {
            VStack(spacing: 10) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(memories) { entry in
                            card(entry)
                                .containerRelativeFrame(.horizontal)
                                .id(entry.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                .scrollIndicators(.hidden)
                .clipShape(.rect(cornerRadius: 24, style: .continuous))
                .frame(height: 360)

                if memories.count > 1 {
                    PageDots(count: memories.count, index: memories.firstIndex { $0.id == page } ?? 0)
                }
            }
        }
    }

    private func card(_ entry: DiaryEntry) -> some View {
        NavigationLink(value: Route.entry(entry.id)) {
            Color.clear
                .overlay { AssetImage(id: entry.id, allowNetwork: true) }
                .clipped()
                .overlay(alignment: .bottom) { panel(entry) }
        }
        .buttonStyle(.press)
        .accessibilityLabel("\(DiaryDates.yearsAgo(entry.day))的今天：\(entry.title)")
    }

    private func panel(_ entry: DiaryEntry) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(DiaryDates.yearsAgo(entry.day))的今天")
                        .fontWeight(.semibold)
                        .foregroundStyle(brand)
                    if let place = entry.placeName {
                        Text(place).foregroundStyle(Color.meta).lineLimit(1)
                    }
                }
                .font(.footnote)
                Text(entry.title)
                    .font(.diary(18, bold: true))
                    .lineSpacing(5)
                    .foregroundStyle(Color.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                router.editor = EditorRequest(assetID: entry.id, mode: .append)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(brand)
            .accessibilityLabel("追加感想")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .glassEffect(.regular, in: .rect(cornerRadius: 18, style: .continuous))
        .padding(10)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("往年的今天还没有日记")
                .font(.headline)
            Text("今天写下的，明年的这一天会出现在这里。")
                .font(.subheadline)
                .foregroundStyle(Color.meta)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.card, in: .rect(cornerRadius: 20, style: .continuous))
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color.ink.opacity(0.7) : Color.ink.opacity(0.18))
                    .frame(width: i == index ? 16 : 6, height: 6)
            }
        }
        .animation(.snappy, value: index)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("第 \(index + 1) 篇，共 \(count) 篇")
    }
}

/// 本周写作：按说明里的写作日期，写过的日子下面有一个点。
private struct WeekStrip: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.brand) private var brand
    private let names = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        let week = store.weekWriting
        let today = DayStamp.today
        VStack(alignment: .leading, spacing: 14) {
            Text(headline(week))
                .font(.headline)
                .contentTransition(.numericText())
            HStack(spacing: 0) {
                ForEach(Array(week.enumerated()), id: \.offset) { i, item in
                    VStack(spacing: 6) {
                        Text(names[i])
                            .font(.caption)
                            .foregroundStyle(Color.meta)
                        Text("\(item.day.day)")
                            .font(.body.weight(item.day == today ? .bold : .regular).monospacedDigit())
                            .foregroundStyle(item.day == today ? brand : (item.day > today ? Color(.tertiaryLabel) : Color.ink))
                        Circle()
                            .fill(item.wrote ? brand : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(DiaryDates.short(item.day))\(item.wrote ? "，写了日记" : "")")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.card, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func headline(_ week: [(day: DayStamp, wrote: Bool)]) -> String {
        let days = Set(week.map(\.day))
        let n = store.diaries.reduce(0) { $0 + $1.writingDays.filter(days.contains).count }
        return n == 0 ? "这周还没写" : "这周写了 \(n) 篇"
    }
}

/// 三张叠起来的未写照片缩略图。
private struct UnwrittenStack: View {
    @Environment(DiaryStore.self) private var store
    @State private var ids: [String] = []

    var body: some View {
        HStack(spacing: -14) {
            ForEach(ids, id: \.self) { id in
                AssetImage(id: id, pointSize: CGSize(width: 40, height: 40))
                    .frame(width: 40, height: 40)
                    .clipShape(.rect(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.card, lineWidth: 2))
            }
        }
        .task(id: store.diaries.count) {
            let recent = await Task.detached { AssetImages.recentAssets(limit: 60) }.value
            ids = Array(recent.map(\.id).filter { store.entry($0) == nil }.prefix(3))
        }
    }
}
