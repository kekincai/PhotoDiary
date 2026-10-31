import SwiftUI
import Photos

/// 从照片添加：默认只列出还没写日记的照片，提醒补记当时的感受。
struct AddFromPhotosView: View {
    enum Filter: String, CaseIterable { case unwritten = "还没写", all = "全部照片" }

    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var filter: Filter = .unwritten
    @State private var photos: [(id: String, date: Date?)] = []
    @State private var loaded = false
    @State private var path: [String] = []
    @Namespace private var zoom

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)
    nonisolated static let limit = 6000

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    Picker("范围", selection: $filter.animation(.snappy)) {
                        ForEach(Filter.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .padding(.bottom, 18)
                    .sensoryFeedback(.selection, trigger: filter)

                    if store.isLimited { LimitedAccessBanner().padding(.bottom, 12) }

                    ForEach(sections, id: \.title) { section in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(section.title)
                                .font(.title3.weight(.bold))
                            if let detail = section.detail {
                                Text(detail).font(.footnote).foregroundStyle(Color.meta)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 10)
                        .accessibilityAddTraits(.isHeader)

                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(section.items, id: \.self) { id in
                                cell(id)
                            }
                        }
                        .padding(.bottom, 22)
                    }

                    if loaded && sections.isEmpty {
                        EmptyHint(title: filter == .unwritten ? "最近的照片都写过了" : "照片库是空的",
                                  message: filter == .unwritten ? "切换到“全部照片”，可以给它们追加感想。" : "拍几张照片再来。")
                    }
                }
            }
            .overlay { if !loaded { ProgressView() } }
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
            loaded = true
        }
    }

    private func cell(_ id: String) -> some View {
        let hasDiary = store.entry(id) != nil
        return Button { path.append(id) } label: {
            AssetImage(id: id)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .bottomLeading) {
                    if hasDiary {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Color(.label))
                            .frame(width: 20, height: 20)
                            .background(.white.opacity(0.94), in: .circle)
                            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                            .padding(5)
                    }
                }
                .matchedTransitionSource(id: id, in: zoom)
        }
        .buttonStyle(.press)
        .accessibilityLabel(hasDiary ? "已写日记的照片" : "还没写日记的照片")
    }

    // MARK: 分组：今天 / 昨天 / 本周早些时候 / 本月早些时候 / 按月

    private struct Section {
        var title: String
        var detail: String?
        var items: [String]
    }

    private var sections: [Section] {
        let cal = Calendar.diary
        let now = Date.now
        let startOfToday = cal.startOfDay(for: now)
        let startOfYesterday = cal.date(byAdding: .day, value: -1, to: startOfToday)!
        let startOfWeek = cal.dateInterval(of: .weekOfYear, for: now)!.start
        let startOfMonth = cal.dateInterval(of: .month, for: now)!.start

        var out: [Section] = []
        func add(_ title: String, _ detail: String?, _ id: String) {
            if out.last?.title == title { out[out.count - 1].items.append(id) }
            else { out.append(Section(title: title, detail: detail, items: [id])) }
        }
        for photo in photos {
            if filter == .unwritten, store.entry(photo.id) != nil { continue }
            let date = photo.date ?? .distantPast
            if date >= startOfToday { add("今天", DiaryDates.short(DayStamp(now)), photo.id) }
            else if date >= startOfYesterday { add("昨天", nil, photo.id) }
            else if date >= startOfWeek { add("本周早些时候", nil, photo.id) }
            else if date >= startOfMonth { add("本月早些时候", nil, photo.id) }
            else if photo.date == nil { add("没有日期", nil, photo.id) }
            else { add(DateFormatter.zh(cal.isDate(date, equalTo: now, toGranularity: .year) ? "M月" : "yyyy年M月").string(from: date), nil, photo.id) }
        }
        return out
    }
}
