import SwiftUI
import Photos

/// 从照片添加：默认只列出还没写日记的照片，提醒补记当时的感受。
struct AddFromPhotosView: View {
    enum Filter: CaseIterable {
        case unwritten, all
        var title: String {
            switch self {
            case .unwritten: String(localized: "还没写", bundle: .app, locale: .app)
            case .all: String(localized: "全部照片", bundle: .app, locale: .app)
            }
        }
    }

    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var filter: Filter = .unwritten
    @State private var photos: [(id: String, date: Date?)] = []
    /// 拍摄时间，读给 VoiceOver：一格格照片只说“还没写日记的照片”分不出是哪张。
    @State private var dates: [String: Date] = [:]
    @State private var loaded = false
    /// 分组结果缓存：照片多时每次刷新都重新分组会卡。
    @State private var sections: [Section] = []
    @State private var path: [String] = []
    @Namespace private var zoom

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var columns: [GridItem] {
        sizeClass == .regular ? [GridItem(.adaptive(minimum: 120), spacing: 2)] : Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)
    }
    nonisolated static let limit = 6000

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    if store.isLimited { LimitedAccessBanner().padding(.horizontal, Metrics.page).padding(.bottom, 16) }

                    ForEach(sections, id: \.title) { section in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(section.title)
                                .font(.title3.weight(.semibold))
                            if let detail = section.detail {
                                Text(detail).font(.footnote).foregroundStyle(Color.meta)
                            }
                        }
                        .padding(.horizontal, Metrics.page)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)

                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(section.items, id: \.self) { id in
                                cell(id)
                            }
                        }
                        .padding(.bottom, 24)
                    }

                    if loaded && sections.isEmpty {
                        if filter == .unwritten {
                            EmptyHint(title: "最近的照片都写过了")
                        } else {
                            EmptyHint(title: "照片库是空的")
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, Metrics.bottomControlInset)
            }
            .overlay { if !loaded { ProgressView() } }
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    BottomFade(height: 120).ignoresSafeArea(edges: .bottom)
                    GlassSegmented(options: Filter.allCases, selection: $filter.animation(.snappy), title: \.title)
                        .padding(.bottom, 12)
                }
            }
            .navigationTitle("从照片添加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                }
            }
            .navigationDestination(for: String.self) { id in
                EditorView(assetID: id, mode: store.entry(id) == nil ? .new : .append,
                           existingCaption: store.entry(id)?.caption) { saved in
                    if saved {
                        dismiss()
                        router.showNewEntry(id)
                    } else {
                        _ = path.popLast()
                    }
                }
                .navigationTransition(.zoom(sourceID: id, in: zoom))
            }
        }
        .task {
            photos = await Task.detached(priority: .userInitiated) {
                AssetImages.recentAssets(limit: Self.limit)
            }.value
            dates = Dictionary(photos.compactMap { p in p.date.map { (p.id, $0) } }, uniquingKeysWith: { a, _ in a })
            rebuildSections()
            loaded = true
        }
        .onChange(of: filter) { rebuildSections() }
        .onChange(of: store.diaries.count) { rebuildSections() }
    }

    private func cell(_ id: String) -> some View {
        let hasDiary = store.entry(id) != nil
        return Button { path.append(id) } label: {
            AssetImage(id: id)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .bottomLeading) {
                    if hasDiary {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 10, weight: .semibold))
                            // 白底上固定用黑色：跟随深色模式的 label 会变成白字白底。
                            .foregroundStyle(.black)
                            .frame(width: 20, height: 20)
                            .background(.white.opacity(0.94), in: .circle)
                            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                            .padding(4)
                    }
                }
                .matchedTransitionSource(id: id, in: zoom)
        }
        .buttonStyle(.press)
        .accessibilityLabel(cellLabel(id, hasDiary: hasDiary))
    }

    private func cellLabel(_ id: String, hasDiary: Bool) -> Text {
        guard let date = dates[id] else { return hasDiary ? Text("已写日记的照片") : Text("还没写日记的照片") }
        let when = DiaryDates.dayAndTime(date)
        return hasDiary ? Text("已写日记的照片，\(when)") : Text("还没写日记的照片，\(when)")
    }

    // MARK: 分组：今天 / 昨天 / 本周早些时候 / 本月早些时候 / 按月

    private struct Section {
        var title: String
        var detail: String?
        var items: [String]
    }

    private func rebuildSections() {
        let cal = Calendar.diary
        let now = Date.now
        let startOfToday = cal.startOfDay(for: now)
        let startOfYesterday = cal.date(byAdding: .day, value: -1, to: startOfToday)!
        let startOfWeek = cal.dateInterval(of: .weekOfYear, for: now)!.start
        let startOfMonth = cal.dateInterval(of: .month, for: now)!.start

        let thisYear = cal.component(.year, from: now)

        var out: [Section] = []
        // 分组键先用数字，换组时才格式化标题，避免每张照片都跑一次日期格式化。
        var lastKey = -1
        func add(_ key: Int, _ id: String, _ title: () -> (String, String?)) {
            if key == lastKey { out[out.count - 1].items.append(id); return }
            let (t, detail) = title()
            out.append(Section(title: t, detail: detail, items: [id]))
            lastKey = key
        }
        for photo in photos {
            if filter == .unwritten, store.entry(photo.id) != nil { continue }
            guard let date = photo.date else {
                add(1, photo.id) { (String(localized: "没有日期", bundle: .app, locale: .app), nil) }
                continue
            }
            if date >= startOfToday { add(2, photo.id) { (String(localized: "今天", bundle: .app, locale: .app), DiaryDates.short(DayStamp(now))) } }
            else if date >= startOfYesterday { add(3, photo.id) { (String(localized: "昨天", bundle: .app, locale: .app), nil) } }
            else if date >= startOfWeek { add(4, photo.id) { (String(localized: "本周早些时候", bundle: .app, locale: .app), nil) } }
            else if date >= startOfMonth { add(5, photo.id) { (String(localized: "本月早些时候", bundle: .app, locale: .app), nil) } }
            else {
                let c = cal.dateComponents([.year, .month], from: date)
                let year = c.year ?? 0
                add(100 + year * 12 + (c.month ?? 0), photo.id) {
                    (year == thisYear ? DiaryDates.monthName(date) : DiaryDates.yearMonth(date), nil)
                }
            }
        }
        sections = out
    }
}
