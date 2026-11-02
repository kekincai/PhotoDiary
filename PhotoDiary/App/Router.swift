import SwiftUI
import Photos

enum AppTab: Hashable, CaseIterable {
    case journal, review, search

    var title: String {
        switch self {
        case .journal: String(localized: "日记", bundle: .app, locale: .app)
        case .review: String(localized: "回顾", bundle: .app, locale: .app)
        case .search: String(localized: "搜索", bundle: .app, locale: .app)
        }
    }

    /// 标签栏图标。选中时用实心变体（系统标签栏的惯例）。
    var symbol: String {
        switch self {
        case .journal: "book.pages"
        case .review: "sparkles.rectangle.stack"
        case .search: "magnifyingglass"
        }
    }
}

enum Route: Hashable {
    case entry(String)
    case tag(String)
    case tags
    case day(DayStamp)
    case place(String)
}

struct EditorRequest: Identifiable, Hashable {
    let id = UUID()
    let assetID: String
    let mode: DiaryStore.WriteMode
    /// 预先填进编辑器的文字（例如手记建议里的歌曲）。
    var seed: String? = nil
}

/// 每个标签页各自一条导航路径；推入详情时隐藏底部标签栏。
@Observable
final class Router {
    var tab: AppTab = .journal {
        didSet { if tab != oldValue { tabBarCollapsed = false } }
    }
    var journalPath: [Route] = []
    var reviewPath: [Route] = []
    var searchPath: [Route] = []

    /// 再点一次已在根页面的当前标签时加一；对应页面据此滚回顶部。
    private(set) var scrollToTopRequests: [AppTab: Int] = [:]

    /// 往下滚时标签栏收起成只剩当前标签的小胶囊（系统标签栏的做法），往上滚或回到顶部时展开。
    private(set) var tabBarCollapsed = false

    var showAddFromPhotos = false
    var showSettings = false
    var editor: EditorRequest?

    var isAtRoot: Bool {
        switch tab {
        case .journal: journalPath.isEmpty
        case .review: reviewPath.isEmpty
        case .search: searchPath.isEmpty
        }
    }

    /// 点标签栏（iOS 惯例）：切到别的标签只切换；点当前标签时，在子页面先回到根页面，已在根页面则滚回顶部。
    func select(_ tab: AppTab) {
        guard tab == self.tab else { self.tab = tab; return }
        if isAtRoot { scrollToTop(tab) } else { popToRoot() }
    }

    func scrollToTop(_ tab: AppTab) {
        scrollToTopRequests[tab, default: 0] += 1
        tabBarCollapsed = false
    }

    func popToRoot() {
        switch tab {
        case .journal: journalPath.removeAll()
        case .review: reviewPath.removeAll()
        case .search: searchPath.removeAll()
        }
    }

    func push(_ route: Route) {
        switch tab {
        case .journal: journalPath.append(route)
        case .review: reviewPath.append(route)
        case .search: searchPath.append(route)
        }
    }

    /// 写完新日记后：回到日记列表并打开这篇。
    func showNewEntry(_ id: String) {
        tab = .journal
        journalPath = [.entry(id)]
    }

    func popCurrent() {
        switch tab {
        case .journal: _ = journalPath.popLast()
        case .review: _ = reviewPath.popLast()
        case .search: _ = searchPath.popLast()
        }
    }

    // MARK: 标签栏收起

    /// 根页面的滚动视图每次滚动都来报一下：往下滚过一段就收起，往上滚一点就展开，靠近顶部一定展开。
    func scrolled(from old: CGFloat, to new: CGFloat) {
        let delta = new - old
        if new < 48 {
            setCollapsed(false)
        } else if delta > 4 {
            setCollapsed(true)
        } else if delta < -4 {
            setCollapsed(false)
        }
    }

    func expandTabBar() { setCollapsed(false) }

    private func setCollapsed(_ collapsed: Bool) {
        guard collapsed != tabBarCollapsed else { return }
        tabBarCollapsed = collapsed
    }
}

/// 挂在根页面的滚动视图上，把滚动方向交给 Router，标签栏据此收起、展开。
/// “减少动态效果”、VoiceOver、切换控制下不收起：VoiceOver 逐项滚动时标签栏一收一放，焦点会跟着跳。
struct TabBarScrollReporter: ViewModifier {
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.assistiveTechnology) private var assistive

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { old, new in
            guard !reduceMotion, !assistive.isRunning else { return }
            router.scrolled(from: old, to: new)
        }
        .onChange(of: assistive.isRunning) { _, running in
            if running { router.expandTabBar() }
        }
    }
}

extension View {
    func collapsesTabBarOnScroll() -> some View { modifier(TabBarScrollReporter()) }
}
