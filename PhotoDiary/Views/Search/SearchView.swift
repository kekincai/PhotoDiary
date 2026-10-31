import SwiftUI
import Photos

/// 搜索：全文 + 标签 + 日期范围，基于本地索引。
struct SearchView: View {
    enum Range: String, CaseIterable, Identifiable {
        case any = "全部时间", month = "最近 30 天", year = "最近一年", custom = "自定义…"
        var id: String { rawValue }
    }

    @Environment(DiaryStore.self) private var store
    @Environment(\.brand) private var brand
    @State private var query = ""
    @State private var tokens: [TagToken] = []
    @State private var range: Range = .any
    @State private var customFrom = Calendar.diary.date(byAdding: .month, value: -3, to: .now) ?? .now
    @State private var customTo = Date.now
    @State private var showCustom = false

    struct TagToken: Identifiable, Hashable {
        var name: String
        var id: String { name }
    }

    var body: some View {
        let results = store.search(text: query, tags: tokens.map(\.name), range: dateRange)
        let isFiltering = !query.isEmpty || !tokens.isEmpty || range != .any

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !isFiltering {
                    suggestions
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .padding(.top, 60)
                } else {
                    Text("\(results.count) 篇")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.meta)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    ForEach(results) { entry in
                        NavigationLink(value: Route.entry(entry.id)) {
                            EntryRow(entry: entry, showsSeparator: entry.id != results.last?.id)
                        }
                        .buttonStyle(.row())
                    }
                }
            }
            .padding(.bottom, 130)
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("搜索")
        .searchable(text: $query, tokens: $tokens, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "日记内容、地点、#标签#") { token in
            Text("#\(token.name)#")
        }
        .searchSuggestions {
            if query.hasPrefix("#") || query.hasPrefix("＃") {
                let q = String(query.dropFirst())
                ForEach(store.allTags.filter { q.isEmpty || $0.localizedStandardContains(q) }.prefix(8), id: \.self) { tag in
                    Button("#\(tag)#") {
                        tokens.append(TagToken(name: tag))
                        query = ""
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("日期范围", selection: $range) {
                        ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Label("日期范围", systemImage: range == .any ? "calendar" : "calendar.badge.checkmark")
                }
            }
        }
        .onChange(of: range) { _, new in if new == .custom { showCustom = true } }
        .sheet(isPresented: $showCustom) { customRangeSheet }
    }

    private var dateRange: ClosedRange<Date>? {
        let cal = Calendar.diary
        switch range {
        case .any: return nil
        case .month: return (cal.date(byAdding: .day, value: -30, to: .now) ?? .now)...Date.now
        case .year: return (cal.date(byAdding: .year, value: -1, to: .now) ?? .now)...Date.now
        case .custom:
            let from = cal.startOfDay(for: min(customFrom, customTo))
            let to = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: max(customFrom, customTo)))!.addingTimeInterval(-1)
            return from...to
        }
    }

    /// 还没输入时：按标签浏览。
    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.tagCounts.isEmpty {
                EmptyHint(symbol: "magnifyingglass", title: "搜索日记", message: "可以搜正文、地点，或者输入 # 按标签筛选。")
            } else {
                Text("标签")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.meta)
                FlowLayout(spacing: 8) {
                    ForEach(store.tagCounts, id: \.name) { tag in
                        Button {
                            tokens = [TagToken(name: tag.name)]
                        } label: {
                            Text("#\(tag.name)# \(Text("\(tag.count)").foregroundStyle(Color.meta))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(brand)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(brand.opacity(0.08), in: .capsule)
                        }
                        .buttonStyle(.press)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var customRangeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("从", selection: $customFrom, displayedComponents: .date)
                DatePicker("到", selection: $customTo, displayedComponents: .date)
            }
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .navigationTitle("日期范围")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showCustom = false }
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
