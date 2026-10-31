import SwiftUI
import Photos
import MapKit

// MARK: 列表

/// 按月分组的时间线；顶部“那年今日”提示。
struct ListContent: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.zoomNamespace) private var namespace

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if let memory = store.onThisDay.first {
                OnThisDayBanner(entry: memory)
            }
            if store.timeline.isEmpty {
                emptyState
            }
            ForEach(months, id: \.key) { month in
                Text(DiaryDates.monthHeader(month.entries[0].displayDate))
                    .font(.footnote.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.meta)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
                ForEach(month.entries) { entry in
                    NavigationLink(value: Route.entry(entry.id)) {
                        EntryRow(entry: entry, showsSeparator: entry.id != month.entries.last?.id, namespace: namespace)
                    }
                    .buttonStyle(.row())
                }
            }
        }
        .padding(.top, 8)
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
        if case .scanning = store.syncState {
            EmptyHint(symbol: "photo.stack", title: "正在读取照片说明", message: "第一次打开需要遍历照片库，建好的部分会先显示出来。")
        } else {
            EmptyHint(symbol: "text.below.photo", title: "还没有日记",
                      message: "点右下角的 + 选一张照片，把当时的感受写进它的说明里。")
        }
    }
}

private struct OnThisDayBanner: View {
    let entry: DiaryEntry
    @Environment(\.brand) private var brand

    var body: some View {
        NavigationLink(value: Route.entry(entry.id)) {
            HStack(spacing: 12) {
                AssetImage(id: entry.id, pointSize: CGSize(width: 44, height: 44))
                    .frame(width: 44, height: 44)
                    .clipShape(.rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("那年今日 · \(DiaryDates.yearsAgo(entry.day))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(brand)
                    Text(entry.title)
                        .font(.diary(15, relativeTo: .subheadline))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(10)
            .background(brand.opacity(0.08), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.press)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
}

// MARK: 日历

/// 按月显示，写过日记的日子显示缩略图。
struct CalendarContent: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        let byDay = Dictionary(grouping: store.timeline, by: \.day)
        LazyVStack(spacing: 28) {
            ForEach(months, id: \.self) { first in
                MonthGrid(firstDay: first, entriesByDay: byDay)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 120)
    }

    /// 从本月往前，直到最早一篇日记所在的月份（至少 12 个月）。
    private var months: [Date] {
        let cal = Calendar.diary
        let thisMonth = cal.dateInterval(of: .month, for: .now)!.start
        let earliest = store.timeline.last?.sortDate ?? thisMonth
        let span = max(11, cal.dateComponents([.month], from: earliest, to: thisMonth).month ?? 0)
        return (0...min(span, 600)).compactMap { cal.date(byAdding: .month, value: -$0, to: thisMonth) }
    }
}

private struct MonthGrid: View {
    let firstDay: Date
    let entriesByDay: [DayStamp: [DiaryEntry]]
    @Environment(\.brand) private var brand

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        let cal = Calendar.diary
        let leading = cal.component(.weekday, from: firstDay) - 1
        let count = cal.range(of: .day, in: .month, for: firstDay)?.count ?? 30
        let today = DayStamp.today

        VStack(alignment: .leading, spacing: 10) {
            Text(DateFormatter.zh("yyyy年M月").string(from: firstDay))
                .font(.title3.weight(.bold))
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdays, id: \.self) { w in
                    Text(w).font(.caption.weight(.semibold)).foregroundStyle(Color.meta)
                }
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 1) }
                ForEach(1...count, id: \.self) { d in
                    let day = DayStamp(cal.date(byAdding: .day, value: d - 1, to: firstDay)!)
                    cell(day: day, entries: entriesByDay[day] ?? [], isToday: day == today)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(day: DayStamp, entries: [DiaryEntry], isToday: Bool) -> some View {
        if let first = entries.first {
            NavigationLink(value: entries.count == 1 ? Route.entry(first.id) : Route.day(day)) {
                AssetImage(id: first.id)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(alignment: .bottomLeading) {
                        Text("\(day.day)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .padding(4)
                    }
                    .overlay {
                        if isToday { RoundedRectangle(cornerRadius: 8).strokeBorder(brand, lineWidth: 2) }
                    }
            }
            .buttonStyle(.press)
            .accessibilityLabel("\(DiaryDates.full(day))，\(entries.count) 篇日记")
        } else {
            Text("\(day.day)")
                .font(.subheadline.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? brand : Color.meta)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
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
                    AssetImage(id: entry.id)
                        .aspectRatio(1, contentMode: .fit)
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
        .padding(.top, 2)
        .padding(.bottom, 120)
        .overlay {
            if store.timeline.isEmpty {
                EmptyHint(symbol: "photo.on.rectangle", title: "还没有写过日记的照片", message: "写过日记的照片会出现在这里。")
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
                        AssetImage(id: entry.id, pointSize: CGSize(width: 48, height: 48))
                            .frame(width: 48, height: 48)
                            .clipShape(.rect(cornerRadius: 10))
                            .padding(3)
                            .background(.white, in: .rect(cornerRadius: 13))
                            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    }
                    .buttonStyle(.press)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapControls { MapCompass(); MapScaleView() }
        .clipShape(.rect(topLeadingRadius: 22, topTrailingRadius: 22))
        .overlay {
            if located.isEmpty {
                Text("日记照片里还没有带位置信息的")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
            }
        }
        .ignoresSafeArea(edges: .bottom)
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
