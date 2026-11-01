import SwiftUI
import Photos

/// 首次打开：说明为什么需要完整的照片库读写权限。系统“欢迎页”的样式：图标、标题、三条要点、底部一个主要按钮。
struct PermissionView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.brand) private var brand
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var requesting = false
    @State private var appeared = false

    private var denied: Bool { store.authorization == .denied || store.authorization == .restricted }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            icon
                .padding(.bottom, Metrics.Spacing.xl)
            Text("把日记写在\n照片的说明里")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.5)
                .lineSpacing(2)
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, Metrics.Spacing.xxl)

            VStack(alignment: .leading, spacing: Metrics.Spacing.xl) {
                point("photo.on.rectangle.angled", "不复制照片", "只在原照片上标注，微单拍的大文件也不会多占一份空间")
                point("icloud", "随照片同步", "日记经 iCloud 同步，在照片 App 里可见、可搜索")
                point("arrow.triangle.2.circlepath", "两边都能写", "在照片 App 的说明栏写，也会出现在这里")
            }
            Spacer(minLength: 0)
            Spacer(minLength: 0)

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
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(brand)
            .disabled(requesting)

            // 第一次请求时系统弹窗自带用途说明；只有被拒绝后才说明需要什么权限。
            if denied {
                Text("需要“完整访问”才能读取和写入照片说明。也可以只选部分照片。")
                    .font(.footnote)
                    .foregroundStyle(Color.meta)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, Metrics.Spacing.l)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, Metrics.Spacing.m)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.35)) { appeared = true } }
    }

    /// 和 App 图标一样的书签，放在主题色的圆角方块上。
    private var icon: some View {
        let palette: MarkPalette = colorScheme == .dark ? .dark : .light
        return BrandMark(width: 40, palette: palette)
            .frame(width: 88, height: 88)
            .background(
                LinearGradient(colors: [brand.opacity(0.85), brand], startPoint: .top, endPoint: .bottom),
                in: .rect(cornerRadius: 20, style: .continuous))
            .shadow(color: brand.opacity(0.3), radius: 16, y: 8)
            .accessibilityHidden(true)
    }

    private func point(_ symbol: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Metrics.Spacing.l) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(brand)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(Color.ink)
                Text(text).font(.subheadline).foregroundStyle(Color.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
