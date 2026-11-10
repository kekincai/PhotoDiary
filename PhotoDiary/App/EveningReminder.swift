import Foundation
import Photos
import UserNotifications
import OSLog

// MARK: 晚间提醒：今天拍了照片、还没写日记的晚上，提醒写一句。
//
// 本地通知到点时没法再判断“今天写没写”，所以每次进后台、日记变了、改了设置都重排一次：
// 今天已经拍了、还没写：排带张数的一条；今天还没拍（早上打开过 App，之后拍照不会唤醒 App 重排）：排通用的一条；
// 今天写过了就不排。往后几天排通用的一条，下次打开 App 时整组换掉。“拍了”包括视频。

/// 不碰界面和照片库的部分：常量、排期、挑照片。都是纯函数，单元测试直接调。
nonisolated enum Reminder {
    static let enabledKey = "eveningReminder"
    /// 提醒时间：当天零点起的分钟数。
    static let timeKey = "eveningReminderTime"
    static let defaultMinutes = 21 * 60
    static let category = "evening"
    static let replyAction = "evening.reply"
    static let assetKey = "assetID"
    static let identifierPrefix = "evening-"
    /// 今天之后再排几天的通用提醒。
    static let followingDays = 6
    /// 界面测试用：启动参数 -reminderReply <文字> 模拟“写一句”的回复。
    static let uiTestReplyKey = "reminderReply"

    static var identifiers: [String] { (0...followingDays).map { identifierPrefix + String($0) } }

    struct Item: Equatable, Sendable {
        /// 0 是今天。
        var dayOffset: Int
        var date: Date
        /// 今天的张数；往后几天不知道，是 nil（通用文字）。
        var photoCount: Int?
    }

    /// 排哪几条提醒。今天：还没写、提醒时间还没过（拍了照片就带张数，还没拍就是通用的）；往后每天一条通用的。
    static func plan(now: Date, minutes: Int, todayPhotoCount: Int, wroteToday: Bool,
                     followingDays: Int = followingDays, calendar: Calendar = .diary) -> [Item] {
        let start = calendar.startOfDay(for: now)
        var items: [Item] = []
        for offset in 0...followingDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let fire = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                  fire > now else { continue }
            if offset == 0 {
                guard !wroteToday else { continue }
                items.append(Item(dayOffset: 0, date: fire, photoCount: todayPhotoCount > 0 ? todayPhotoCount : nil))
            } else {
                items.append(Item(dayOffset: offset, date: fire, photoCount: nil))
            }
        }
        return items
    }

    struct Photo: Equatable, Sendable {
        var id: String
        var date: Date
        var isFavorite: Bool
        var hasDiary = false
    }

    /// 提醒写哪一张：还没写的里面，优先收藏的，其次最后拍的。
    static func choosePhoto(_ photos: [Photo]) -> String? {
        let open = photos.filter { !$0.hasDiary }
        let latest = { (list: [Photo]) in list.max { $0.date < $1.date } }
        return (latest(open.filter(\.isFavorite)) ?? latest(open))?.id
    }

    /// 这一天写过日记没有（任何一条说明里有这一天的写作日期行）。
    static func wrote(on day: DayStamp, in diaries: [DiaryEntry]) -> Bool {
        diaries.contains { $0.writingDays.contains(day) }
    }

    /// 这一天拍的照片和视频（不读说明）。没有照片权限时是空的。
    static func photos(on day: DayStamp) -> [Photo] {
        let calendar = Calendar.diary
        let start = calendar.startOfDay(for: day.date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@ AND (mediaType == %d OR mediaType == %d)",
                                        start as NSDate, end as NSDate, PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        options.includeAssetSourceTypes = LibraryScanner.sourceTypes
        let result = PHAsset.fetchAssets(with: options)
        var out: [Photo] = []
        result.enumerateObjects { asset, _, _ in
            out.append(Photo(id: asset.localIdentifier, date: asset.creationDate ?? start, isFavorite: asset.isFavorite))
        }
        return out
    }

    static func exists(_ id: String) -> Bool {
        let options = PHFetchOptions()
        options.includeAssetSourceTypes = LibraryScanner.sourceTypes
        return PHAsset.fetchAssets(withLocalIdentifiers: [id], options: options).count > 0
    }

    /// 点开或回复了通知：交给界面打开编辑器。
    struct Response: Equatable, Sendable {
        var assetID: String?
        var day: DayStamp
        var reply: String?
    }
}

/// 排提醒、问通知权限、接住点开的通知。
@Observable
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    /// 点开通知后等着界面处理的请求（冷启动时界面和索引都还没准备好）。
    var pending: Reminder.Response?

    private let delegate = ReminderNotificationDelegate()
    private var debounce: Task<Void, Never>?

    private var center: UNUserNotificationCenter { .current() }

    /// App 启动时尽早调用：系统可能正是因为点了通知才启动 App。
    func activate() {
        center.delegate = delegate
        registerCategory()
    }

    /// 通知上的“写一句”：直接在通知里输入，回到 App 后在编辑器里确认（写照片说明可能要系统确认，不在后台悄悄写）。
    /// 文字按当前界面语言，换语言后再调一次。
    func registerCategory() {
        let reply = UNTextInputNotificationAction(
            identifier: Reminder.replyAction,
            title: String(localized: "写一句", bundle: .app, locale: .app),
            options: [.foreground],
            textInputButtonTitle: String(localized: "继续", bundle: .app, locale: .app),
            textInputPlaceholder: "")
        let category = UNNotificationCategory(identifier: Reminder.category, actions: [reply], intentIdentifiers: [])
        center.setNotificationCategories([category])
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Reminder.enabledKey) }

    var minutes: Int {
        UserDefaults.standard.object(forKey: Reminder.timeKey) as? Int ?? Reminder.defaultMinutes
    }

    /// 打开提醒时问通知权限。拒绝过的话系统不再弹窗，直接返回 false。
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    /// 日记变化时连着来好几次，等一下再排。
    func rescheduleSoon(store: DiaryStore) {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await reschedule(store: store)
        }
    }

    func reschedule(store: DiaryStore) async {
        center.removePendingNotificationRequests(withIdentifiers: Reminder.identifiers)
        guard isEnabled else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let now = Date.now
        let today = DayStamp(now)
        var photos = store.canRead ? await Task.detached { Reminder.photos(on: today) }.value : []
        for index in photos.indices { photos[index].hasDiary = store.entry(photos[index].id) != nil }
        let items = Reminder.plan(now: now, minutes: minutes, todayPhotoCount: photos.count,
                                  wroteToday: Reminder.wrote(on: today, in: store.diaries))

        for item in items {
            let content = UNMutableNotificationContent()
            if let count = item.photoCount {
                content.body = String(localized: "今天拍了 \(count) 张，写一句？", bundle: .app, locale: .app)
                if let id = Reminder.choosePhoto(photos) { content.userInfo = [Reminder.assetKey: id] }
            } else {
                content.body = String(localized: "今天的照片，写一句？", bundle: .app, locale: .app)
            }
            content.sound = .default
            content.categoryIdentifier = Reminder.category
            let components = Calendar.diary.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let request = UNNotificationRequest(identifier: Reminder.identifierPrefix + String(item.dayOffset), content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            do {
                try await center.add(request)
            } catch {
                Log.app.error("排晚间提醒失败：\(error, privacy: .public)")
            }
        }
        Log.app.info("晚间提醒：排了 \(items.count) 条，今天 \(photos.count) 张")
    }

    /// 通知对应的编辑器。通知里没有照片（往后几天的通用提醒）就现挑那天的；照片已经删了就只打开 App。
    func editorRequest(for response: Reminder.Response, store: DiaryStore) async -> EditorRequest? {
        let id: String?
        if let assetID = response.assetID {
            id = await Task.detached { Reminder.exists(assetID) }.value ? assetID : nil
        } else {
            let day = response.day
            var photos = await Task.detached { Reminder.photos(on: day) }.value
            for index in photos.indices { photos[index].hasDiary = store.entry(photos[index].id) != nil }
            id = Reminder.choosePhoto(photos)
        }
        guard let id else { return nil }
        let reply = response.reply?.trimmingCharacters(in: .whitespacesAndNewlines)
        return EditorRequest(assetID: id, mode: store.entry(id) == nil ? .new : .append,
                             seed: reply?.isEmpty == false ? reply : nil)
    }

    /// 界面测试点不了真的通知：用启动参数模拟一次“写一句”的回复，写进最近一张还没写的照片。
    func simulateReplyForUITests(store: DiaryStore) async {
        guard let reply = UserDefaults.standard.string(forKey: Reminder.uiTestReplyKey) else { return }
        let recent = await Task.detached { AssetImages.recentAssets(limit: 60) }.value
        guard let photo = recent.first(where: { store.entry($0.id) == nil }) else { return }
        pending = Reminder.Response(assetID: photo.id, day: DayStamp(.now), reply: reply)
    }
}

/// 系统在自己的队列上调这些方法：必须 nonisolated，拿到的值再交给主线程（见 CLAUDE.md）。
/// 用带 completionHandler 的版本：async 版本由系统在后台线程上调完成回调，旧系统上会撞主线程断言。
/// 这里在主线程上把值交出去之后再调完成回调。
nonisolated final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    /// App 开着的时候到点也照样显示。
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        guard content.categoryIdentifier == Reminder.category,
              response.actionIdentifier != UNNotificationDismissActionIdentifier else {
            completionHandler()
            return
        }
        let opened = Reminder.Response(assetID: content.userInfo[Reminder.assetKey] as? String,
                                       day: DayStamp(response.notification.date),
                                       reply: (response as? UNTextInputNotificationResponse)?.userText)
        nonisolated(unsafe) let done = completionHandler
        DispatchQueue.main.async {
            MainActor.assumeIsolated { ReminderScheduler.shared.pending = opened }
            done()
        }
    }
}
