import Foundation
import Observation
import FoundationModels

/// Apple Intelligence 的开关和可用性。机型不支持、系统没开、模型没下完、或用户在设置里关掉时 `isEnabled` 为假，
/// 相关入口直接不出现。
@Observable
final class Intelligence {
    static let storageKey = "intelligence"

    let engine: any IntelligenceEngine
    private let defaults: UserDefaults
    private let forcedAvailable: Bool?
    private(set) var availability: SystemLanguageModel.Availability

    /// 用户的开关（设置 → 通用 → Apple Intelligence）。
    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Self.storageKey) }
    }

    /// 本周回顾的缓存：同一周、同样的日记不重新生成。
    var reviewCache: (key: Int, text: String)?

    init(engine: any IntelligenceEngine = FoundationModelsEngine(), defaults: UserDefaults = .standard, forcedAvailable: Bool? = nil) {
        self.engine = engine
        self.defaults = defaults
        self.forcedAvailable = forcedAvailable
        self.enabled = defaults.object(forKey: Self.storageKey) as? Bool ?? true
        self.availability = forcedAvailable == true ? .available : .unavailable(.deviceNotEligible)
        refreshAvailability()
    }

    /// 界面测试：传 -fakeIntelligence 用固定规则的假模型；没传就当机器不支持，测试结果不受 Mac 是否开了 Apple Intelligence 影响。
    static func forLaunch() -> Intelligence {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-fakeIntelligence") {
            return Intelligence(engine: FakeIntelligenceEngine(), forcedAvailable: true)
        }
        if PhotoDiaryApp.isUITesting || PhotoDiaryApp.isHostingUnitTests {
            return Intelligence(forcedAvailable: false)
        }
        return Intelligence()
    }

    var isAvailable: Bool {
        if case .available = availability { return true }
        return false
    }

    var isEnabled: Bool { enabled && isAvailable }

    /// 机器支持 Apple Intelligence 才显示设置里的开关（没开或模型没好也显示，打开开关之后系统那边一好就能用）。
    var isEligible: Bool {
        if case .unavailable(.deviceNotEligible) = availability { return false }
        return true
    }

    /// 回到前台时重查：用户可能刚在系统设置里打开了 Apple Intelligence，或模型刚下载完。
    func refreshAvailability() {
        if let forcedAvailable {
            availability = forcedAvailable ? .available : .unavailable(.deviceNotEligible)
            return
        }
        availability = SystemLanguageModel.default.availability
    }

    /// 输出语言：跟界面语言。
    static var languageName: String {
        switch AppLanguage.current {
        case .chinese, .system: "Simplified Chinese"
        case .japanese: "Japanese"
        case .english: "English"
        }
    }
}
