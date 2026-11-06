import Foundation
import Observation

// MARK: 从外面打开 App 的入口（App 和小组件扩展共用）
//
// 小组件、控制中心、快捷指令都只是把 App 打开到某个地方，统一成一个 photodiary:// 链接：
// - photodiary://write/latest   给最新一张照片写日记（写过就追加感想）
// - photodiary://today          今天的日记
// - photodiary://onthisday      回顾里的那年今日
// - photodiary://entry/<id>     某一篇（id 是 PHAsset.localIdentifier，本身带斜杠）
// - photodiary://search?q=…     带着文字打开搜索

nonisolated enum DeepLink: Hashable, Sendable {
    case writeLatest
    case today
    case onThisDay
    case entry(String)
    case search(String)

    static let scheme = "photodiary"

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else { return nil }
        let path = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        switch host {
        case "write":
            guard path == ["latest"] || path.isEmpty else { return nil }
            self = .writeLatest
        case "today":
            self = .today
        case "onthisday":
            self = .onThisDay
        case "entry":
            let id = path.joined(separator: "/")
            guard !id.isEmpty else { return nil }
            self = .entry(id)
        case "search":
            let query = components.queryItems?.first { $0.name == "q" }?.value ?? ""
            self = .search(query.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .writeLatest:
            components.host = "write"
            components.path = "/latest"
        case .today:
            components.host = "today"
        case .onThisDay:
            components.host = "onthisday"
        case .entry(let id):
            components.host = "entry"
            components.path = "/" + id
        case .search(let query):
            components.host = "search"
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        }
        return components.url ?? URL(string: "\(Self.scheme)://")!
    }
}

/// 收到、还没处理的链接。App 没读到照片库（刚启动、还没授权）时先放在这里，能读了再打开。
@MainActor @Observable
final class DeepLinkInbox {
    static let shared = DeepLinkInbox()

    private(set) var pending: DeepLink?

    func open(_ link: DeepLink) { pending = link }

    func take() -> DeepLink? {
        defer { pending = nil }
        return pending
    }
}
