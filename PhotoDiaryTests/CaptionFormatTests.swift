import Testing
import Foundation
@testable import PhotoDiary

struct CaptionFormatTests {
    let sample = """
    风很舒服，第一次用新镜头拍日落 #旅行# #镜头测试#
    — 2026.10.31

    三年后再看，还是喜欢这张
    — 2029.11.02
    """

    @Test func parsesSegmentsAndDates() {
        let parsed = CaptionFormat.parse(sample)
        #expect(parsed.segments.count == 2)
        #expect(parsed.segments[0].date == DayStamp(year: 2026, month: 10, day: 31))
        #expect(parsed.segments[1].text == "三年后再看，还是喜欢这张")
        #expect(parsed.tags == ["旅行", "镜头测试"])
        #expect(parsed.hasDateLine)
    }

    @Test func externalCaptionHasNoDate() {
        let parsed = CaptionFormat.parse("Sunset at Kamakura beach")
        #expect(parsed.segments.count == 1)
        #expect(parsed.segments[0].date == nil)
        #expect(!parsed.hasDateLine)
    }

    @Test func malformedDateLineIsBodyText() {
        let parsed = CaptionFormat.parse("今天\n— 2026.13.40")
        #expect(parsed.segments.count == 1)
        #expect(parsed.segments[0].text == "今天\n— 2026.13.40")
        #expect(parsed.segments[0].date == nil)
    }

    @Test func tagRules() {
        #expect(CaptionFormat.tags(in: "和＃朋友＃去看#展览#") == ["朋友", "展览"])
        #expect(CaptionFormat.tags(in: "单个 # 不是标签") == [])
        #expect(CaptionFormat.tags(in: "我有#3 个苹果 #旅行#") == ["旅行"])
        #expect(CaptionFormat.tags(in: "#" + String(repeating: "长", count: 21) + "#") == [])
        #expect(CaptionFormat.tags(in: "#a\nb#") == [])
    }

    @Test func appendAddsDateLineAndBlankLine() {
        let day = DayStamp(year: 2026, month: 10, day: 31)!
        #expect(CaptionFormat.appending("第一次 ＃旅行＃", to: nil, on: day) == "第一次 #旅行#\n— 2026.10.31")
        let two = CaptionFormat.appending("再看", to: "第一次\n— 2026.10.20\n", on: day)
        #expect(two == "第一次\n— 2026.10.20\n\n再看\n— 2026.10.31")
    }

    @Test func finalizeEdit() {
        let day = DayStamp(year: 2026, month: 10, day: 31)!
        #expect(CaptionFormat.finalizingEdit("Sunset", on: day) == "Sunset\n— 2026.10.31")
        #expect(CaptionFormat.finalizingEdit("a\n— 2026.10.20", on: day) == "a\n— 2026.10.20")
        #expect(CaptionFormat.finalizingEdit("  \n ", on: day) == nil)
    }

    @Test func titleSplit() {
        let s = CaptionFormat.splitTitle("和朋友去看展，出口那面墙的颜色一直记得。墙是一种说不上来的绿。")
        #expect(s.title == "和朋友去看展，出口那面墙的颜色一直记得。")
        #expect(s.rest == "墙是一种说不上来的绿。")
        #expect(CaptionFormat.splitTitle("没有标点").title == "没有标点")
    }

    @Test func trailingTagsAreHiddenForDisplay() {
        #expect(CaptionFormat.strippingTrailingTags("风很舒服 #旅行# #镜头测试#") == "风很舒服")
        #expect(CaptionFormat.strippingTrailingTags("和#朋友#吃饭") == "和#朋友#吃饭")
    }

    @Test func renameAndMerge() {
        #expect(CaptionFormat.renamingTag("朋友", to: "好友", in: "和#朋友#吃饭 #朋友#") == "和#好友#吃饭")
        #expect(CaptionFormat.renamingTag("朋友", to: "日常", in: "吃饭 #日常# #朋友#") == "吃饭 #日常#")
        #expect(CaptionFormat.isValidTagName("旅行"))
        #expect(!CaptionFormat.isValidTagName(" 旅行"))
    }

    @Test func cameraBoilerplateIsIgnored() {
        for s in ["FUJIFILM DIGITAL CAMERA GFX100RF", "OLYMPUS DIGITAL CAMERA", "SONY DSC", "LEICA CAMERA AG",
                  "RICOH GR III", "SAMSUNG CAMERA PICTURES", "  Default  ", "KONICA MINOLTA DIGITAL CAMERA"] {
            #expect(CaptionFormat.isCameraBoilerplate(s), "\(s)")
        }
        for s in ["Fujifilm X100 test shot in Kyoto", "第一次用 FUJIFILM 拍日落", "SONY DSC\n今天很冷",
                  "Kamakura, Japan. Shot on Fujifilm X-T5", "LOVE"] {
            #expect(!CaptionFormat.isCameraBoilerplate(s), "\(s)")
        }
    }

    @Test func writingOverwritesCameraBoilerplate() {
        let day = DayStamp(year: 2026, month: 10, day: 31)!
        #expect(CaptionFormat.appending("夕阳", to: "FUJIFILM DIGITAL CAMERA GFX100RF", on: day) == "夕阳\n— 2026.10.31")
    }

    @Test func entryDisplay() {
        let entry = DiaryEntry(id: "1", caption: sample, keywords: [], creationDate: nil, latitude: nil,
                               longitude: nil, mediaKind: .photo, isCloudShared: false, pixelWidth: 4, pixelHeight: 3)
        #expect(entry.title == "风很舒服，第一次用新镜头拍日落")
        #expect(entry.preview == "三年后再看，还是喜欢这张")
        #expect(entry.tagLine == "#旅行# #镜头测试#")
    }

    @Test func hiddenCaptionsMatchExactlyAndGetOverwritten() {
        let defaults = isolatedDefaults()
        defaults.set(["0", " IMG "], forKey: CaptionFilter.defaultsKey)
        let hides = CaptionFilter.matcher(defaults: defaults)
        #expect(hides("0"))
        #expect(hides(" 0\n"))
        #expect(hides("img"))
        #expect(!hides("10"))
        #expect(!hides("0 号线"))
        let day = DayStamp(year: 2026, month: 10, day: 31)!
        #expect(CaptionFormat.appending("夕阳", to: "0", on: day, hidden: hides) == "夕阳\n— 2026.10.31")
    }

    @Test func indexRoundTripRebuildsDerivedFields() throws {
        var entry = DiaryEntry(id: "1", caption: sample, keywords: [], creationDate: Date(timeIntervalSince1970: 1_792_000_000),
                               latitude: nil, longitude: nil, mediaKind: .photo, isCloudShared: false, pixelWidth: 4, pixelHeight: 3)
        // 旧索引里带着 segments、tags 两个键，新格式忽略它们，读入后重新解析。
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as! [String: Any]
        json["segments"] = []
        json["tags"] = ["旧"]
        let decoded = try JSONDecoder().decode(DiaryEntry.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.title == "风很舒服，第一次用新镜头拍日落")
        #expect(decoded.tags == ["旅行", "镜头测试"])
        #expect(decoded == entry)

        // 时区变了，照片日期跟着变。
        entry.timeZoneID = "Pacific/Kiritimati"
        let kiritimati = entry.day
        entry.timeZoneID = "Pacific/Pago_Pago"
        #expect(entry.day != kiritimati)
    }
}
