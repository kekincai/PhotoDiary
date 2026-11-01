import Testing
import Foundation
@testable import PhotoDiary

/// iPhone 和 Apple Watch 之间传的东西：编码来回一致，说明在表上解析出的结果和 iPhone 相同。
struct WatchSyncTests {
    @Test func snapshotRoundTrip() throws {
        let entry = WatchEntry(id: "A/L0/001", caption: "风很舒服 #旅行#\n— 2026.10.31\n\n三年后再看\n— 2029.11.02",
                               day: DayStamp(year: 2026, month: 10, day: 31)!, placeName: "杉并区", mediaKind: .livePhoto)
        let snapshot = WatchSnapshot(generated: date(2026, 10, 31), today: DayStamp(date(2026, 10, 31)), entries: [entry],
                                     onThisDay: ["A/L0/001"], week: [WatchWeekDay(day: DayStamp(date(2026, 10, 25)), wrote: true)],
                                     writtenThisWeek: 1, writtenThisMonth: 3,
                                     unwritten: [WatchPhoto(id: "B/L0/002", day: nil)], tags: ["旅行"])
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WatchSnapshot.self, from: data)
        #expect(decoded == snapshot)
        #expect(decoded.imageIDs == ["A/L0/001", "B/L0/002"])
        #expect(data.count < 2000)
    }

    @Test func watchEntryParsesLikePhone() {
        let caption = "买到了熟透的无花果。切开的时候汁水流到桌布上 #美食#\n— 2026.10.30"
        let entry = WatchEntry(id: "x", caption: caption, day: DayStamp(year: 2026, month: 10, day: 30)!,
                               placeName: nil, mediaKind: .photo).entry
        let phone = DiaryEntry(id: "x", caption: caption, keywords: [], creationDate: date(2026, 10, 30), latitude: nil,
                               longitude: nil, mediaKind: .photo, isCloudShared: false, pixelWidth: 0, pixelHeight: 0)
        #expect(entry.title == phone.title)
        #expect(entry.preview == phone.preview)
        #expect(entry.tags == ["美食"])
        #expect(entry.day == phone.day)
    }

    @Test func messagesRoundTrip() throws {
        let write = WatchWrite(assetID: "A/L0/001", text: "过了些日子再看", mode: .append)
        let cases: [WatchMessage] = [.refresh, .thumbnails(ids: ["a", "b"]), .images(["a": Data([1, 2, 3])]),
                                     .write(write), .wrote(write.id), .ok]
        for message in cases {
            let back = try #require(WatchMessage(data: message.data))
            #expect(back == message)
        }
        let viaUserInfo = try #require(WatchMessage(userInfo: WatchMessage.write(write).userInfo))
        guard case .write(let received) = viaUserInfo else { Issue.record("不是写入消息"); return }
        #expect(received == write)
        #expect(WatchMessage(userInfo: ["other": 1]) == nil)
    }
}
