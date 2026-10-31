import SwiftUI
import Photos
import MapKit

// MARK: 列表

/// 按月分组的时间线；顶部“那年今日”提示。
struct ListContent: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.zoomNamespace) private var namespace

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if store.isLimited { LimitedAccessBanner() }
            if let memory = store.onThisDay.first {
                OnThisDayBanner(entry: memory)
            }
            if store.timeline.isEmpty {
                emptyState
            }
            ForEach(months, id: \.key) { month in
                MonthHeading(date: month.entries[0].displayDate, count: month.entries.count)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 2)
                ForEach(month.entries) { entry in
                    NavigationLink(value: Route.entry(entry.id)) {
                        EntryRow(entry: entry, showsSeparator: entry.id != month.entries.last?.id, namespace: namespace)
                    }
                    .buttonStyle(.row())
                }
            }
        }
        .padding(.bottom, 120)
    }

    private var months: [(key: String, entries: [DiaryEntry])] {
        var out: [(key: String, entries: [DiaryEntry])] = []
        for entry in store.timeline {
            let key = "\(entry.day.year)-\(entry.day.month)"
            if out.last?.key == key { out[out.count - 1].entries.append(entry) }
            else { out.append((key, [entry])) }
        }
        return out
    }

    @ViewBuilder private var emptyState: some View {
        if !store.hasSynced && store.timeline.isEmpty {
            EmptyHint(title: "正在读取照片说明", message: "照片多的话需要一会儿，读到的会先显示出来。")
        } else {
            EmptyHint(title: "还没有写过说明的照片",
                      message: "选一张照片，把当时的感受写进它的说明里。",
                      action: ("从照片开始", { router.showAddFromPhotos = true }))
        }
    }
}

/// 月份标题：“10月”加粗，年份和篇数退后一层。
struct MonthHeading: View {
    let date: Date
    var count: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(DateFormatter.zh("M月").string(from: date))
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.ink)
            Text(DateFormatter.zh("yyyy").string(from: date))
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

private struct OnThisDayBanner: View {
    let entry: DiaryEntry
    @Environment(\.brand) private var brand

    var body: some View {
        NavigationLink(value: Route.entry(entry.id)) {
            HStack(spacing: 14) {
                AssetImage(id: entry.id, pointSize: CGSize(width: 52, height: 52))
                    .frame(width: 52, height: 52)
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(DiaryDates.yearsAgo(entry.day))的今天")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(brand)
                    Text(entry.title)
                        .font(.diary(15, relativeTo: .subheadline))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.row())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 1).padding(.horizontal, 20)
        }
    }
}

// MARK: 日历

/// 星期行：吸顶在切换条下面，所有月份共用。
struct WeekdayRow: View {
    private let names = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(names.enumerated()), id: \.offset) { i, name in
                Text(name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(i == 0 || i == 6 ? Color(.tertiaryLabel) : Color.meta)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 只列出写过日记的月份（加上本月），写过的日子铺满照片。
struct CalendarContent: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        let byDay = Dictionary(grouping: store.timeline, by: \.day)
        LazyVStack(alignment: .leading, spacing: 32) {
            ForEach(months, id: \.self) { first in
                MonthGrid(firstDay: first, entriesByDay: byDay)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 120)
    }

    private var months: [Date] {
        let cal = Calendar.diary
        let thisMonth = cal.dateInterval(of: .month, for: .now)!.start
        var seen = Set<Date>([thisMonth])
        var out = [thisMonth]
        for entry in store.timeline {
            guard let start = cal.dateInterval(of: .month, for: entry.displayDate)?.start, !seen.contains(start) else { continue }
            seen.insert(start)
            out.append(start)
        }
        return out.sorted(by: >)
    }
}

private struct MonthGrid: View {
    let firstDay: Date
    let entriesByDay: [DayStamp: [DiaryEntry]]
    @Environment(\.brand) private var brand
    @Environment(\.zoomNamespace) private var namespace

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        let cal = Calendar.diary
        let leading = cal.component(.weekday, from: firstDay) - 1
        let count = cal.range(of: .day, in: .month, for: firstDay)?.count ?? 30
        let days = (1...count).map { DayStamp(cal.date(byAdding: .day, value: $0 - 1, to: firstDay)!) }
        let total = days.reduce(0) { $0 + (entriesByDay[$1]?.count ?? 0) }

        VStack(alignment: .leading, spacing: 10) {
            MonthHeading(date: firstDay, count: total == 0 ? nil : total)
                .padding(.horizontal, 8)
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(0..<leading, id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
                ForEach(days, id: \.self) { day in
                    cell(day: day, entries: entriesByDay[day] ?? [])
                }
            }
        }
    }

    @ViewBuilder
    private func cell(day: DayStamp, entries: [DiaryEntry]) -> some View {
        let today = DayStamp.today
        if let first = entries.first {
            NavigationLink(value: entries.count == 1 ? Route.entry(first.id) : Route.day(day)) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { AssetImage(id: first.id) }
                    .clipShape(.rect(cornerRadius: 9, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        Text("\(day.day)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.45), radius: 3)
                            .padding(.leading, 6)
                            .padding(.top, 4)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if entries.count > 1 {
                            Text("\(entries.count)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .background(.black.opacity(0.4), in: .capsule)
                                .padding(4)
                        }
                    }
                    .overlay {
                        if day == today {
                            RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(brand, lineWidth: 2)
                        }
                    }
                    .modifier(TransitionSource(id: first.id, namespace: entries.count == 1 ? namespace : nil))
            }
            .buttonStyle(.press)
            .accessibilityLabel("\(DiaryDates.full(day))，\(entries.count) 篇")
        } else {
            VStack(spacing: 3) {
                Text("\(day.day)")
                    .font(.callout.weight(day == today ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(day == today ? brand : (day > today ? Color(.quaternaryLabel) : Color(.secondaryLabel)))
                Circle()
                    .fill(day == today ? brand : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityLabel(DiaryDates.full(day))
        }
    }
}

// MARK: 照片

/// 有日记的照片网格。
struct MediaGridContent: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.zoomNamespace) private var namespace
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(store.timeline) { entry in
                NavigationLink(value: Route.entry(entry.id)) {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { AssetImage(id: entry.id) }
                        .clipped()
                        .overlay(alignment: .bottomTrailing) {
                            if entry.segments.count > 1 { ParagraphBadge(count: entry.segments.count).padding(5) }
                        }
                        .overlay(alignment: .topTrailing) { MediaBadge(kind: entry.mediaKind).padding(6) }
                        .modifier(TransitionSource(id: entry.id, namespace: namespace))
                }
                .buttonStyle(.press)
                .accessibilityLabel("\(DiaryDates.dayTitle(entry.displayDate))：\(entry.title)")
            }
        }
        .padding(.bottom, 120)
        .overlay(alignment: .top) {
            if store.timeline.isEmpty {
                EmptyHint(title: "这里还是空的", message: "写过说明的照片会排在这里。")
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
                            .clipShape(.rect(cornerRadius: 9, style: .continuous))
                            .padding(3)
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
                Text("写过说明的照片里，还没有带位置的。")
                    .font(.footnote)
                    .padding(.horizontal, 14).padding(.vertical, 10)
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
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle(DiaryDates.full(day))
        .navigationBarTitleDisplayMode(.inline)
    }
}
