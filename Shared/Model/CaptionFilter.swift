import Foundation

/// 用户在设置里列出的“不是日记”的说明（例如“0”、导入工具留下的编号）。
/// 说明和其中一条完全相同（忽略首尾空白和大小写）的照片不在日记里出现；写日记时直接覆盖，和相机自动写入的说明一样。
nonisolated enum CaptionFilter {
    static let defaultsKey = "hiddenCaptions"

    static var patterns: [String] {
        get { patterns(in: .standard) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    static func patterns(in defaults: UserDefaults) -> [String] {
        defaults.stringArray(forKey: defaultsKey) ?? []
    }

    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 一次读出全部规则，批量判断时用。
    static func matcher(defaults: UserDefaults = .standard) -> (String?) -> Bool {
        let set = Set(patterns(in: defaults).map(normalized).filter { !$0.isEmpty })
        return { caption in
            guard !set.isEmpty, let caption else { return false }
            return set.contains(normalized(caption))
        }
    }
}
