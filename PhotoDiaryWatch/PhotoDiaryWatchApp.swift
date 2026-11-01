import SwiftUI

/// Apple Watch 上的照片日记：回看最近的日记和那年今日，给还没写的照片口述一段。
/// 表上没有照片库，所有内容都是 iPhone 发来的快照；口述的内容发回 iPhone 写进照片说明。
@main
struct PhotoDiaryWatchApp: App {
    @State private var store = WatchStore.shared

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(store)
                .task { store.start() }
        }
    }
}
