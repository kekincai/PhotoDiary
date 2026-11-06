import Testing
import Foundation
@testable import PhotoDiary

/// App 内切换界面语言：代码里取的文字（String(localized:bundle:.app)）跟着变，和系统语言无关。
@MainActor @Suite(.serialized)
struct AppLanguageTests {
    @Test func switchingLanguageChangesCodeStrings() {
        defer { AppLanguage.apply(AppLanguage.stored) }
        AppLanguage.apply(.english)
        #expect(String(localized: "设置", bundle: .app, locale: .app) == "Settings")
        AppLanguage.apply(.japanese)
        #expect(String(localized: "设置", bundle: .app, locale: .app) == "設定")
        AppLanguage.apply(.chinese)
        #expect(String(localized: "设置", bundle: .app, locale: .app) == "设置")
        #expect(String(localized: "周一", bundle: .app, locale: .app) == "周一")
        #expect(String(localized: "这周写了 \(3) 篇", bundle: .app, locale: .app) == "这周写了 3 篇")
    }
}
