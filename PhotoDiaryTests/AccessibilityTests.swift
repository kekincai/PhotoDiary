import Testing
import Foundation
@testable import PhotoDiary

/// VoiceOver 读出来的句子。
struct AccessibilityTests {
    private func entry(_ caption: String, kind: MediaKind = .photo, on day: Date = date(2026, 10, 20)) -> DiaryEntry {
        DiaryEntry(id: "x", caption: caption, keywords: [], creationDate: day, latitude: nil, longitude: nil,
                   mediaKind: kind, isCloudShared: false, pixelWidth: 4, pixelHeight: 3)
    }

    @Test func sentencesDoNotDoubleFullStops() {
        #expect(Spoken.sentences(["寺里的苔藓被雨淋得发亮。", "标签：旅行"]) == "寺里的苔藓被雨淋得发亮。标签：旅行")
        #expect(Spoken.sentences(["真的吗？", "好"]) == "真的吗？好")
        #expect(Spoken.sentences(["一", "", "二"]) == "一。二")
    }

    /// 回归：标题以句号结尾时读成“发亮。。标签”。
    @Test func summaryReadsLikeSentences() {
        var e = entry("寺里的苔藓被雨淋得发亮。 #旅行# #京都#\n— 2026.10.20")
        e.placeName = "京都市"
        let spoken = e.spokenSummary
        #expect(!spoken.contains("。。"))
        #expect(!spoken.contains("#"))
        #expect(spoken.contains("京都市"))
        #expect(spoken.contains("寺里的苔藓被雨淋得发亮。"))
        #expect(spoken.contains("旅行"))
        #expect(spoken.contains("京都"))
    }

    @Test func summaryMentionsSegmentsAndMediaKind() {
        let e = entry("第一段\n— 2026.10.20\n\n第二段\n— 2026.10.25", kind: .video)
        let spoken = e.spokenSummary
        #expect(spoken.contains("2 段"))
        #expect(spoken.hasSuffix("视频"))
        #expect(entry("一张", kind: .livePhoto).spokenSummary.hasSuffix("实况照片"))
    }

    @Test func tagNamesAreSpokenWithoutHashMarks() {
        #expect(Spoken.tag("旅行") == "标签“旅行”")
        #expect(Spoken.tags([]) == nil)
        #expect(Spoken.tags(["旅行"])?.contains("#") == false)
    }
}
