import SwiftUI
import Photos
import PhotosUI

enum JournalMode: String, CaseIterable, Identifiable {
    case list, calendar, media, map
    var id: String { rawValue }
    var title: String {
        switch self {
        case .list: String(localized: "列表")
        case .calendar: String(localized: "日历")
        case .media: String(localized: "照片")
        case .map: String(localized: "地图")
        }
    }
}

extension EnvironmentValues {
    @Entry var zoomNamespace: Namespace.ID? = nil
}

/// 日记：同一份日记的四种视图。白底，大标题随内容滚走；颜色交给照片。
/// 视图切换在底部的浮动玻璃分段控件里（RootView）。
struct JournalView: View {
    @Binding var mode: JournalMode
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pastTitle = false

    var body: some View {
        Group {
            switch mode {
            case .list, .calendar: scroll
            // 还没有日记时，照片视图和列表一样显示空状态。
            case .media: if store.timeline.isEmpty { scroll } else { mediaScroll }
            case .map: MapContent().ignoresSafeArea()
            }
        }
        .id(mode)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: mode)
        .onChange(of: mode) { pastTitle = false }

        .navigationTitle("日记")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(mode == .media && !pastTitle ? .dark : nil, for: .navigationBar)
        .toolbarBackgroundVisibility(mode == .map ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("日记")
                    .font(.headline)
                    .opacity(pastTitle || mode == .map ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: pastTitle)
                    .accessibilityHidden(!(pastTitle || mode == .map))
            }
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
    }

    // MARK: 列表、日历

    /// 再点“日记”标签时滚回到这个元素：对齐到第一个元素，导航栏下面的边距由系统算。
    /// 监听挂在滚动视图上，不挂在列表行里（滚远后行会被回收，收不到通知）。
    private static let topID = "journal-top"

    private var scroll: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                TitleBlock(subtitle: subtitle)
                    .id(Self.topID)
                Section {
                    if mode == .calendar { CalendarContent() } else { ListContent() }
                } header: {
                    if mode == .calendar { WeekdayHeader().padding(.top, 16) }
                }
            }
            .padding(.bottom, 170)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top > 46
        } action: { _, past in
            pastTitle = past
        }
        .onChange(of: router.scrollToTopRequests[.journal]) {
            withAnimation(.move) { proxy.scrollTo(Self.topID, anchor: .top) }
        }
        }
    }

    // MARK: 照片网格：铺到屏幕顶部，标题压在照片上

    private var mediaScroll: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
            ScrollView {
                MediaGridContent()
                    .id(Self.topID)
                    .overlay(alignment: .top) {
                        ZStack(alignment: .top) {
                            LinearGradient(stops: [
                                .init(color: .black.opacity(0.55), location: 0),
                                .init(color: .black.opacity(0.28), location: 0.55),
                                .init(color: .black.opacity(0), location: 1),
                            ], startPoint: .top, endPoint: .bottom)
                            .frame(height: max(190, viewport.safeAreaInsets.top + 92))
                            .allowsHitTesting(false)
                            TitleBlock(subtitle: subtitle, onPhoto: true)
                                .padding(.top, viewport.safeAreaInsets.top)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.bottom, 170)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .onChange(of: router.scrollToTopRequests[.journal]) {
                withAnimation(.move) { proxy.scrollTo(Self.topID, anchor: .top) }
            }
            .scrollEdgeEffectHidden(!pastTitle, for: .top)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y > 120
            } action: { _, past in
                pastTitle = past
            }
            }
        }
    }

    // MARK: 头部

    private var subtitle: String {
        if case .scanning(let done, let total) = store.syncState, total > 0 {
            let percent = Int(Double(done) / Double(total) * 100)
            return String(localized: "正在读取照片说明 \(percent)%")
        }
        // 按写作日期数；下面的月份标题按照片日期数，所以这里不写月份名，免得两个“10月”数字对不上。
        let n = store.writtenThisMonth
        return n == 0 ? String(localized: "本月还没写") : String(localized: "本月写了 \(n) 篇")
    }

    private var moreMenu: some View {
        Menu {
            Button("标签", systemImage: "number") { router.push(.tags) }
            Divider()
            Button("设置", systemImage: "gearshape") { router.showSettings = true }
        } label: {
            Label("更多选项", systemImage: "ellipsis")
        }
    }
}

/// 页面大标题 + 一行副标题；照片网格里是白字压在照片上。
private struct TitleBlock: View {
    let subtitle: String
    var onPhoto = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("日记")
                .font(.system(size: 34, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.system(size: 15, weight: onPhoto ? .medium : .regular))
                .foregroundStyle(onPhoto ? Color.white : Color.meta)
                .contentTransition(.numericText())
                .animation(.snappy, value: subtitle)
        }
        .foregroundStyle(onPhoto ? Color.white : Color.ink)
        .shadow(color: .black.opacity(onPhoto ? 0.25 : 0), radius: 8, y: 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 2)
    }
}

/// 只给了“有限访问”时：提示可以扩大范围。
struct LimitedAccessBanner: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("只显示了你允许访问的照片")
                .font(.footnote)
                .foregroundStyle(Color.meta)
            Spacer(minLength: 0)
            Button("选择更多") { LimitedLibrary.present() }
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.tile, in: .rect(cornerRadius: 16, style: .continuous))
    }
}

enum LimitedLibrary {
    static func present() {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              var top = scene.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }
}
