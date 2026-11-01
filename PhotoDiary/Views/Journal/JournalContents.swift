import SwiftUI
import Photos
import MapKit

// MARK: 列表

/// 按月分组的大照片卡片；顶部“那年今日”横幅。
struct ListContent: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.zoomNamespace) private var namespace
    @Environment(\.isWide) private var wide

    /// iPad 上卡片排成两三栏。
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 340, maximum: 520), spacing: Metrics.Spacing.xl, alignment: .top)] }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if store.isLimited {
                LimitedAccessBanner().padding(.horizontal, 16).padding(.top, 18)
            }
            // 第一次读取照片库的整个过程都显示进度；读到的日记接在下面先显示出来。
            if store.isFirstScan && !store.timeline.isEmpty {
                FirstScanView(placeholders: false)
            }
            if let memory = store.onThisDay.first {
                OnThisDayBanner(entry: memory)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }
            if store.timeline.isEmpty {
                emptyState
            }
            ForEach(Array(store.months.enumerated()), id: \.element.id) { index, month in
                MonthHeading(date: month.start, count: month.entries.count)
                    .padding(.horizontal, 20)
                    .padding(.top, index == 0 ? 26 : 4)
                    .padding(.bottom, 12)
                if wide {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.Spacing.xxl) {
                        ForEach(month.entries) { entry in card(entry) }
                    }
                    .padding(.horizontal, Metrics.page)
                    .padding(.bottom, Metrics.Spacing.xxl)
                } else {
                    ForEach(month.entries) { entry in
                        card(entry)
                            .padding(.horizontal, Metrics.page)
                            .padding(.bottom, Metrics.Spacing.xxl)
                    }
                }
            }
        }
    }

    private func card(_ entry: DiaryEntry) -> some View {
        NavigationLink(value: Route.entry(entry.id)) {
            EntryCard(entry: entry, namespace: namespace)
        }
        .buttonStyle(.press)
        .entryContextMenu(entry)
    }

    @ViewBuilder private var emptyState: some View {
        if !store.hasSynced && store.timeline.isEmpty {
            FirstScanView()
        } else {
            EmptyHint(title: "还没有写过说明的照片",
                      message: "选一张照片，把当时的感受写进它的说明里",
                      action: ("从照片开始", { router.showAddFromPhotos = true }))
        }
    }
}

/// 第一次读取照片库时：进度卡片 + 闪动的占位卡片，读到的日记会直接替换掉占位。
struct FirstScanView: View {
    var placeholders = true
    @Environment(DiaryStore.self) private var store
    @Environment(\.brand) private var brand

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            progressCard
            if placeholders {
                ForEach(0..<2, id: \.self) { _ in PlaceholderCard() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var progress: (done: Int, total: Int)? {
        if case .scanning(let done, let total) = store.syncState, total > 0 { return (done, total) }
        return nil
    }

    private var progressCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(brand)
                .frame(width: 44, height: 44)
                .background(brand.soft(), in: .rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("正在读取照片说明")
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                Group {
                    if let progress {
                        Text("已读 \(progress.done) / \(progress.total) 张 · 找到 \(store.timeline.count) 篇")
                    } else {
                        Text("正在打开照片库…")
                    }
                }
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Color.meta)
                .contentTransition(.numericText())
                .animation(.snappy, value: progress?.done)
                ProgressView(value: progress.map { Double($0.done) / Double($0.total) } ?? 0)
                    .tint(brand)
                    .padding(.top, 4)
                    .animation(.snappy, value: progress?.done)
                Text("第一次打开要读一遍照片库，之后只读有变化的照片。读到的日记会先显示出来。")
                    .font(.caption)
                    .foregroundStyle(Color.meta)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color.tile, in: .rect(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// 和 EntryCard 一样的形状，灰块加闪光。
private struct PlaceholderCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .aspectRatio(4 / 3, contentMode: .fit)
            Group {
                Capsule().frame(width: 150, height: 11)
                Capsule().frame(maxWidth: 260).frame(height: 18)
                Capsule().frame(maxWidth: .infinity).frame(height: 13)
                Capsule().frame(maxWidth: 220).frame(height: 13)
            }
            .padding(.horizontal, 4)
        }
        .foregroundStyle(Color.tile)
        .shimmer()
        .accessibilityHidden(true)
    }
}

/// 月份标题：“10月”半粗，年份和篇数退后一层。
struct MonthHeading: View {
    let date: Date
    var count: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(DiaryDates.monthName(date))
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.ink)
            Text(DiaryDates.year(date))
                .font(.subheadline)
                .foregroundStyle(Color.meta)
            Spacer(minLength: 0)
            if let count {
                Text("\(count) 篇")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Color.meta)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 灰底小卡片：缩略图、“1 年前的今天”、宋体一行。
private struct OnThisDayBanner: View {
    let entry: DiaryEntry
    @Environment(\.brand) private var brand

    var body: some View {
        NavigationLink(value: Route.entry(entry.id)) {
            HStack(spacing: 12) {
                AssetImage(id: entry.id, pointSize: CGSize(width: 48, height: 48))
                    .frame(width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(DiaryDates.onThisDay(entry.day))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(brand)
                    Text(entry.title)
                        .font(.diary(15, relativeTo: .subheadline))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .padding(.vertical, 8)
            .background(Color.tile, in: .rect(cornerRadius: 16, style: .continuous))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.press)
    }
}

// MARK: 日历

/// 星期行：吸顶，下方一条细线，所有月份共用。
struct WeekdayHeader: View {
    var body: some View {
        let names = DiaryDates.weekdaySymbols
        HStack(spacing: 2) {
            ForEach(Array(names.enumerated()), id: \.offset) { i, name in
                Text(name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(i == 0 || i == 6 ? Color(.tertiaryLabel) : Color.meta)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(.separator)).frame(height: 0.5)
        }
        .accessibilityHidden(true)
    }
}

/// 只列出写过日记的月份（加上本月），写过的日子铺满照片。
struct CalendarContent: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        let today = DayStamp.today
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(store.calendarMonths.enumerated()), id: \.element) { index, first in
                MonthGrid(firstDay: first, today: today)
                    .padding(.top, index == 0 ? 20 : 30)
            }
        }
        // iPad 上日历不铺满整屏，格子太大反而难看。
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }
}

private struct MonthGrid: View {
    let firstDay: Date
    let today: DayStamp
    @Environment(DiaryStore.self) private var store
    @Environment(\.brand) private var brand
    @Environment(\.zoomNamespace) private var namespace

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        let cal = Calendar.diary
        let leading = cal.component(.weekday, from: firstDay) - 1
        let count = cal.range(of: .day, in: .month, for: firstDay)?.count ?? 30
        let days = (1...count).map { DayStamp(cal.date(byAdding: .day, value: $0 - 1, to: firstDay)!) }
        let total = days.reduce(0) { $0 + store.entries(on: $1).count }

        VStack(alignment: .leading, spacing: 12) {
            MonthHeading(date: firstDay, count: total == 0 ? nil : total)
                .padding(.horizontal, 16)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<leading, id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
                ForEach(days, id: \.self) { day in
                    cell(day: day, entries: store.entries(on: day))
                }
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func cell(day: DayStamp, entries: [DiaryEntry]) -> some View {
        if let first = entries.first {
            NavigationLink(value: entries.count == 1 ? Route.entry(first.id) : Route.day(day)) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { AssetImage(id: first.id) }
                    .clipShape(.rect(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        Text("\(day.day)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.55), radius: 4)
                            .padding(.leading, 4)
                            .padding(.top, 4)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if entries.count > 1 {
                            Text("\(entries.count)")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .background(.black.opacity(0.4), in: .capsule)
                                .padding(4)
                        }
                    }
                    .overlay {
                        if day == today {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(brand, lineWidth: 2)
                        }
                    }
                    .modifier(TransitionSource(id: first.id, namespace: entries.count == 1 ? namespace : nil, cornerRadius: 8))
            }
            .buttonStyle(.press)
            .modifier(OptionalEntryMenu(entry: entries.count == 1 ? first : nil))
            .accessibilityLabel("\(DiaryDates.full(day))，\(entries.count) 篇")
        } else if day == today {
            Text("\(day.day)")
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(brand, in: .circle)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .accessibilityLabel("今天，\(DiaryDates.full(day))")
        } else {
            Text("\(day.day)")
                .font(.body.monospacedDigit())
                .foregroundStyle(day > today ? Color(.tertiaryLabel) : Color.inkSecondary)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .accessibilityLabel(DiaryDates.full(day))
        }
    }
}

// MARK: 照片

/// 有日记的照片网格：3 列贴边。
struct MediaGridContent: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.zoomNamespace) private var namespace
    @Environment(\.isWide) private var wide
    /// iPhone 3 列；iPad 按宽度自适应，格子 150pt 左右。
    private var columns: [GridItem] {
        wide ? [GridItem(.adaptive(minimum: 150), spacing: 2)] : Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(store.timeline) { entry in
                NavigationLink(value: Route.entry(entry.id)) {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { AssetImage(id: entry.id) }
                        .clipped()
                        .overlay(alignment: .bottomTrailing) {
                            if entry.segments.count > 1 { ParagraphBadge(count: entry.segments.count, compact: true).padding(6) }
                        }
                        .overlay(alignment: .topTrailing) { MediaBadge(kind: entry.mediaKind).padding(6) }
                        .modifier(TransitionSource(id: entry.id, namespace: namespace, cornerRadius: 0))
                }
                .buttonStyle(.press)
                .entryContextMenu(entry)
                .accessibilityLabel("\(DiaryDates.dayTitle(entry.displayDate))：\(entry.title)")
            }
        }
    }
}

// MARK: 地图

/// 按照片自带位置显示有日记的照片。
struct MapContent: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let located = store.timeline.filter { $0.coordinate != nil }
        Map(initialPosition: .automatic) {
            ForEach(located) { entry in
                Annotation(entry.title, coordinate: entry.coordinate!, anchor: .bottom) {
                    Button { router.push(.entry(entry.id)) } label: {
                        AssetImage(id: entry.id, pointSize: CGSize(width: 46, height: 46))
                            .frame(width: 46, height: 46)
                            .clipShape(.rect(cornerRadius: 8, style: .continuous))
                            .padding(4)
                            .background(.white, in: .rect(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    }
                    .buttonStyle(.press)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapControls { MapCompass(); MapScaleView() }
        .overlay {
            if located.isEmpty {
                Text("写过说明的照片里，还没有带位置的")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
            }
        }
    }
}

// MARK: 某一天

struct DayEntriesView: View {
    let day: DayStamp
    @Environment(DiaryStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let entries = store.entries(on: day)
                ForEach(entries) { entry in
                    NavigationLink(value: Route.entry(entry.id)) {
                        EntryRow(entry: entry, showsSeparator: entry.id != entries.last?.id)
                    }
                    .buttonStyle(.row())
                    .entryContextMenu(entry)
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle(DiaryDates.full(day))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 日历格子只有一篇日记时才挂上下文菜单；多篇时点进去是当天的列表。
private struct OptionalEntryMenu: ViewModifier {
    let entry: DiaryEntry?
    func body(content: Content) -> some View {
        if let entry { content.entryContextMenu(entry) } else { content }
    }
}
