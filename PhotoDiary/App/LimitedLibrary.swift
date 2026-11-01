import UIKit
import Photos
import PhotosUI

/// “有限访问”时弹出系统的照片选择器，让用户扩大范围。
enum LimitedLibrary {
    static func present() {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              var top = scene.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }
}
