import SwiftUI
import Photos

struct RootView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    /// 只在冷启动时出现一次；切换语言重建界面时不再出现。
    @State private var splash = !LaunchSplash.finished
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        Group {
            if store.canRead {
                MainTabs()
            } else {
                PermissionView()
            }
        }
        // 日记正文的宋体不会自己跟着“粗体文本”变粗：这个设置一变就重建界面（导航位置在 Router 里，不会丢）。
        .id(legibilityWeight == .bold)
        // 开屏盖在上面时，下面的界面不让 VoiceOver 读到。
        .accessibilityHidden(splash)
        .animation(.move, value: store.canRead)
        .overlay {
            if splash {
                LaunchSplash(ready: store.hasLoaded || !store.canRead) { splash = false }
            }
        }
    }
}

extension EnvironmentValues {
    /// 宽屏（iPad、横屏大 iPhone）：用系统标签栏，列表多栏。
    @Entry var isWide = false
}

/// 三个标签页（保留各自的滚动位置）。
///
/// - iPhone：隐藏系统标签栏，底部是自己的浮动玻璃标签栏 + 主题色“+”按钮；往下滚时收起成小胶囊。
///   日记在根页面时，标签栏上方多一条视图切换；搜索页用自己的底部搜索框代替标签栏。
/// - iPad（宽屏）：系统标签栏（顶部，可展开成侧栏），搜索是独立的搜索标签；“+”在导航栏右上角。
private struct MainTabs: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @SceneStorage("journalMode") private var mode: JournalMode = .list
    @Namespace private var zoom
    /// iPhone 上全屏的编辑器：不带系统的上滑动画出现，翻面由编辑器自己做。
    @State private var coverEditor: EditorRequest?

    private var wide: Bool { sizeClass == .regular }
    private var showsTabBar: Bool { !wide && router.isAtRoot && router.tab != .search }
    /// 搜索页的搜索框自己画渐隐；放在这里会盖在搜索框上面，看起来发灰。
    private var showsFade: Bool { showsTabBar && !(router.tab == .journal && mode == .map) }

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab(AppTab.journal.title, systemImage: AppTab.journal.symbol, value: AppTab.journal) {
                NavigationStack(path: $router.journalPath) { JournalView(mode: $mode).routes() }
                    .toolbarVisibility(wide ? .automatic : .hidden, for: .tabBar)
            }
            Tab(AppTab.review.title, systemImage: AppTab.review.symbol, value: AppTab.review) {
                NavigationStack(path: $router.reviewPath) { ReviewView().routes() }
                    .toolbarVisibility(wide ? .automatic : .hidden, for: .tabBar)
            }
            // 写明标题：系统默认的“搜索”跟系统语言，App 内切换语言时不会变。
            Tab(AppTab.search.title, systemImage: AppTab.search.symbol, value: AppTab.search, role: .search) {
                NavigationStack(path: $router.searchPath) { SearchView().routes() }
                    .toolbarVisibility(wide ? .automatic : .hidden, for: .tabBar)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(\.zoomNamespace, zoom)
        .environment(\.isWide, wide)
        .overlay(alignment: .bottom) {
            if showsFade {
                BottomFade(height: router.tabBarCollapsed ? 110 : 140)
                    .ignoresSafeArea(edges: .bottom)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if showsTabBar {
                FloatingTabBar(mode: $mode)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.move, value: router.isAtRoot)
        .animation(.move, value: router.tab == .search)
        .animation(.snappy, value: router.tab == .journal)
        .animation(.move, value: router.tabBarCollapsed)
        .sheet(isPresented: $router.showAddFromPhotos) {
            AddFromPhotosView()
        }
        .sheet(item: Binding(get: { wide ? router.editor : nil }, set: { router.editor = $0 })) { request in
            EditorSheet(request: request)
        }
        .fullScreenCover(item: Binding(get: { wide ? nil : coverEditor }, set: { coverEditor = $0; router.editor = $0 })) { request in
            EditorSheet(request: request, flips: true)
                .presentationBackground(.clear)
        }
        .onChange(of: router.editor) { _, request in
            guard !wide, request != coverEditor else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { coverEditor = request }
        }
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
        }
    }
}

extension View {
    /// 各标签页共用的导航目的地。
    func routes() -> some View {
        modifier(Routes())
    }
}

private struct Routes: ViewModifier {
    @Environment(\.isWide) private var wide

    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { route in
            Group {
                switch route {
                case .entry(let id): EntryDetailView(id: id)
                case .tag(let name): TagEntriesView(tag: name)
                case .tags: TagsView()
                case .day(let day): DayEntriesView(day: day)
                case .place(let name): PlaceEntriesView(place: name)
                }
            }
            .toolbarVisibility(wide ? .automatic : .hidden, for: .tabBar)
        }
    }
}

/// iPad 上导航栏右上角的“+”；iPhone 上在底部标签栏旁边。
struct WideAddButton: ToolbarContent {
    @Environment(Router.self) private var router
    @Environment(\.isWide) private var wide
    @Environment(\.brand) private var brand

    var body: some ToolbarContent {
        if wide {
            ToolbarItem(placement: .topBarTrailing) {
                Button("从照片写日记", systemImage: "plus") { router.showAddFromPhotos = true }
                    .buttonStyle(.glassProminent)
                    .tint(brand)
            }
        }
    }
}

/// 玻璃胶囊［日记 · 回顾 · 搜索］+ 主题色“+”。收起时只剩当前标签的小胶囊，两个玻璃体之间会融合过渡。
private struct FloatingTabBar: View {
    @Binding var mode: JournalMode
    @Environment(Router.self) private var router
    @Environment(\.brand) private var brand
    @Namespace private var selection
    @Namespace private var glass

    private var collapsed: Bool { router.tabBarCollapsed }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Group {
                    if collapsed {
                        Button { router.expandTabBar() } label: {
                            compactItem(router.tab)
                        }
                        .buttonStyle(.press)
                        .accessibilityLabel(Text("展开标签栏，当前是\(router.tab.title)"))
                        .largeContent(router.tab.title, systemImage: router.tab.symbol)
                    } else {
                        HStack(spacing: 0) {
                            ForEach(AppTab.allCases, id: \.self) { tab in
                                item(tab)
                            }
                        }
                        .padding(Metrics.Spacing.xs)
                        .animation(.snappy, value: router.tab)
                    }
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("tabs", in: glass)
                .sensoryFeedback(.selection, trigger: router.tab)

                // 收起时小胶囊留在左边，“+”留在右边，和系统标签栏收起后的布局一样。
                if collapsed { Spacer(minLength: 0) }

                Button {
                    router.showAddFromPhotos = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: collapsed ? 20 : 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: plusSize, height: plusSize)
                        .contentShape(.circle)
                }
                .buttonStyle(.press)
                .glassEffect(.regular.tint(brand).interactive(), in: .circle)
                .glassEffectID("plus", in: glass)
                .accessibilityLabel("从照片写日记")
                .largeContent(String(localized: "从照片写日记", bundle: .app, locale: .app), systemImage: "plus")
                .sensoryFeedback(.impact(weight: .light), trigger: router.showAddFromPhotos) { _, new in new }
            }
        }
        .padding(.horizontal, Metrics.page)
        .padding(.bottom, 6)
        // 和系统标签栏一样：字号固定在一定范围，更大的字号长按看大字。
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }

    private var plusSize: CGFloat { collapsed ? 48 : Metrics.primaryAction }

    private func item(_ tab: AppTab) -> some View {
        let selected = router.tab == tab
        return Button {
            // 内容立即切换，只有选中的滑块做动画；点当前标签回到根页面或顶部。
            router.select(tab)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.symbol)
                    .symbolVariant(selected ? .fill : .none)
                    .font(.system(size: 20, weight: .medium))
                    .frame(height: 26)
                    .symbolEffect(.bounce.down.byLayer, value: selected)
                Text(tab.title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(selected ? brand : Color.ink)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.control)
            .background {
                if selected {
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
        }
        .buttonStyle(.press)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .largeContent(tab.title, systemImage: tab.symbol)
        // 长按“日记”直接换视图（快捷方式；主入口在右上角）。
        .contextMenu {
            if tab == .journal {
                // 从别的标签长按时，选完也切回日记。
                JournalModePicker(mode: Binding(get: { mode }, set: { mode = $0; router.tab = .journal }))
            }
        }
    }

    /// 收起时的小胶囊：当前标签的实心图标 + 名字。
    private func compactItem(_ tab: AppTab) -> some View {
        HStack(spacing: 6) {
            Image(systemName: tab.symbol)
                .symbolVariant(.fill)
                .font(.system(size: 17, weight: .medium))
            Text(tab.title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(brand)
        .padding(.horizontal, Metrics.Spacing.l)
        .frame(height: 48)
        .contentShape(.capsule)
    }
}
