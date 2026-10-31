import SwiftUI
import Photos

/// 搜索：输入前按标签、地点、时间浏览；搜索框在底部。基于本地索引。
struct SearchView: View {
    enum Range: Hashable {
        case any, month, year, onThisDay, custom

        var title: String {
            switch self {
            case .any: String(localized: "全部时间")
            case .month: String(localized: "最近 30 天")
            case .year: String(localized: "最近一年")
            case .onThisDay: String(localized: "那年今日")
            case .custom: String(localized: "选择日期…")
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

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var isTypingTag: Bool { trimmed.hasPrefix("#") || trimmed.hasPrefix("＃") }
    private var isFiltering: Bool { !trimmed.isEmpty || !tags.isEmpty || place != nil || range != .any }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isTypingTag {
                    tagSuggestions
                } else if !isFiltering {
                    browse
                } else {
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
        }
        .scrollDismissesKeyboard(.immediately)
        // 离开搜索页（切到别的标签、点开一篇日记）时收起键盘，不让键盘留在别的页面上。
        .onChange(of: router.tab == .search && router.searchPath.isEmpty) { _, visible in
            if !visible { focused = false }
        }
        .navigationTitle("搜索")
        .toolbarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom, spacing: 0) { searchBar }
        .sheet(isPresented: $showCustom) { customRangeSheet }
    }

    // MARK: 输入前：标签、地点、时间

    @ViewBuilder private var browse: some View {
        if store.timeline.isEmpty {
            EmptyHint(title: "搜索日记", message: "可以搜正文和地点，输入 # 按标签筛选")
        } else {
            if !store.tagCounts.isEmpty {
                groupTitle("标签").padding(.top, 16)
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
                groupTitle("地点").padding(.top, 28)
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

            groupTitle("时间").padding(.top, 28)
            FlowLayout(spacing: 8) {
                ForEach([Range.month, .year, .onThisDay, .custom], id: \.self) { option in
                    Button {
                        range = option
                        focused = false
                        if option == .custom { showCustom = true }
                    } label: {
                        Chip { Text(option.title) }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.ink)
                    }
                    .buttonStyle(.press)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func groupTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .accessibilityAddTraits(.isHeader)
    }

    private func tagChip(_ name: String, count: Int) -> some View {
        Chip {
            Text(verbatim: "#\(name)#")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(brand)
            Text("\(count)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Color.meta)
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

    @ViewBuilder private var resultsList: some View {
        let results = self.results
        activeFilters
        if results.isEmpty {
            ContentUnavailableView.search(text: trimmed)
                .padding(.top, 40)
        } else {
            Text("\(results.count) 篇")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.meta)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)
            ForEach(results) { entry in
                NavigationLink(value: Route.entry(entry.id)) {
                    EntryRow(entry: entry, showsSeparator: entry.id != results.last?.id)
                }
                .buttonStyle(.row())
            }
        }
    }

    /// 已选的筛选条件，点一下去掉。
    @ViewBuilder private var activeFilters: some View {
        if !tags.isEmpty || place != nil || range != .any {
            FlowLayout(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    removable(fill: brand.soft(), color: brand) { Text(verbatim: "#\(tag)#") } remove: {
                        tags.removeAll { $0 == tag }
                    }
                }
                if let place {
                    removable(fill: .tile, color: .ink) {
                        Label(place, systemImage: "mappin")
                    } remove: { self.place = nil }
                }
                if range != .any {
                    removable(fill: .tile, color: .ink) {
                        Text(range == .custom ? customRangeTitle : range.title)
                    } remove: { range = .any }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    private func removable<Content: View>(fill: Color, color: Color, @ViewBuilder content: () -> Content,
                                          remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            Chip(height: 34, fill: fill) {
                content()
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).opacity(0.6)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
        }
        .buttonStyle(.press)
    }

    private var customRangeTitle: String {
        let from = DayStamp(min(customFrom, customTo)), to = DayStamp(max(customFrom, customTo))
        return from == to ? DiaryDates.full(from) : "\(DiaryDates.full(from)) – \(DiaryDates.full(to))"
    }

    private var dateRange: ClosedRange<Date>? {
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
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
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

    private var customRangeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("从", selection: $customFrom, displayedComponents: .date)
                DatePicker("到", selection: $customTo, displayedComponents: .date)
            }
            .navigationTitle("日期范围")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", systemImage: "checkmark") { showCustom = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// 自动换行排列的标签。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > width, !rows[rows.count - 1].indices.isEmpty {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            rows[rows.count - 1].indices.append(i)
            rows[rows.count - 1].width += size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
