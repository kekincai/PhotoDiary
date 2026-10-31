import Foundation

/// 一段日记：正文 + 末尾的写作时间行。
nonisolated struct DiarySegment: Hashable, Codable, Sendable {
    var text: String
    var date: DayStamp?
}

nonisolated struct ParsedCaption: Hashable, Sendable {
    var segments: [DiarySegment]
    var tags: [String]

    /// 至少有一段带写作时间行，才算“日记”格式。
    var hasDateLine: Bool { segments.contains { $0.date != nil } }
}

/// 照片说明的纯文本格式。说明是唯一正本，这里只负责读和按规则拼接，
/// 永不擅自改写用户在别处写的文字。
///
///     风很舒服，第一次用新镜头拍日落 #旅行# #镜头测试#
///     — 2026.10.31
///
///     三年后再看，还是喜欢这张
///     — 2029.11.02
nonisolated enum CaptionFormat {
    static let maxTagLength = 20

    // 标签：#话题# 或全角 ＃话题＃；内容不含换行、首尾不为空白，长度 1…20。
    private static let tagRegex = try! NSRegularExpression(
        pattern: "[#＃]([^#＃\\s](?:[^#＃\\n]{0,\(maxTagLength - 2)}[^#＃\\s])?)[#＃]"
    )
    // 写作时间行：— 2026.10.31（容忍 – 和 - 以及多余空格）。
    private static let dateLineRegex = try! NSRegularExpression(
        pattern: "^\\s*[—–\\-]{1,2}\\s*(\\d{4})\\.(\\d{1,2})\\.(\\d{1,2})\\s*$"
    )
    // 行尾连续的标签（只影响显示）。
    private static let trailingTagsRegex = try! NSRegularExpression(
        pattern: "(?:[ \\t\\u3000]*[#＃][^#＃\\s](?:[^#＃\\n]{0,\(maxTagLength - 2)}[^#＃\\s])?[#＃])+[ \\t\\u3000]*$",
        options: [.anchorsMatchLines]
    )

    // MARK: 解析

    static func parse(_ caption: String) -> ParsedCaption {
        var segments: [DiarySegment] = []
        var buffer: [Substring] = []

        func flush(date: DayStamp?) {
            let text = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeAll()
            if !text.isEmpty || date != nil {
                segments.append(DiarySegment(text: text, date: date))
            }
        }

        let normalized = caption.replacingOccurrences(of: "\r\n", with: "\n")
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if let day = dateStamp(inLine: String(line)) {
                flush(date: day)
            } else {
                buffer.append(line)
            }
        }
        flush(date: nil)

        // 只有一个日期行、没有正文的段落合并进前一段，避免显示空段。
        segments = segments.reduce(into: []) { result, segment in
            if segment.text.isEmpty, var last = result.last, last.date == nil {
                last.date = segment.date
                result[result.count - 1] = last
            } else if !segment.text.isEmpty {
                result.append(segment)
            }
        }
        return ParsedCaption(segments: segments, tags: tags(in: caption))
    }

    static func dateStamp(inLine line: String) -> DayStamp? {
        let range = NSRange(line.startIndex..., in: line)
        guard let m = dateLineRegex.firstMatch(in: line, range: range),
              let y = Int(line[Range(m.range(at: 1), in: line)!]),
              let mo = Int(line[Range(m.range(at: 2), in: line)!]),
              let d = Int(line[Range(m.range(at: 3), in: line)!]) else { return nil }
        return DayStamp(year: y, month: mo, day: d)
    }

    /// 按出现顺序去重后的标签名（不含 #）。
    static func tags(in text: String) -> [String] {
        var seen = Set<String>()
        return tagMatches(in: text).compactMap { seen.insert($0.name).inserted ? $0.name : nil }
    }

    struct TagMatch: Sendable {
        var range: Range<String.Index>
        var name: String
    }

    static func tagMatches(in text: String) -> [TagMatch] {
        let ns = NSRange(text.startIndex..., in: text)
        return tagRegex.matches(in: text, range: ns).compactMap { m in
            guard let whole = Range(m.range, in: text), let inner = Range(m.range(at: 1), in: text) else { return nil }
            return TagMatch(range: whole, name: String(text[inner]))
        }
    }

    // MARK: 相机自动写入的说明

    private static let cameraMakers = ["FUJIFILM", "OLYMPUS", "SONY", "NIKON", "CANON", "KODAK", "LEICA", "RICOH",
                                       "PENTAX", "PANASONIC", "SAMSUNG", "SIGMA", "HASSELBLAD", "MINOLTA", "KONICA",
                                       "CASIO", "GOPRO", "DJI", "LG", "HUAWEI", "XIAOMI"]

    /// 相机自动写进 EXIF/IPTC 的说明，例如“FUJIFILM DIGITAL CAMERA GFX100RF”“OLYMPUS DIGITAL CAMERA”“SONY DSC”。
    /// 这类说明不算日记，读取时忽略，写日记时直接覆盖。
    static func isCameraBoilerplate(_ caption: String?) -> Bool {
        guard let text = caption?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return false }
        if text.contains("\n") || text.count > 64 { return false }
        let upper = text.uppercased()
        if ["DEFAULT", "UNTITLED", "SONY DSC", "DCIM", "DIGITAL CAMERA", "CAMERA"].contains(upper) { return true }
        if upper.contains("DIGITAL CAMERA") || upper.contains("DIGITAL STILL CAMERA") || upper.contains("CAMERA PICTURES") {
            return true
        }
        // 全大写、只含拉丁字母数字和少量符号、以厂商名开头的短串，例如“LEICA CAMERA AG”“RICOH GR III”。
        let allowed = CharacterSet.uppercaseLetters.union(.decimalDigits).union(CharacterSet(charactersIn: " -_./"))
        let isMachineLike = text == upper && text.unicodeScalars.allSatisfy { $0.isASCII && allowed.contains($0) }
        return isMachineLike && cameraMakers.contains { upper.hasPrefix($0 + " ") || upper == $0 }
    }

    // MARK: 写入

    static func dateLine(_ day: DayStamp) -> String { "— \(day.captionString)" }

    /// 写入前统一把标签的全角＃换成半角#，其余文字一字不动。
    static func normalizeTags(_ text: String) -> String {
        var result = text
        for match in tagMatches(in: text).reversed() {
            result.replaceSubrange(match.range, with: "#\(match.name)#")
        }
        return result
    }

    /// 新写或追加一段：正文后自动补写作时间行，追加时与旧内容空一行。
    static func appending(_ newText: String, to existing: String?, on day: DayStamp = .today) -> String {
        let body = normalizeTags(newText.trimmingCharacters(in: .whitespacesAndNewlines))
        let segment = body + "\n" + dateLine(day)
        let old = isCameraBoilerplate(existing) ? "" : (existing ?? "").trimmingTrailingWhitespace()
        return old.isEmpty ? segment : old + "\n\n" + segment
    }

    /// 编辑整条说明后保存：若最后一段还没有写作时间行就补上。返回 nil 表示清除说明。
    static func finalizingEdit(_ edited: String, on day: DayStamp = .today) -> String? {
        let text = normalizeTags(edited).trimmingTrailingWhitespace()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let lastLine = text.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        if dateStamp(inLine: lastLine) != nil { return text }
        return text + "\n" + dateLine(day)
    }

    /// 把说明里所有 #old# 改为 #new#；同一条说明里已有 #new# 时去掉重复。
    static func renamingTag(_ old: String, to new: String, in caption: String) -> String {
        guard old != new else { return caption }
        var result = caption
        let matches = tagMatches(in: caption)
        let alreadyHasNew = matches.contains { $0.name == new }
        let olds = matches.filter { $0.name == old }
        for (i, match) in olds.enumerated().reversed() {
            if alreadyHasNew || i > 0 {
                // 已经有目标标签：删除这一个，并吃掉一侧多余的空格。
                var range = match.range
                if range.lowerBound > result.startIndex,
                   result[result.index(before: range.lowerBound)] == " " {
                    range = result.index(before: range.lowerBound)..<range.upperBound
                } else if range.upperBound < result.endIndex, result[range.upperBound] == " " {
                    range = range.lowerBound..<result.index(after: range.upperBound)
                }
                result.removeSubrange(range)
            } else {
                result.replaceSubrange(match.range, with: "#\(new)#")
            }
        }
        return result
    }

    static func isValidTagName(_ name: String) -> Bool {
        let probe = "#\(name)#"
        return tagMatches(in: probe).first.map { $0.name == name && $0.range == probe.startIndex..<probe.endIndex } ?? false
    }

    // MARK: 显示（不改变存储）

    /// 去掉每行行尾的标签串，标签另行显示在地点后面。
    static func strippingTrailingTags(_ text: String) -> String {
        let ns = NSRange(text.startIndex..., in: text)
        let stripped = trailingTagsRegex.stringByReplacingMatches(in: text, range: ns, withTemplate: "")
        return stripped
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 首句作标题：到第一个句号、问号、感叹号或换行为止（含标点）。
    static func splitTitle(_ text: String) -> (title: String, rest: String) {
        let terminators: Set<Character> = ["。", "？", "！", "?", "!", "\n"]
        guard let index = text.firstIndex(where: { terminators.contains($0) }) else {
            return (text, "")
        }
        let titleEnd = text[index] == "\n" ? index : text.index(after: index)
        // 连续的标点（如“！！”“？！”）也归入标题。
        var end = titleEnd
        while end < text.endIndex, terminators.contains(text[end]), text[end] != "\n" {
            end = text.index(after: end)
        }
        let title = String(text[..<end]).trimmingCharacters(in: .whitespaces)
        let rest = String(text[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, rest)
    }
}

nonisolated extension String {
    func trimmingTrailingWhitespace() -> String {
        var s = self
        while let last = s.last, last.isWhitespace || last.isNewline { s.removeLast() }
        return s
    }
}
