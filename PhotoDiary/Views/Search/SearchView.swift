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
    @Environment(Intelligence.self) private var intelligence
    @Environment(\.brand) private var brand
    @State private var query = ""
    /// 模型从输入的句子里拆出来的条件（“去年夏天在海边” → 日期 + 关键词）。
    @State private var intent: SearchFilter?
    @State private var tags: [String] = []
    @State private var place: String?
    @State private var range: Range = .any
    @State private var customFrom = Calendar.diary.date(byAdding: .month, value: -3, to: .now) ?? .now
    @State private var customTo = Date.now
    @State private var showCustom = false
    /// 有筛选条件时往下拉：拉过这个距离松手就清掉所有条件。
    @State private var pull: CGFloat = 0
    @State private var armed = false
    @State private var phase: ScrollPhase = .idle
    private static let clearPull: CGFloat = 96
    @FocusState private var focused: Bool
    @Environment(\.isWide) private var wide
    @Environment(\.assistiveTechnology) private var assistive

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
                    browse.transition(.opacity)
                } else {
                    Group {
                        filterBar
                        resultsList
                    }
                    .transition(.opacity)
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
        // 有筛选条件时，往下拉到底再松手就清掉：一枚光圈随着下拉收拢，拉够了合上、变成主题色。
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            max(0, -(geo.contentOffset.y + geo.contentInsets.top))
        } action: { _, amount in
            guard isFiltering, phase == .interacting || phase == .decelerating else { pull = 0; return }
            pull = amount
            let nowArmed = phase == .interacting && amount > Self.clearPull
            if nowArmed != armed { withAnimation(.snappy) { armed = nowArmed } }
        }
        .onScrollPhaseChange { _, newPhase in
            phase = newPhase
            if newPhase != .interacting, armed { clearFilters() }
            if newPhase == .idle { pull = 0 }
        }
        .overlay(alignment: .top) {
            if isFiltering {
                PullToClear(progress: pull / Self.clearPull, armed: armed)
                    .offset(y: pull / 2 - 20)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: armed) { _, new in new }
        // 离开搜索页（切到别的标签、点开一篇日记）时收起键盘，不让键盘留在别的页面上。
        .onChange(of: router.tab == .search && router.searchPath.isEmpty) { _, visible in
            if !visible { focused = false }
        }
        // 快捷指令带着文字打开：换成这段文字，其他条件清掉。
        .onChange(of: router.searchRequest, initial: true) { _, request in
            guard let request else { return }
            router.searchRequest = nil
            tags = []
            place = nil
            range = .any
            query = request
        }
        .navigationTitle("搜索")
        .toolbarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom, spacing: 0) { searchBar }
        // 停下来半秒再问模型；字面匹配的结果先出来，模型拆出来的条件到了再并进去。
        .task(id: trimmed) {
            let text = trimmed
            guard intelligence.isEnabled, !isTypingTag, text.count >= 2 else {
                if intent != nil { withAnimation(.snappy) { intent = nil } }
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let context = SearchContext(today: .today, tags: store.allTags, places: store.places.map(\.name),
                                        language: Intelligence.languageName)
            let result = await intelligence.engine.interpret(text, context: context)?.resolved(in: context)
            guard !Task.isCancelled, text == trimmed else { return }
            withAnimation(.snappy) { intent = result }
        }
        .sensoryFeedback(.selection, trigger: [tags.count, place == nil ? 0 : 1, range == .any ? 0 : 1])
        .sheet(isPresented: $showCustom) {
            DateRangeCalendar(initial: range == .custom ? (DayStamp(customFrom), DayStamp(customTo)) : nil) { from, to in
                customFrom = from.date
                customTo = to.date
                range = .custom
            }
        }
    }

    /// 下拉到底松手：所有筛选条件一起淡出，回到浏览。
    private func clearFilters() {
        armed = false
        focused = false
        withAnimation(.snappy) {
            tags = []
            place = nil
            range = .any
            query = ""
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
                        ForEach(Array(places.enumerated()), id: \.element.name) { index, item in
                            Button { place = item.name; focused = false } label: { placeCard(item, stagger: index) }
                                .buttonStyle(.press)
                        }
                    }
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollIndicators(.hidden)
                .frame(height: 172)
            }

            groupTitle(String(localized: "时间", bundle: .app, locale: .app)).padding(.top, 28)
            let pools = timePools
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: wide ? 4 : 2), spacing: 10) {
                ForEach(Array(timeOptions.enumerated()), id: \.element) { index, option in
                    Button {
                        focused = false
                        // 自选日期：在日历里点完“完成”才生效。
                        if option == .custom { showCustom = true } else { range = option }
                    } label: { timeTile(option, pool: pools[option] ?? [], stagger: index) }
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

    /// 每块时间卡片轮换的照片。几块尽量不放同一批：最近一年去掉最近 30 天里的，
    /// “选择日期”用一年以前的；哪块没得挑了就用这段时间里的全部。每块最多轮 12 张，
    /// 从早到晚排——地点卡片是从最近一张起，这样两排不会同时翻到同一张。
    private var timePools: [Range: [String]] {
        let month = entries(in: .month).map(\.id)
        let year = entries(in: .year).map(\.id)
        let all = store.timeline.map(\.id)
        let monthSet = Set(month)
        let yearSet = Set(year)
        let yearOnly = year.filter { !monthSet.contains($0) }
        let older = all.filter { !yearSet.contains($0) }
        func pool(_ ids: [String]) -> [String] { Array(ids.prefix(12).reversed()) }
        return [
            .onThisDay: pool(store.onThisDay.map(\.id)),
            .month: pool(month),
            .year: pool(yearOnly.isEmpty ? year : yearOnly),
            .custom: pool(older.isEmpty ? all : older),
        ]
    }

    /// 时间范围也用照片表示，和地点卡片一样压白字；封面在这段时间的照片里慢慢轮换。
    /// “选择日期”同样是一块照片，标题前多一个日历符号。
    private func timeTile(_ option: Range, pool: [String], stagger: Int) -> some View {
        let count = option == .custom ? 0 : entries(in: option).count
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous)
        return Color.tile
            .frame(height: 96)
            .overlay {
                if !pool.isEmpty {
                    RotatingCover(ids: pool, pointSize: CGSize(width: 220, height: 96), stagger: .seconds(2.3 * Double(stagger)))
                    LinearGradient(colors: [.black.opacity(0), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if option == .custom {
                            Image(systemName: "calendar").font(.subheadline.weight(.semibold))
                        }
                        Text(option.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                    }
                    if count > 0 {
                        Text("\(count) 篇")
                            .font(.caption.weight(.medium))
                            .opacity(0.85)
                    }
                }
                .foregroundStyle(pool.isEmpty ? Color.ink : .white)
                .padding(12)
            }
            .clipShape(shape)
            .contentShape(shape)
            // 固定高度的照片块：字号封顶，读不清的靠 VoiceOver 和大字查看。
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brand)
            Text("\(count)")
                .font(.footnote.weight(.medium).monospacedDigit())
                .foregroundStyle(brand.opacity(0.7))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Spoken.tag(name))，\(count) 篇"))
    }

    /// 地点卡片：封面在这个地点的照片里慢慢轮换，各张卡片错开起步。
    private func placeCard(_ item: DiaryStore.PlaceGroup, stagger: Int) -> some View {
        let pool = Array(store.entries(at: item.name).prefix(12).map(\.id))
        return RotatingCover(ids: pool.isEmpty ? [item.cover] : pool, pointSize: CGSize(width: 140, height: 172),
                             stagger: .seconds(1.7 * Double(stagger) + 1))
            .frame(width: 140, height: 172)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 103)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.callout.weight(.semibold))
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
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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

    /// 模型拆出来、而且还没被采纳成正式条件的部分。采纳过的（标签已选、地点已选、日期已选）不再重复显示。
    private var visibleIntent: SearchFilter? {
        guard var intent else { return nil }
        intent.tags.removeAll(where: tags.contains)
        if place != nil || intent.place == place { intent.place = nil }
        if range != .any { intent.days = nil }
        intent.keywords.removeAll { $0.compare(trimmed, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame }
        return intent.isEmpty ? nil : intent
    }

    private var results: [DiaryEntry] {
        var out = store.search(text: query, tags: tags, range: dateRange)
        if let intent = visibleIntent {
            // 模型的条件和已选条件一起查，结果并进字面匹配的结果里。
            var combined = intent
            combined.tags = (tags + intent.tags).uniqued()
            if let place { combined.place = place }
            let explicit = dateRange
            let extra = store.search(combined).filter { e in explicit.map { $0.contains(e.sortDate) } ?? true }
            let seen = Set(out.map(\.id))
            out = (out + extra.filter { !seen.contains($0.id) }).sorted { $0.sortDate > $1.sortDate }
        }
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
                    FilterToken(label: "#\(tag)#", spoken: Spoken.tag(tag)) { tags.removeAll { $0 == tag } }
                }
                if let place {
                    FilterToken(label: place, spoken: Spoken.place(place), symbol: "mappin.and.ellipse") { self.place = nil }
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
                // 模型理解出来的条件：浅色胶囊，前面一枚 Apple Intelligence 标记。点一下采纳成正式条件。
                if let intent = visibleIntent {
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.inkSecondary)
                        .padding(.leading, 4)
                        .accessibilityHidden(true)
                    ForEach(intent.tags, id: \.self) { tag in
                        IntentToken(label: "#\(tag)#", spoken: Spoken.tag(tag)) {
                            if !tags.contains(tag) { tags.append(tag) }
                        }
                    }
                    if let suggested = intent.place {
                        IntentToken(label: suggested, spoken: Spoken.place(suggested), symbol: "mappin.and.ellipse") {
                            place = suggested
                        }
                    }
                    if let days = intent.days {
                        IntentToken(label: DiaryDates.range(days.lowerBound, days.upperBound), symbol: "calendar") {
                            customFrom = days.lowerBound.date
                            customTo = days.upperBound.date
                            range = .custom
                        }
                    }
                    ForEach(intent.keywords, id: \.self) { word in
                        IntentToken(label: word) { query = word }
                    }
                }
                // 下拉清除这个手势 VoiceOver、切换控制做不了：给他们一个按钮。
                if assistive.isRunning {
                    Button("清除筛选", action: clearFilters)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, Metrics.Spacing.s)
                        .frame(minHeight: 38)
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
                    .largeContent(String(localized: "回到日记", bundle: .app, locale: .app), systemImage: AppTab.journal.symbol)
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
                .frame(minHeight: 54)
                .glassEffect(.regular.interactive(), in: .capsule)
                .onTapGesture { focused = true }
            }
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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
    /// 读给 VoiceOver 的（“标签“旅行””），不写就读 label。
    var spoken: String?
    var symbol: String?
    var edit: (() -> Void)?
    let remove: () -> Void
    @Environment(\.brand) private var brand

    var body: some View {
        HStack(spacing: 0) {
            if let edit {
                Button(action: edit) { content }
                    .buttonStyle(.plain)
                    .accessibilityLabel(spoken ?? label)
                    .accessibilityHint(Text("选择日期"))
            } else {
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spoken ?? label)
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
            .accessibilityLabel(Text("去掉“\(spoken ?? label)”"))
        }
        .foregroundStyle(.white)
        .background(brand, in: .capsule)
        .padding(.trailing, 2)
    }

    private var content: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.footnote.weight(.semibold))
            }
            Text(verbatim: label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .frame(minHeight: 38)
        .contentShape(.rect)
    }
}

/// 模型理解出来、还没采纳的条件：主题色浅底（待确认态），点一下变成正式的筛选条件。
private struct IntentToken: View {
    let label: String
    var spoken: String?
    var symbol: String?
    let accept: () -> Void
    @Environment(\.brand) private var brand

    var body: some View {
        Button(action: accept) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.footnote.weight(.semibold))
                }
                Text(verbatim: label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(brand)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(brand.soft(), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.press)
        .accessibilityLabel(spoken ?? label)
        .accessibilityHint(Text("加入筛选"))
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

/// 下拉清除筛选的提示：一枚光圈随着下拉慢慢收拢，拉够了“咔哒”合上、变成主题色；松手筛选条件就清掉了。
private struct PullToClear: View {
    let progress: CGFloat
    let armed: Bool
    @Environment(\.brand) private var brand

    var body: some View {
        let p = Double(min(max(progress, 0), 1))
        // 拉的时候最多收到八成，合上那一下留给 armed，才有“关上”的动作。
        let closure = armed ? 1 : p * 0.8
        ZStack {
            Aperture(closure: closure, color: .tile, seam: Color.ink.opacity(0.16))
            Aperture(closure: closure, color: brand, seam: .white.opacity(0.4))
                .opacity(armed ? 1 : 0)
        }
        .frame(width: 40, height: 40)
        .scaleEffect(armed ? 1.12 : 0.55 + 0.45 * p)
        .opacity(p)
        .animation(.snappy(duration: 0.35), value: armed)
    }
}
