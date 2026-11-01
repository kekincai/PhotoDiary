import SwiftUI
import Photos

enum AppTab: Hashable, CaseIterable {
    case journal, review, search

    var title: String {
        switch self {
        case .journal: String(localized: "日记")
        case .review: String(localized: "回顾")
        case .search: String(localized: "搜索")
        }
    }

    var symbol: String {
        switch self {
        case .journal: "book.pages"
        case .review: "clock"
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
}

/// 每个标签页各自一条导航路径；推入详情时隐藏底部标签栏。
@Observable
final class Router {
    var tab: AppTab = .journal
    var journalPath: [Route] = []
    var reviewPath: [Route] = []
    var searchPath: [Route] = []

    /// 再点一次已在根页面的当前标签时加一；对应页面据此滚回顶部。
    private(set) var scrollToTopRequests: [AppTab: Int] = [:]

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
}
