import SwiftUI
import Photos

/// 首次打开：说明为什么需要完整的照片库读写权限。
struct PermissionView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.brand) private var brand
    @Environment(\.openURL) private var openURL
    @State private var requesting = false

    private var denied: Bool { store.authorization == .denied || store.authorization == .restricted }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Text("把日记写在\n照片的说明里")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.7)
                .lineSpacing(2)
                .foregroundStyle(.white)
                .padding(.bottom, 28)

            VStack(alignment: .leading, spacing: 16) {
                point("photo.on.rectangle", "不复制照片", "只在原照片上标注，微单拍的大文件也不会多占一份空间")
                point("icloud", "随照片同步", "日记经 iCloud 同步，在照片 App 里可见、可搜索")
                point("arrow.triangle.2.circlepath", "两边都能写", "在照片 App 的说明栏写，也会出现在这里")
            }
            Spacer()
            Spacer()

            Button {
                if denied {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } else {
                    requesting = true
                    Task { await store.requestAccess(); requesting = false }
                }
            } label: {
                (denied ? Text("前往“设置”允许访问照片") : Text("允许访问照片"))
                    .font(.headline)
                    .foregroundStyle(brand)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(.white, in: .capsule)
            }
            .buttonStyle(.press)
            .disabled(requesting)

            (denied ? Text("需要“完整访问”才能读取和写入照片说明。也可以只选部分照片。")
                    : Text("需要读写照片说明。选择“有限访问”也可以使用，但只会显示你选的照片。"))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 16)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(brand)
    }

    private func point(_ symbol: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }
}
