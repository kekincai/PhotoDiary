import SwiftUI
import Photos

enum AppTab: Hashable, CaseIterable {
    case journal, review, search

    var title: String {
        switch self {
        case .journal: "日记"
        case .review: "回顾"
        case .search: "搜索"
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
    case external
    case day(DayStamp)
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
