import SwiftUI
import Photos
import OSLog

@main
struct PhotoDiaryApp: App {
    @State private var store: DiaryStore
    @State private var router = Router()
    /// 主题色的十六进制值：预设或在调色板里自选的。
    @AppStorage(BrandColor.storageKey) private var brandHex = BrandColor.lake.rawValue
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system
    /// 设置里改语言时先调用 AppLanguage.apply，再写入这里，界面整体按新语言重建。
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppLanguage.apply(AppLanguage.stored)
        let store = DiaryStore()
        // 第一帧还没画就开始读索引。
        if !Self.isHostingUnitTests { store.prepare() }
        _store = State(initialValue: store)
    }

    static let isHostingUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .environment(\.brand, .brand(hex: brandHex))
                .tint(.brand(hex: brandHex))
                .environment(\.locale, AppLanguage.current.locale)
                .id(language)
                .onChange(of: language) { store.placeLanguageChanged() }
                .onAppear { appearance.apply() }
                .onChange(of: appearance) { appearance.apply() }
                .task {
                    // 作为单元测试宿主启动时不读照片库：测试用自己的假照片库，不能改到模拟器里的照片。
                    guard !Self.isHostingUnitTests else { return }
                    DiaryFonts.shared.prepare()
                    WatchBridge.shared.start(store: store)
                    await store.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    Log.app.debug("scenePhase → \(String(describing: phase), privacy: .public)")
                    if phase == .active {
                        store.refreshAuthorization()
                        WatchBridge.shared.resume()
                    }
                    if phase == .background { saveInBackground() }
                }
                // 日记一变就把快照发给 Apple Watch（防抖）。
                .onChange(of: store.diaries) { WatchBridge.shared.scheduleSync() }
        }
    }

    /// 进入后台时立即保存索引，并向系统要一点时间保证写完。
    private func saveInBackground() {
        let task = BackgroundTask()
        task.id = UIApplication.shared.beginBackgroundTask(withName: "保存索引") { task.end() }
        Task {
            await store.saveNow()
            task.end()
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
