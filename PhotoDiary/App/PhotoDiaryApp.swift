import SwiftUI
import Photos

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
                    DiaryFonts.shared.prepare()
                    await store.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.refreshAuthorization() }
                }
        }
    }
}
