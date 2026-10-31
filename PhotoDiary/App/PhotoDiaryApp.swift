import SwiftUI
import Photos
import OSLog

@main
struct PhotoDiaryApp: App {
    @State private var store = DiaryStore()
    @State private var router = Router()
    @AppStorage("brand") private var brand: BrandColor = .lake
    /// 设置里改语言时先调用 AppLanguage.apply，再写入这里，界面整体按新语言重建。
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppLanguage.apply(AppLanguage.stored)
    }

    static let isHostingUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .environment(\.brand, brand.color)
                .tint(brand.color)
                .environment(\.locale, AppLanguage.current.locale)
                .id(language)
                .task {
                    // 作为单元测试宿主启动时不读照片库：测试用自己的假照片库，不能改到模拟器里的照片。
                    guard !Self.isHostingUnitTests else { return }
                    DiaryFonts.shared.prepare()
                    await store.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    Log.app.debug("scenePhase → \(String(describing: phase), privacy: .public)")
                    if phase == .active { store.refreshAuthorization() }
                }
        }
    }
}
