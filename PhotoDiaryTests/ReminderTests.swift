import Testing
import Foundation
@testable import PhotoDiary

/// 晚间提醒排哪几条、提醒写哪一张。
struct ReminderPlanTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()

    func at(_ hour: Int, _ minute: Int = 0, day: Int = 7) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func plan(now: Date, minutes: Int = 21 * 60, photos: Int, wrote: Bool, following: Int = 3) -> [Reminder.Item] {
        Reminder.plan(now: now, minutes: minutes, todayPhotoCount: photos, wroteToday: wrote,
                      followingDays: following, calendar: calendar)
    }

    @Test func todayWithPhotosAndNothingWrittenGetsCountedReminder() {
        let items = plan(now: at(18), photos: 8, wrote: false)
        #expect(items.first == Reminder.Item(dayOffset: 0, date: at(21), photoCount: 8))
        // 往后三天各一条通用的。
        #expect(items.dropFirst().map(\.dayOffset) == [1, 2, 3])
        #expect(items.dropFirst().allSatisfy { $0.photoCount == nil })
        #expect(items[1].date == at(21, day: 8))
        #expect(items[3].date == at(21, day: 10))
    }

    /// 早上打开 App 时今天还没拍：照样排今天的（通用文字），之后拍了照片不会唤醒 App 重排。
    @Test func noPhotosYetTodayStillGetsGenericReminder() {
        let items = plan(now: at(8), photos: 0, wrote: false)
        #expect(items.map(\.dayOffset) == [0, 1, 2, 3])
        #expect(items.first?.photoCount == nil)
    }

    @Test func alreadyWroteTodaySkipsToday() {
        let items = plan(now: at(18), photos: 5, wrote: true)
        #expect(items.map(\.dayOffset) == [1, 2, 3])
    }

    @Test func timeAlreadyPassedSkipsToday() {
        #expect(plan(now: at(21, 30), photos: 5, wrote: false).map(\.dayOffset) == [1, 2, 3])
        // 正好到点也不排了（系统不会补发过去的时间）。
        #expect(plan(now: at(21), photos: 5, wrote: false).map(\.dayOffset) == [1, 2, 3])
    }

    @Test func customTimeIsUsed() {
        let items = plan(now: at(7), minutes: 8 * 60 + 15, photos: 1, wrote: false, following: 1)
        #expect(items.map(\.date) == [at(8, 15), at(8, 15, day: 8)])
        #expect(items[0].photoCount == 1)
    }

    @Test func crossesMonthEnd() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 22))!
        let items = plan(now: now, photos: 3, wrote: false, following: 2)
        let days = items.map { calendar.dateComponents([.month, .day], from: $0.date) }
        #expect(days.map(\.month) == [12, 12])
        #expect(days.map(\.day) == [1, 2])
    }

    // MARK: 写哪一张

    let early = Date(timeIntervalSince1970: 1_000)
    let late = Date(timeIntervalSince1970: 2_000)
    let latest = Date(timeIntervalSince1970: 3_000)

    @Test func prefersFavourite() {
        let photos = [
            Reminder.Photo(id: "a", date: early, isFavorite: true),
            Reminder.Photo(id: "b", date: latest, isFavorite: false),
        ]
        #expect(Reminder.choosePhoto(photos) == "a")
    }

    @Test func latestFavouriteAmongSeveral() {
        let photos = [
            Reminder.Photo(id: "a", date: early, isFavorite: true),
            Reminder.Photo(id: "b", date: late, isFavorite: true),
            Reminder.Photo(id: "c", date: latest, isFavorite: false),
        ]
        #expect(Reminder.choosePhoto(photos) == "b")
    }

    @Test func otherwiseLatest() {
        let photos = [
            Reminder.Photo(id: "a", date: late, isFavorite: false),
            Reminder.Photo(id: "b", date: latest, isFavorite: false),
            Reminder.Photo(id: "c", date: early, isFavorite: false),
        ]
        #expect(Reminder.choosePhoto(photos) == "b")
    }

    @Test func skipsPhotosWithDiary() {
        let photos = [
            Reminder.Photo(id: "fav", date: latest, isFavorite: true, hasDiary: true),
            Reminder.Photo(id: "a", date: early, isFavorite: false),
            Reminder.Photo(id: "b", date: late, isFavorite: false, hasDiary: true),
        ]
        #expect(Reminder.choosePhoto(photos) == "a")
        #expect(Reminder.choosePhoto(photos.map { var p = $0; p.hasDiary = true; return p }) == nil)
        #expect(Reminder.choosePhoto([]) == nil)
    }

    // MARK: 今天写了没有

    @Test func wroteTodayLooksAtWritingDates() {
        let today = DayStamp(year: 2026, month: 11, day: 7)!
        let old = entry("1", "旧的\n— 2026.11.01", date(2026, 11, 1))
        let appended = entry("2", "旧的\n— 2026.10.01\n\n今天补一句\n— 2026.11.07", date(2026, 10, 1))
        let undated = entry("3", "照片 App 里写的", date(2026, 11, 7))
        #expect(!Reminder.wrote(on: today, in: [old, undated]))
        #expect(Reminder.wrote(on: today, in: [old, appended]))
    }

    private func entry(_ id: String, _ caption: String, _ created: Date) -> DiaryEntry {
        DiaryEntry(id: id, caption: caption, keywords: [], creationDate: created, latitude: nil, longitude: nil,
                   mediaKind: .photo, isCloudShared: false, pixelWidth: 1, pixelHeight: 1)
    }
}
