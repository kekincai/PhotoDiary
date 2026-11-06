import Foundation
import FoundationModels

/// 标签建议：模型给话题，这里整理成能写进说明的标签。
nonisolated enum TagSuggestions {
    static let maxSuggestions = 3
    static let maxInputCharacters = 1500

    /// 模型按内容打的话题。
    @Generable(description: "Topics of a diary entry, as short tags in the same language as the text.")
    struct Tagged: Sendable {
        @Guide(description: "Two to five short topic tags, each one to four words, same language as the text. Prefer any tag from the provided list that fits.", .maximumCount(5))
        var topics: [String]
    }

    /// 后处理：去掉 #、对回已有标签（不分大小写、全角半角）、名字要合规、文中已有的不再建议、去重、最多三个。
    static func refine(_ topics: [String], text: String, existing: [String]) -> [String] {
        let present = CaptionFormat.tags(in: text)
        var result: [String] = []
        for raw in topics {
            var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#＃"))
                .trimmingCharacters(in: .whitespaces)
            name = name.replacingOccurrences(of: "\n", with: " ")
            if let known = existing.first(where: { same($0, name) }) { name = known }
            guard CaptionFormat.isValidTagName(name),
                  !present.contains(where: { same($0, name) }),
                  !result.contains(where: { same($0, name) }) else { continue }
            result.append(name)
            if result.count == maxSuggestions { break }
        }
        return result
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) == .orderedSame
    }
}
