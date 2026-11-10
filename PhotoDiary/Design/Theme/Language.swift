import SwiftUI
import ObjectiveC

// MARK: 界面语言：跟随系统，或在设置里指定

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case chinese = "zh-Hans"
    case japanese = "ja"
    case english = "en"

    var id: String { rawValue }

    static let storageKey = "appLanguage"

    /// 语言名用各自的文字写，“跟随系统”跟着当前界面语言。
    var displayName: String {
        switch self {
        case .system: String(localized: "跟随系统", bundle: .app, locale: .app)
        case .chinese: "简体中文"
        case .japanese: "日本語"
        case .english: "English"
        }
    }

    /// 实际使用的语言：跟随系统时取系统首选语言里第一个支持的，都不支持时用英语。
    /// 繁体中文也用简体中文的界面（读得懂，比英语近）；App 名和权限说明这些系统显示的文字没有繁体，回退到开发语言简体中文，两边一致。
    var resolved: AppLanguage {
        guard self == .system else { return self }
        for identifier in Locale.preferredLanguages {
            let language = Locale.Language(identifier: identifier)
            switch language.languageCode {
            case .chinese: return .chinese
            case .japanese: return .japanese
            case .english: return .english
            default: continue
            }
        }
        return .english
    }

    /// 界面语言 + 系统的地区（日期格式、星期起始等跟随地区习惯）。
    var locale: Locale {
        let code = resolved.rawValue
        guard let region = Locale.current.region?.identifier else { return Locale(identifier: code) }
        return Locale(identifier: "\(code)_\(region)")
    }

    static var stored: AppLanguage {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// 当前界面语言（已解析，不会是 .system）。
    nonisolated(unsafe) private(set) static var current: AppLanguage = .chinese
    nonisolated(unsafe) fileprivate static var bundle: Bundle?

    /// 切换界面语言。App 内的文字立即生效；系统自己画的界面（权限弹窗、分享面板、文字选择菜单等）下次启动生效。
    /// `persist: false` 只改本次运行（单元测试的宿主用，不留下 AppleLanguages）。
    static func apply(_ choice: AppLanguage, persist: Bool = true) {
        if persist {
            if choice == .system {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([choice.rawValue], forKey: "AppleLanguages")
            }
        }
        current = choice.resolved
        bundle = Bundle.main.path(forResource: current.rawValue, ofType: "lproj").flatMap(Bundle.init(path:))
        DiaryDates.locale = current.locale
        // 代码里的 String(localized:) 用这两个（见 AppLocalization.swift）。
        Bundle.app = bundle ?? .main
        Locale.app = current.locale
        LocalizedBundle.install()
    }
}

/// 把 Bundle.main 的文字查找转到所选语言的 .lproj，SwiftUI 的 Text 走这里。
/// String(localized:) 不走这里，代码里要传 bundle: .app（见 AppLocalization.swift）。
private nonisolated final class LocalizedBundle: Bundle, @unchecked Sendable {
    nonisolated(unsafe) private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        object_setClass(Bundle.main, LocalizedBundle.self)
    }

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = AppLanguage.bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
