import SwiftUI
import Photos
import UIKit
import OSLog

@main
struct PhotoDiaryApp: App {
    @State private var store: DiaryStore
    @State private var router = Router()
    @State private var intelligence = Intelligence.forLaunch()
    @State private var reminders = ReminderScheduler.shared
    /// 主题色的十六进制值：预设或在调色板里自选的。
    @AppStorage(BrandColor.storageKey) private var brandHex = BrandColor.lake.rawValue
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system
    /// 设置里改语言时先调用 AppLanguage.apply，再写入这里，界面整体按新语言重建。
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @AppStorage(WeekStart.storageKey) private var weekStart: WeekStart = .default
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 界面测试每次都从“跟随系统”开始（系统语言由测试指定），上一个测试切过的语言不留下来。
        if Self.isUITesting { UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey) }
        AppLanguage.apply(AppLanguage.stored)
        // 读索引之前就定下一周从哪天开始，按周归并的数据才对。
        Calendar.diaryFirstWeekday = WeekStart.stored.rawValue
        // 点通知启动 App 时，系统在 didFinishLaunching 返回前就要找到通知的代理。
        ReminderScheduler.shared.activate()
        let store = DiaryStore()
        // 第一帧还没画就开始读索引。
        if !Self.isHostingUnitTests { store.prepare() }
        if Self.isUITesting { UIView.setAnimationsEnabled(false) }
        _store = State(initialValue: store)
    }

    static let isHostingUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    /// 界面测试启动时传 -uiTesting：关掉动画。系统菜单打开后一直等不到“动画结束”，每一步都要白等 60 秒。
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
    private static var openedTestingLink = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .environment(intelligence)
                .environment(\.brand, .brand(hex: brandHex))
                .tint(.brand(hex: brandHex))
                .environment(\.locale, AppLanguage.current.locale)
                .id(language)
                .onChange(of: language) {
                    store.placeLanguageChanged()
                    // 通知上的按钮和提醒文字按新语言重写。
                    reminders.registerCategory()
                    reminders.rescheduleSoon(store: store)
                    WidgetBridge.shared.scheduleUpdate()
                }
                .onAppear {
                    appearance.apply()
                    Self.limitMacWindowSize()
                }
                .onChange(of: appearance) { appearance.apply() }
                .onChange(of: weekStart) {
                    Calendar.diaryFirstWeekday = weekStart.rawValue
                    store.weekStartChanged()
                }
                .task {
                    // 作为单元测试宿主启动时不读照片库：测试用自己的假照片库，不能改到模拟器里的照片。
                    guard !Self.isHostingUnitTests else { return }
                    DiaryFonts.shared.prepare()
                    WatchBridge.shared.start(store: store)
                    WidgetBridge.shared.start(store: store)
                    await store.start()
                    // 每次打开都重排：往后几天的通用提醒换成按今天实际情况算的。
                    await reminders.reschedule(store: store)
                    if Self.isUITesting { await reminders.simulateReplyForUITests(store: store) }
                }
                // 点开了晚间提醒：索引读好后打开那张照片的编辑器。
                .onChange(of: reminders.pending, initial: true) { openPendingReminder() }
                .onChange(of: store.hasLoaded) { openPendingReminder() }
                .onChange(of: scenePhase) { _, phase in
                    Log.app.debug("scenePhase → \(String(describing: phase), privacy: .public)")
                    if phase == .active {
                        store.refreshAuthorization()
                        intelligence.refreshAvailability()
                        WatchBridge.shared.resume()
                        // 过了零点、在别处改过照片：小组件的那年今日和“今天写过没有”重算一遍。
                        WidgetBridge.shared.scheduleUpdate()
                    }
                    if phase == .background { saveInBackground() }
                }
                // 小组件、控制中心、快捷指令都是 photodiary:// 链接（快捷指令直接放进 DeepLinkInbox）。
                .onOpenURL { url in
                    guard let link = DeepLink(url: url) else { return }
                    DeepLinkInbox.shared.open(link)
                }
                .onAppear(perform: openTestingLink)
                // 照片库能读了才打开：还没授权、索引还没读出来时先留着。
                .onChange(of: DeepLinkInbox.shared.pending) { openPendingLink() }
                .onChange(of: store.canRead, initial: true) { openPendingLink() }
                // 日记一变就把快照发给 Apple Watch（防抖）。
                .onChange(of: store.diaries) {
                    WatchBridge.shared.scheduleSync()
                    // 今天写了日记，今晚就不用提醒了。
                    if !Self.isHostingUnitTests { reminders.rescheduleSoon(store: store) }
                    WidgetBridge.shared.scheduleUpdate()
                }
                .onChange(of: store.hasLoaded) { WidgetBridge.shared.scheduleUpdate() }
                .onChange(of: store.canRead) { WidgetBridge.shared.scheduleUpdate() }
                // 日记列表一变就在后台把这些照片的 PHAsset 取齐，界面上滚动时不再查照片库。
                .onChange(of: store.diaries, initial: true) { AssetImages.shared.warm(ids: store.diaries.map(\.id)) }
        }
        .commands { AppCommands(router: router, canRead: store.canRead) }
    }

    private func openPendingLink() {
        guard store.canRead, !Self.isHostingUnitTests, let link = DeepLinkInbox.shared.take() else { return }
        var latest: Router.LatestPhoto?
        if link == .writeLatest, let id = AssetImages.recentAssets(limit: 1).first?.id {
            latest = Router.LatestPhoto(id: id, hasDiary: store.entry(id) != nil || store.currentCaption(for: id) != nil)
        }
        Log.app.info("打开链接 \(link.url.absoluteString, privacy: .public)")
        router.open(link, latestPhoto: latest)
    }

    /// 界面测试用 -openURL photodiary://… 启动，当作系统送来的链接（XCUITest 点不了小组件）。
    private func openTestingLink() {
        guard Self.isUITesting, !Self.openedTestingLink else { return }
        Self.openedTestingLink = true
        guard let string = UserDefaults.standard.string(forKey: "openURL"),
              let url = URL(string: string), let link = DeepLink(url: url) else { return }
        DeepLinkInbox.shared.open(link)
    }

    /// Mac 上窗口别缩得比 iPad 竖屏还窄：再窄就退成手机布局，标签栏和“+”会挤在一起。
    private static func limitMacWindowSize() {
        #if targetEnvironment(macCatalyst)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.sizeRestrictions?.minimumSize = CGSize(width: 760, height: 600)
        }
        #endif
    }

    /// 进入后台时立即保存索引、重排晚间提醒，并向系统要一点时间保证做完。
    private func saveInBackground() {
        let task = BackgroundTask()
        task.id = UIApplication.shared.beginBackgroundTask(withName: "保存索引") { task.end() }
        Task {
            await store.saveNow()
            if !Self.isHostingUnitTests { await reminders.reschedule(store: store) }
            task.end()
        }
    }

    private func openPendingReminder() {
        guard let response = reminders.pending, store.hasLoaded else { return }
        reminders.pending = nil
        Task {
            // 正在写的编辑器不顶掉，免得丢字。
            guard router.editor == nil,
                  let request = await reminders.editorRequest(for: response, store: store) else { return }
            // 别的面板开着时先收起，编辑器才弹得出来。
            if router.showSettings || router.showAddFromPhotos {
                router.showSettings = false
                router.showAddFromPhotos = false
                try? await Task.sleep(for: .milliseconds(600))
            }
            router.editor = request
        }
    }
}

/// 菜单栏（Mac）和硬件键盘（iPad）的快捷键。
/// 菜单不在界面的环境里，拿不到 App 内选的语言，文字要自己按 .app 查表。
private struct AppCommands: Commands {
    let router: Router
    let canRead: Bool

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(String(localized: "设置…", bundle: .app, locale: .app)) { router.showSettings = true }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "从照片写日记", bundle: .app, locale: .app)) { router.showAddFromPhotos = true }
                .keyboardShortcut("n")
                .disabled(!canRead)
        }
        CommandGroup(before: .sidebar) {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { router.tab = tab }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                    .disabled(!canRead)
            }
            Divider()
        }
    }
}

private final class BackgroundTask {
    var id = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
