import SwiftUI

/// 搜索的“选择日期”：和日记的日历同一套样子（星期行吸顶、写过的日子铺照片、今天是主题色圆），
/// 点一天是起点，再点一天是终点，第三下重新开始。只列写过日记的月份和本月。
struct DateRangeCalendar: View {
    /// 完成时交回起止日期（只选一天时两个相同）。
    var initial: (from: DayStamp, to: DayStamp)?
    var onDone: (DayStamp, DayStamp) -> Void

    @Environment(DiaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var start: DayStamp?
    @State private var end: DayStamp?

    init(initial: (from: DayStamp, to: DayStamp)?, onDone: @escaping (DayStamp, DayStamp) -> Void) {
        self.initial = initial
        self.onDone = onDone
        _start = State(initialValue: initial?.from)
        _end = State(initialValue: initial.flatMap { $0.from == $0.to ? nil : $0.to })
    }

    var body: some View {
        let today = DayStamp.today
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(Array(store.calendarMonths.enumerated()), id: \.element) { index, first in
                            RangeMonthGrid(firstDay: first, today: today, start: start, end: end, select: select)
                                .padding(.top, index == 0 ? 20 : 30)
                        }
                    } header: {
                        WeekdayHeader()
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline.monospacedDigit())
                        .contentTransition(.numericText())
                        .animation(.snappy, value: title)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", systemImage: "checkmark") {
                        guard let start else { return }
                        onDone(start, end ?? start)
                        dismiss()
                    }
                    .disabled(start == nil)
                }
            }
            .sensoryFeedback(.selection, trigger: [start, end])
        }
    }

    /// 标题就是选中的范围，不另写说明。
    private var title: String {
        guard let start else { return String(localized: "日期范围", bundle: .app, locale: .app) }
        return DiaryDates.range(start, end ?? start)
    }

    private func select(_ day: DayStamp) {
        withAnimation(.snappy) {
            if let s = start, end == nil, day != s {
                start = min(s, day)
                end = max(s, day)
            } else {
                start = day
                end = nil
            }
        }
    }
}

/// 一个月的格子，尺寸、圆角、字号和日记的日历（MonthGrid）一致；选中的范围铺一层主题色。
private struct RangeMonthGrid: View {
    let firstDay: Date
    let today: DayStamp
    let start: DayStamp?
    let end: DayStamp?
    let select: (DayStamp) -> Void
    @Environment(DiaryStore.self) private var store
    @Environment(\.brand) private var brand

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        let cal = Calendar.diary
        let leading = cal.leadingBlanks(before: firstDay)
        let count = cal.range(of: .day, in: .month, for: firstDay)?.count ?? 30
        let days = (1...count).map { DayStamp(cal.date(byAdding: .day, value: $0 - 1, to: firstDay)!) }
        let total = days.reduce(0) { $0 + store.entries(on: $1).count }

        VStack(alignment: .leading, spacing: 12) {
            MonthHeading(date: firstDay, count: total == 0 ? nil : total)
                .padding(.horizontal, 16)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<leading, id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit).accessibilityHidden(true) }
                ForEach(days, id: \.self) { day in
                    Button { select(day) } label: { cell(day) }
                        .buttonStyle(.press)
                        .accessibilityLabel(label(day))
                        .accessibilityValue(value(day))
                        .accessibilityAddTraits(isEndpoint(day) ? .isSelected : [])
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.horizontal, 4)
        }
    }

    private func isEndpoint(_ day: DayStamp) -> Bool { day == start || day == end }

    /// 日期，有日记时带篇数，今天前面加“今天”。
    private func label(_ day: DayStamp) -> String {
        let count = store.entries(on: day).count
        let date = DiaryDates.full(day)
        let label = count > 0 ? String(localized: "\(date)，\(count) 篇", bundle: .app, locale: .app) : date
        return day == today ? String(localized: "今天，\(label)", bundle: .app, locale: .app) : label
    }

    /// 起点 / 终点 / 在范围里：只靠颜色看得出来的，读出来。
    private func value(_ day: DayStamp) -> String {
        if day == start { return String(localized: "起点", bundle: .app, locale: .app) }
        if day == end { return String(localized: "终点", bundle: .app, locale: .app) }
        if inRange(day) { return String(localized: "在范围内", bundle: .app, locale: .app) }
        return ""
    }

    private func inRange(_ day: DayStamp) -> Bool {
        guard let start else { return false }
        guard let end else { return day == start }
        return day >= start && day <= end
    }

    private func cell(_ day: DayStamp) -> some View {
        let first = store.entries(on: day).first
        let selected = inRange(day)
        let endpoint = isEndpoint(day)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let first {
                    AssetImage(id: first.id)
                        .overlay { if selected { brand.opacity(endpoint ? 0.45 : 0.3) } }
                } else if endpoint {
                    brand
                } else if selected {
                    brand.opacity(0.15)
                }
            }
            .clipShape(shape)
            .overlay(alignment: first == nil ? .center : .topLeading) {
                if first != nil {
                    Text("\(day.day)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 4)
                        .padding(.leading, 4)
                        .padding(.top, 4)
                } else if day == today && !selected {
                    Text("\(day.day)")
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(brand, in: .circle)
                } else {
                    Text("\(day.day)")
                        .font(.body.weight(endpoint ? .semibold : .regular).monospacedDigit())
                        .foregroundStyle(endpoint ? .white : (day > today ? Color(.tertiaryLabel) : Color.inkSecondary))
                        .fixedSize()
                }
            }
            .overlay {
                if endpoint && first != nil { shape.strokeBorder(brand, lineWidth: 2.5) }
            }
            .contentShape(shape)
    }
}
