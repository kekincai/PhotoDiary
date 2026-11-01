import SwiftUI
import Photos

/// 搜索：输入前按标签、地点、时间浏览；搜索框在底部。基于本地索引。
struct SearchView: View {
    enum Range: Hashable {
        case any, month, year, onThisDay, custom

        var title: String {
            switch self {
            case .any: String(localized: "全部时间", bundle: .app, locale: .app)
            case .month: String(localized: "最近 30 天", bundle: .app, locale: .app)
            case .year: String(localized: "最近一年", bundle: .app, locale: .app)
            case .onThisDay: String(localized: "那年今日", bundle: .app, locale: .app)
            case .custom: String(localized: "选择日期", bundle: .app, locale: .app)
            }
        }
    }

    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.brand) private var brand
    @State private var query = ""
    @State private var tags: [String] = []
    @State private var place: String?
    @State private var range: Range = .any
    @State private var customFrom = Calendar.diary.date(byAdding: .month, value: -3, to: .now) ?? .now
    @State private var customTo = Date.now
    @State private var showCustom = false
    @FocusState private var focused: Bool
    @Environment(\.isWide) private var wide

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var isTypingTag: Bool { trimmed.hasPrefix("#") || trimmed.hasPrefix("＃") }
    private var filterKey: [String] { tags + [place ?? "", "\(range)", "\(customFrom)", "\(customTo)"] }
    private var isFiltering: Bool { !trimmed.isEmpty || !tags.isEmpty || place != nil || range != .any }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isTypingTag {
                    tagSuggestions
                } else if !isFiltering {
                    browse
                } else {
                    filterBar
                    resultsList
                }
            }
            .padding(.bottom, 40)
            // 点空白处收起键盘。
            .background {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { focused = false }
            }
            // 换了筛选条件就从头显示，连同大标题。
            .background { ScrollToTop(trigger: filterKey) }
        }
        .scrollDismissesKeyboard(.immediately)
        // 离开搜索页（切到别的标签、点开一篇日记）时收起键盘，不让键盘留在别的页面上。
        .onChange(of: router.tab == .search && router.searchPath.isEmpty) { _, visible in
            if !visible { focused = false }
        }
        .navigationTitle("搜索")
        .toolbarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom, spacing: 0) { searchBar }
        .sensoryFeedback(.selection, trigger: [tags.count, place == nil ? 0 : 1, range == .any ? 0 : 1])
        .sheet(isPresented: $showCustom) {
            DateRangeCalendar(initial: range == .custom ? (DayStamp(customFrom), DayStamp(customTo)) : nil) { from, to in
                customFrom = from.date
                customTo = to.date
                range = .custom
            }
        }
    }

    // MARK: 输入前：标签、地点、时间

    @ViewBuilder private var browse: some View {
        if store.timeline.isEmpty {
            EmptyHint(title: "搜索日记")
        } else {
            if !store.tagCounts.isEmpty {
                groupTitle(String(localized: "标签", bundle: .app, locale: .app)).padding(.top, 16)
                FlowLayout(spacing: 8) {
                    ForEach(store.tagCounts, id: \.name) { tag in
                        Button { tags = [tag.name]; focused = false } label: { tagChip(tag.name, count: tag.count) }
                            .buttonStyle(.press)
                    }
                }
                .padding(.horizontal, 16)
            }

            let places = store.places
            if !places.isEmpty {
                groupTitle(String(localized: "地点", bundle: .app, locale: .app)).padding(.top, 28)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(places, id: \.name) { item in
                            Button { place = item.name; focused = false } label: { placeCard(item) }
                                .buttonStyle(.press)
                        }
                    }
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollIndicators(.hidden)
                .frame(height: 172)
            }

            groupTitle(String(localized: "时间", bundle: .app, locale: .app)).padding(.top, 28)
            let covers = timeCovers
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: wide ? 4 : 2), spacing: 10) {
                ForEach(timeOptions, id: \.self) { option in
                    Button {
                        focused = false
                        // 自选日期：在日历里点完“完成”才生效。
                        if option == .custom { showCustom = true } else { range = option }
                    } label: { timeTile(option, cover: covers[option]) }
                        .buttonStyle(.press)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// 那年今日没有日记时不列出来。
    private var timeOptions: [Range] {
        store.onThisDay.isEmpty ? [.month, .year, .custom] : [.onThisDay, .month, .year, .custom]
    }

    private func entries(in option: Range) -> [DiaryEntry] {
        option == .onThisDay ? store.onThisDay : store.search(text: "", tags: [], range: dateRange(option))
    }

    /// 每块时间卡片的照片：这段时间里最近的一篇，已被前面卡片用掉的跳过，免得几块一样。
    private var timeCovers: [Range: String] {
        var used: Set<String> = []
        var out: [Range: String] = [:]
        for option in timeOptions where option != .custom {
            let items = entries(in: option)
            if let pick = items.first(where: { !used.contains($0.id) }) ?? items.first {
                out[option] = pick.id
                used.insert(pick.id)
            }
        }
        return out
    }

    /// 时间范围也用照片表示，和地点卡片一样压白字。自选日期没有照片，是一块灰底加本月的小日历。
    private func timeTile(_ option: Range, cover: String?) -> some View {
        let items = option == .custom ? [] : entries(in: option)
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous)
        return Color.tile
            .frame(height: 96)
            .overlay {
                if let cover {
                    AssetImage(id: cover, pointSize: CGSize(width: 220, height: 96))
                    LinearGradient(colors: [.black.opacity(0), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                }
            }
            .overlay(alignment: .topLeading) {
                if option == .custom {
                    MiniMonth().padding(12)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    if !items.isEmpty {
                        Text("\(items.count) 篇")
                            .font(.caption.weight(.medium))
                            .opacity(0.85)
                    }
                }
                .foregroundStyle(cover == nil ? Color.ink : .white)
                .padding(12)
            }
            .clipShape(shape)
            .contentShape(shape)
            .accessibilityElement(children: .combine)
    }

    private func groupTitle(_ title: String) -> some View {
        SectionTitle(title: title)
            .padding(.horizontal, Metrics.text)
            .padding(.bottom, 14)
    }

    private func tagChip(_ name: String, count: Int) -> some View {
        Chip(fill: brand.soft()) {
            Text(verbatim: "#\(name)#")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(brand)
            Text("\(count)")
                .font(.footnote.weight(.medium).monospacedDigit())
                .foregroundStyle(brand.opacity(0.7))
        }
    }

    private func placeCard(_ item: DiaryStore.PlaceGroup) -> some View {
        AssetImage(id: item.cover, pointSize: CGSize(width: 140, height: 172))
            .frame(width: 140, height: 172)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 103)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(item.count) 篇")
                        .font(.caption.weight(.medium))
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
    }

    // MARK: 输入 # 时：标签联想

    private var tagSuggestions: some View {
        let q = String(trimmed.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "#＃"))
        let matches = store.tagCounts.filter { q.isEmpty || $0.name.localizedStandardContains(q) }
        return FlowLayout(spacing: 8) {
            ForEach(matches, id: \.name) { tag in
                Button {
                    if !tags.contains(tag.name) { tags.append(tag.name) }
                    query = ""
                    focused = false
                } label: { tagChip(tag.name, count: tag.count) }
                    .buttonStyle(.press)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: 结果

    private var results: [DiaryEntry] {
        var out = store.search(text: query, tags: tags, range: dateRange)
        if range == .onThisDay {
            let ids = Set(store.onThisDay.map(\.id))
            out = out.filter { ids.contains($0.id) }
        }
        if let place { out = out.filter { $0.placeName == place } }
        return out
    }

    /// 结果按月分组，月份标题和日记页一样。
    @ViewBuilder private var resultsList: some View {
        let results = self.results
        if results.isEmpty {
            // 不用系统的 ContentUnavailableView.search：它的文字跟系统语言，App 内切换语言时不会变。
            EmptyHint(title: "没有找到")
        } else {
            ForEach(Array(months(of: results).enumerated()), id: \.element.start) { index, month in
                MonthHeading(date: month.start, count: month.entries.count)
                    .padding(.horizontal, Metrics.text)
                    .padding(.top, index == 0 ? 16 : 20)
                ForEach(month.entries) { entry in
                    NavigationLink(value: Route.entry(entry.id)) {
                        EntryRow(entry: entry, showsSeparator: entry.id != month.entries.last?.id)
                    }
                    .buttonStyle(.row())
                    .entryContextMenu(entry)
                }
            }
        }
    }

    private func months(of entries: [DiaryEntry]) -> [(start: Date, entries: [DiaryEntry])] {
        let cal = Calendar.diary
        var out: [(start: Date, entries: [DiaryEntry])] = []
        for entry in entries {
            let start = cal.dateInterval(of: .month, for: entry.day.date)?.start ?? entry.day.date
            if out.last?.start == start { out[out.count - 1].entries.append(entry) } else { out.append((start, [entry])) }
        }
        return out
    }

    /// 已选的筛选条件：主题色实心胶囊，右边一个圆形 ✕ 去掉；日期点一下回到日历改。
    /// 还没选日期时，末尾多一个日历按钮，直接加日期。
    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    FilterToken(label: "#\(tag)#") { tags.removeAll { $0 == tag } }
                }
                if let place {
                    FilterToken(label: place, symbol: "mappin.and.ellipse") { self.place = nil }
                }
                if range != .any {
                    FilterToken(label: range == .custom ? customRangeTitle : range.title, symbol: "calendar",
                                edit: { focused = false; showCustom = true }) { range = .any }
                } else {
                    Button { focused = false; showCustom = true } label: {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.ink)
                            .frame(width: 46, height: 38)
                            .background(Color.tile, in: .capsule)
                    }
                    .buttonStyle(.press)
                    .accessibilityLabel(Text(Range.custom.title))
                }
            }
            .padding(.vertical, 10)
        }
        .contentMargins(.horizontal, Metrics.page, for: .scrollContent)
        .scrollIndicators(.hidden)
    }

    private var customRangeTitle: String {
        DiaryDates.range(DayStamp(min(customFrom, customTo)), DayStamp(max(customFrom, customTo)))
    }

    private var dateRange: ClosedRange<Date>? { dateRange(range) }

    private func dateRange(_ range: Range) -> ClosedRange<Date>? {
        let cal = Calendar.diary
        switch range {
        case .any, .onThisDay: return nil
        case .month: return (cal.date(byAdding: .day, value: -30, to: .now) ?? .now)...Date.now
        case .year: return (cal.date(byAdding: .year, value: -1, to: .now) ?? .now)...Date.now
        case .custom:
            let from = cal.startOfDay(for: min(customFrom, customTo))
            let to = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: max(customFrom, customTo)))!.addingTimeInterval(-1)
            return from...to
        }
    }

    // MARK: 底部：回到日记 + 玻璃搜索框

    private var searchBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                // iPad 有系统标签栏，不需要“回到日记”。
                if !wide {
                    Button { router.tab = .journal } label: {
                        Image(systemName: AppTab.journal.symbol)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.ink)
                            .frame(width: 54, height: 54)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.press)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("回到日记")
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.inkSecondary)
                    TextField("日记内容、地点、#标签#", text: $query)
                        .font(.body)
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit(submit)
                    if !query.isEmpty {
                        // 清除只清空文字，键盘保留，方便接着输入（系统搜索框的做法）。
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color(.tertiaryLabel))
                                .frame(width: 44, height: 44)
                                .contentShape(.rect)
                        }
                        .padding(.trailing, -12)
                        .accessibilityLabel("清除")
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
                .glassEffect(.regular.interactive(), in: .capsule)
                .onTapGesture { focused = true }
            }
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            BottomFade(height: 140).ignoresSafeArea(edges: .bottom)
        }
    }

    /// 输入 “#旅行#” 或 “#旅行” 后回车：变成标签筛选。
    private func submit() {
        guard isTypingTag else { return }
        let name = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#＃ "))
        if let tag = store.allTags.first(where: { $0 == name }) ?? store.allTags.first(where: { $0.localizedStandardContains(name) }) {
            if !tags.contains(tag) { tags.append(tag) }
            query = ""
        }
    }
}

/// 触发值一变就把所在的滚动视图滚回最顶上，连同大标题。
/// SwiftUI 的 scrollTo 只能到内容顶端（停在收起的导航栏下面，而且这台设备上收起后不显示小标题），
/// 所以借 UIKit 直接设偏移。
private struct ScrollToTop: UIViewRepresentable {
    let trigger: [String]

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        context.coordinator.last = trigger
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard context.coordinator.last != trigger else { return }
        context.coordinator.last = trigger
        DispatchQueue.main.async {
            var ancestor: UIView? = view
            while let current = ancestor, !(current is UIScrollView) { ancestor = current.superview }
            guard let scroll = ancestor as? UIScrollView else { return }
            // 先越过顶端一点，导航栏才会展开成大标题（内容边距随之变大）；下一轮再贴回新的顶端。
            scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top - 80), animated: false)
            DispatchQueue.main.async {
                scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var last: [String]? }
}

/// 一个已选的筛选条件。整颗胶囊是主题色（选中态），✕ 是独立的按钮，点得准，也一眼看得出能去掉。
private struct FilterToken: View {
    let label: String
    var symbol: String?
    var edit: (() -> Void)?
    let remove: () -> Void
    @Environment(\.brand) private var brand

    var body: some View {
        HStack(spacing: 0) {
            if let edit {
                Button(action: edit) { content }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("选择日期"))
            } else {
                content
            }
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(brand)
                    .frame(width: 24, height: 24)
                    .background(.white, in: .circle)
                    .frame(width: 38, height: 38)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("去掉“\(label)”"))
        }
        .foregroundStyle(.white)
        .background(brand, in: .capsule)
        .padding(.trailing, 2)
    }

    private var content: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            }
            Text(verbatim: label)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .frame(height: 38)
        .contentShape(.rect)
    }
}

/// “选择日期”卡片上的本月小日历：写过的日子是实心点，今天是主题色，和日记的日历一个意思。
private struct MiniMonth: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.brand) private var brand

    var body: some View {
        let cal = Calendar.diary
        let first = cal.dateInterval(of: .month, for: .now)?.start ?? .now
        let leading = cal.component(.weekday, from: first) - 1
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let today = DayStamp.today
        let cells: [DayStamp?] = Array(repeating: nil, count: leading)
            + (0..<count).map { DayStamp(cal.date(byAdding: .day, value: $0, to: first)!) }
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(0..<(cells.count + 6) / 7, id: \.self) { row in
                GridRow {
                    ForEach(0..<7, id: \.self) { col in
                        let i = row * 7 + col
                        let day = i < cells.count ? cells[i] : nil
                        Circle()
                            .fill(color(day, today: today))
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func color(_ day: DayStamp?, today: DayStamp) -> Color {
        guard let day else { return .clear }
        if day == today { return brand }
        return store.entries(on: day).isEmpty ? Color.meta.opacity(0.25) : Color.inkSecondary
    }
}
