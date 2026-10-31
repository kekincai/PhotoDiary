import SwiftUI
import Photos

/// 回顾：那年今日大卡片、本周写作、还没写的照片、标签、其他来源的说明。
struct ReviewView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.brand) private var brand

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                OnThisDayCard()
                WeekCard()
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
            separator
            NavigationLink(value: Route.tags) {
                CardRow(title: "标签", subtitle: tagSummary) {
                    Text("#")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(brand)
                        .frame(width: 36, height: 36)
                        .background(brand.opacity(0.1), in: .rect(cornerRadius: 10))
                }
            }
            .buttonStyle(.row())
            separator
            NavigationLink(value: Route.external) {
                CardRow(title: "其他来源的说明", subtitle: externalSummary) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.ink.opacity(0.8))
                        .frame(width: 36, height: 36)
                        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
                }
            }
            .buttonStyle(.row())
        }
        .background(Color.card, in: .rect(cornerRadius: 22))
        .clipShape(.rect(cornerRadius: 22))
    }

    private var separator: some View {
        Rectangle().fill(Color.hairline).frame(height: 1).padding(.leading, 16)
    }

    private var tagSummary: String {
        let tags = store.tagCounts
        if tags.isEmpty { return "在日记里写 #话题# 就会出现在这里" }
        let names = tags.prefix(3).map(\.name).joined(separator: "、")
        return tags.count > 3 ? "\(names)等 \(tags.count) 个" : names
    }

    private var externalSummary: String {
        let n = store.externals.count
        return n == 0 ? "导入时自带或以前写的，不算作日记" : "\(n) 张照片 · 导入时自带或以前写的"
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
        Group {
            if memories.isEmpty {
                empty
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(memories) { entry in
                            card(entry, count: memories.count, index: memories.firstIndex(of: entry) ?? 0)
                                .containerRelativeFrame(.horizontal)
                                .id(entry.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                .scrollIndicators(.hidden)
                .clipShape(.rect(cornerRadius: 26))
            }
        }
        .frame(height: 340)
    }

    private func card(_ entry: DiaryEntry, count: Int, index: Int) -> some View {
        NavigationLink(value: Route.entry(entry.id)) {
            AssetImage(id: entry.id, allowNetwork: true)
                .overlay(alignment: .top) {
                    HStack {
                        Text("那年今日")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.black.opacity(0.42), in: .capsule)
                        Spacer()
                        if count > 1 {
                            HStack(spacing: 5) {
                                ForEach(0..<count, id: \.self) { i in
                                    Capsule()
                                        .fill(.white.opacity(i == index ? 1 : 0.55))
                                        .frame(width: i == index ? 18 : 6, height: 6)
                                }
                            }
                            .accessibilityLabel("共 \(count) 篇")
                        }
                    }
                    .padding(18)
                }
                .overlay(alignment: .bottom) { panel(entry) }
        }
        .buttonStyle(.press)
    }

    private func panel(_ entry: DiaryEntry) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(DiaryDates.yearsAgo(entry.day)) · \(DiaryDates.full(entry.day))")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(brand)
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
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding(10)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(brand)
            Text("那年今日").font(.headline)
            Text("往年的今天还没有日记。\n今天写下的，明年这一天会在这里出现。")
                .font(.subheadline)
                .foregroundStyle(Color.meta)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.card, in: .rect(cornerRadius: 26))
    }
}

/// 本周写作：按说明里的写作日期统计本周哪几天写了日记。
private struct WeekCard: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.brand) private var brand
    private let names = ["日", "一", "二", "三", "四", "五", "六"]

    private func writtenThisWeek(_ week: [(day: DayStamp, wrote: Bool)]) -> Int {
        let days = Set(week.map(\.day))
        return store.diaries.reduce(0) { $0 + $1.writingDays.filter(days.contains).count }
    }

    var body: some View {
        let week = store.weekWriting
        let today = DayStamp.today
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("这周").font(.headline)
                Spacer()
                Text("本周 \(writtenThisWeek(week)) 篇")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(brand)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 6) {
                ForEach(Array(week.enumerated()), id: \.offset) { i, item in
                    VStack(spacing: 6) {
                        Text(names[i]).font(.caption.weight(.semibold)).foregroundStyle(Color.meta)
                        Text("\(item.day.day)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(item.wrote ? .white : (item.day > today ? Color(.tertiaryLabel) : Color.meta))
                            .frame(width: 36, height: 36)
                            .background(item.wrote ? AnyShapeStyle(brand) : AnyShapeStyle(Color(.tertiarySystemFill)), in: .circle)
                            .overlay {
                                if item.day == today && !item.wrote {
                                    Circle().strokeBorder(brand, lineWidth: 1.5)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(DiaryDates.short(item.day))\(item.wrote ? "，写了日记" : "")")
                }
            }
        }
        .padding(16)
        .background(Color.card, in: .rect(cornerRadius: 22))
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
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.card, lineWidth: 2))
            }
            if ids.isEmpty {
                RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)).frame(width: 40, height: 40)
            }
        }
        .task(id: store.diaries.count) {
            let recent = await Task.detached { AssetImages.recentAssets(limit: 60) }.value
            ids = Array(recent.map(\.id).filter { store.entry($0)?.isDiary != true }.prefix(3))
        }
    }
}
