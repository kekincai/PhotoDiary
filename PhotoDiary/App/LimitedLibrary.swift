import UIKit
import Photos
import PhotosUI

/// “有限访问”时弹出系统的照片选择器，让用户扩大范围。
enum LimitedLibrary {
    /// 新选进来的照片不会出现在增量变化里，选了就全库重读（有限访问时照片不多，很快）。
    static func present(store: DiaryStore) {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              var top = scene.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top, completionHandler: pickerFinished(store: store))
    }

    /// 选择器关掉时的回调。系统在后台队列上调它：必须是 @Sendable，不能带主线程隔离。
    static func pickerFinished(store: DiaryStore) -> @Sendable ([String]) -> Void {
        nonisolated(unsafe) let store = store
        return { added in
            guard !added.isEmpty else { return }
            Task { @MainActor in store.rebuildIndex() }
        }
    }
}

extension URL {
    /// 改照片权限的地方：iPhone 上是本 App 的设置页；Mac 上是“隐私与安全性 › 照片”（App 自己的设置页里没有照片权限）。
    static var photoAccessSettings: URL? {
        #if targetEnvironment(macCatalyst)
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")
        #else
        URL(string: UIApplication.openSettingsURLString)
        #endif
    }
}
