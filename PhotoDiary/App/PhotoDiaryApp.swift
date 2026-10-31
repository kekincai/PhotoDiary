import SwiftUI
import Photos

@main
struct PhotoDiaryApp: App {
    @State private var store = DiaryStore()
    @State private var router = Router()
    @AppStorage("brand") private var brand: BrandColor = .lake
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .environment(\.brand, brand.color)
                .tint(brand.color)
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
