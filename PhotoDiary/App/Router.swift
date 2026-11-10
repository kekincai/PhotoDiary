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
    /// 点哪个按钮打开的（matchedTransitionSource 的 id）：编辑器从这个按钮放大出来。
    var zoomSource: String? = nil

    /// “追加感想”按钮的 zoom 来源 id。
    static func appendButton(_ assetID: String) -> String { "append:\(assetID)" }
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
    /// 快捷指令带来的搜索文字，搜索页接过去后清空。
    var searchRequest: String?

    /// 有编辑器开着、里面写了还没保存的字（表单里的和“从照片添加”里推入的都算）。
    /// 这时从外面来的链接不顶掉编辑器，等它关掉（保存或放弃）再打开。
    var editorIsDirty = false {
        didSet { if oldValue, !editorIsDirty { openDeferredLink() } }
    }
    private var deferredLink: (link: DeepLink, latestPhoto: LatestPhoto?)?
    /// 没保存就被收起的编辑器留下的字（zoom 转场的下拉、捏合返回不经过“放弃这次修改？”）。
    /// 下次打开同一张照片的同一种编辑器时放回去；只在内存里。
    private var drafts: [String: String] = [:]

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

    // MARK: 从外面打开（小组件、控制中心、快捷指令）

    /// 最新一张照片和它写没写过日记；只有“写最新一张”要用，由调用方去照片库查。
    struct LatestPhoto: Equatable {
        var id: String
        var hasDiary: Bool
    }

    /// 打开一个 photodiary:// 链接。原来开着的面板先关掉，再到链接指的地方。
    /// 编辑器里有没保存的字时先记下，等编辑器关掉再打开（程序关掉编辑器不经过“放弃这次修改？”，字会丢）。
    func open(_ link: DeepLink, latestPhoto: LatestPhoto? = nil) {
        if editorIsDirty {
            deferredLink = (link, latestPhoto)
            return
        }
        // 照片库里一张照片都没有：“写最新一张”什么也不做，开着的东西也不动。
        if link == .writeLatest, latestPhoto == nil { return }
        let hadSheet = showAddFromPhotos || showSettings || editor != nil
        showAddFromPhotos = false
        showSettings = false
        switch link {
        case .writeLatest:
            guard let latestPhoto else { return }
            let request = EditorRequest(assetID: latestPhoto.id, mode: latestPhoto.hasDiary ? .append : .new)
            if !hadSheet {
                editor = request
            } else {
                // 已经开着一个面板：等它收起再弹编辑器，同时换会被 SwiftUI 吞掉。
                editor = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    editor = request
                }
            }
        case .today:
            editor = nil
            tab = .journal
            journalPath = [.day(.today)]
        case .onThisDay:
            editor = nil
            tab = .review
            reviewPath = []
            scrollToTop(.review)
        case .entry(let id):
            editor = nil
            tab = .journal
            journalPath = [.entry(id)]
        case .search(let query):
            editor = nil
            tab = .search
            searchPath = []
            searchRequest = query
        }
    }

    private func openDeferredLink() {
        guard let deferred = deferredLink else { return }
        deferredLink = nil
        Task {
            // 编辑器正在收起：等它收完再开别的面板，同时换会被 SwiftUI 吞掉。
            try? await Task.sleep(for: .milliseconds(600))
            open(deferred.link, latestPhoto: deferred.latestPhoto)
        }
    }

    // MARK: 草稿

    private static func draftKey(_ assetID: String, _ mode: DiaryStore.WriteMode) -> String { "\(mode):\(assetID)" }

    func saveDraft(_ text: String, for assetID: String, mode: DiaryStore.WriteMode) {
        drafts[Self.draftKey(assetID, mode)] = text
    }

    /// 取出并清掉这张照片的草稿。
    func takeDraft(for assetID: String, mode: DiaryStore.WriteMode) -> String? {
        drafts.removeValue(forKey: Self.draftKey(assetID, mode))
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
