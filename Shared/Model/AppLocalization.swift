import Foundation

// MARK: 代码里取文字用的语言

// SwiftUI 的 Text 每次绘制都重新查表，App 内切换语言立即生效；String(localized:) 却按启动时的系统语言查表，
// 传 locale 也不管用，只认 bundle。所以代码里一律写 String(localized: …, bundle: .app, locale: .app)：
// bundle 是界面语言的 .lproj，locale 决定复数规则（英文的 1 entry / 2 entries）。
// iPhone 上由 AppLanguage.apply 改写；Apple Watch 没有 App 内切换，保持系统默认。

extension Bundle {
    nonisolated(unsafe) static var app: Bundle = .main
}

extension Locale {
    nonisolated(unsafe) static var app: Locale = .autoupdatingCurrent
}
