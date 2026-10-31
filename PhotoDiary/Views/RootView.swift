import SwiftUI
import Photos

struct RootView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        Group {
            if store.canRead {
                MainTabs()
            } else {
                PermissionView()
            }
        }
        .animation(.move, value: store.canRead)
    }
}

/// 三个标签页（保留各自的滚动位置），底部浮动玻璃标签栏 + 主题色“+”按钮。
/// 用系统 TabView 承载、隐藏系统标签栏：同一时间屏幕上只有当前标签的滚动视图，点状态栏回到顶部才有效。
/// 日记在根页面时，标签栏上方多一条视图切换；搜索页用自己的底部搜索框代替标签栏。
private struct MainTabs: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SceneStorage("journalMode") private var mode: JournalMode = .list
    @Namespace private var zoom

    private var showsTabBar: Bool { router.isAtRoot && router.tab != .search }
    /// 搜索页的搜索框自己画渐隐；放在这里会盖在搜索框上面，看起来发灰。
    private var showsFade: Bool { showsTabBar && !(router.tab == .journal && mode == .map) }

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab(value: AppTab.journal) {
                NavigationStack(path: $router.journalPath) { JournalView(mode: $mode).routes() }
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab(value: AppTab.review) {
                NavigationStack(path: $router.reviewPath) { ReviewView().routes() }
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab(value: AppTab.search) {
                NavigationStack(path: $router.searchPath) { SearchView().routes() }
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
        }
        .environment(\.zoomNamespace, zoom)
        .overlay(alignment: .bottom) {
            if showsFade {
                BottomFade()
                    .ignoresSafeArea(edges: .bottom)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if showsTabBar {
                VStack(spacing: 16) {
                    if router.tab == .journal {
                        // 再点当前视图也回到顶部，和点标签一样。
                        GlassSegmented(options: JournalMode.allCases, selection: $mode, title: \.title,
                                       onReselect: { router.scrollToTop(.journal) })
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                    }
                    FloatingTabBar()
                }
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.move, value: router.isAtRoot)
        .animation(.move, value: router.tab == .search)
        .animation(.snappy, value: router.tab == .journal)
        .sheet(isPresented: $router.showAddFromPhotos) {
            AddFromPhotosView()
        }
        .sheet(item: $router.editor) { request in
            EditorSheet(request: request)
        }
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
        }
    }
}

extension View {
    /// 各标签页共用的导航目的地。
    func routes() -> some View {
        navigationDestination(for: Route.self) { route in
            Group {
                switch route {
                case .entry(let id): EntryDetailView(id: id)
                case .tag(let name): TagEntriesView(tag: name)
                case .tags: TagsView()
                case .day(let day): DayEntriesView(day: day)
                case .place(let name): PlaceEntriesView(place: name)
                }
            }
            .toolbarVisibility(.hidden, for: .tabBar)
        }
    }
}

private struct FloatingTabBar: View {
    @Environment(Router.self) private var router
    @Environment(\.brand) private var brand
    @Namespace private var selection

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        item(tab)
                    }
                }
                .padding(5)
                .animation(.snappy, value: router.tab)
                .glassEffect(.regular.interactive(), in: .capsule)
                .sensoryFeedback(.selection, trigger: router.tab)

                Button {
                    router.showAddFromPhotos = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 62)
                }
                .buttonStyle(.press)
                .glassEffect(.regular.tint(brand).interactive(), in: .circle)
                .accessibilityLabel("从照片写日记")
                .sensoryFeedback(.impact(weight: .light), trigger: router.showAddFromPhotos) { _, new in new }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func item(_ tab: AppTab) -> some View {
        let selected = router.tab == tab
        return Button {
            // 内容立即切换，只有选中的滑块做动画；点当前标签回到根页面或顶部。
            router.select(tab)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .frame(height: 26)
                Text(tab.title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(selected ? brand : Color.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
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
    }
}
