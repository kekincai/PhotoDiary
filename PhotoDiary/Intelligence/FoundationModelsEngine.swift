import Foundation
import FoundationModels
import OSLog

/// 真实现：Apple 设备上的语言模型。每次调用新开一个会话，不保留对话。
/// 提示词用英文写，输出语言跟界面语言；标签跟日记原文的语言。出错一律静默，界面上就当没有建议。
nonisolated struct FoundationModelsEngine: IntelligenceEngine {
    func interpret(_ query: String, context: SearchContext) async -> SearchIntent? {
        let instructions = """
        You turn a search query over a personal photo diary into filters. Reply only with the structured result.
        Today is \(context.today.captionString) (year \(context.today.year)). Resolve relative times to absolute dates: \
        "last year" is \(context.today.year - 1)-01-01 to \(context.today.year - 1)-12-31; "this summer" is June to August of \
        \(context.today.year); "last month" is the previous calendar month. Leave dates empty when no time is mentioned.
        Known tags (use only these, spelled exactly): \(context.tags.joined(separator: ", ")).
        Known places (use only these, spelled exactly): \(context.places.joined(separator: ", ")).
        Keywords are the remaining content words, in the query's language, plus one or two close synonyms. \
        Do not put time expressions, tag names or place names into keywords.
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: query, generating: SearchIntent.self)
            return response.content
        } catch {
            Log.intelligence.debug("解析搜索失败：\(error, privacy: .public)")
            return nil
        }
    }

    func suggestTags(for text: String, existing: [String]) async -> [String] {
        let model = SystemLanguageModel(useCase: .contentTagging)
        let input = String(text.prefix(TagSuggestions.maxInputCharacters))
        let known = existing.prefix(SearchContext.maxTags).joined(separator: ", ")
        let prompt = """
        Existing tags: \(known.isEmpty ? "(none)" : known)
        Diary entry:
        \(input)
        """
        do {
            let session = LanguageModelSession(model: model)
            let response = try await session.respond(to: prompt, generating: TagSuggestions.Tagged.self)
            return TagSuggestions.refine(response.content.topics, text: text, existing: existing)
        } catch {
            Log.intelligence.debug("建议标签失败：\(error, privacy: .public)")
            return []
        }
    }

    func weeklyReview(_ input: WeeklyReviewInput) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let instructions = """
                You write a short weekly look-back for the author of a personal photo diary, in \(input.language). \
                Two or three sentences, addressed to the author as "you", warm and plain. Mention only what the entries say; \
                do not invent details, do not judge, do not give advice, do not list dates. No headings, no emoji, no quotes.
                """
                let lines = input.items.map { item in
                    var line = item.date.captionString
                    if let place = item.place { line += " · " + place }
                    return line + " · " + item.text
                }
                let prompt = "This week's entries:\n" + lines.joined(separator: "\n")
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    for try await snapshot in session.streamResponse(to: prompt) {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    Log.intelligence.debug("本周回顾失败：\(error, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
