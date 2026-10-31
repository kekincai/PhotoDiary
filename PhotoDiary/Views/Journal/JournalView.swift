import SwiftUI
import Photos
import PhotosUI

enum JournalMode: String, CaseIterable, Identifiable {
    case list, calendar, media, map
    var id: String { rawValue }
    var title: String {
        switch self {
        case .list: "列表"
        case .calendar: "日历"
        case .media: "照片"
        case .map: "地图"
        }
    }
}

extension EnvironmentValues {
    @Entry var zoomNamespace: Namespace.ID? = nil
}

/// 日记：主题色头部 + 同一份日记的四种视图。
struct JournalView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.brand) private var brand
    @SceneStorage("journalMode") private var mode: JournalMode = .list
    @State private var scrolledPastHeader = false

    var body: some View {
        Group {
            if mode == .map {
                VStack(spacing: 0) {
                    header
                    card(fill: true) { MapContent() }
                }
                .background(brand)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        header
                        card {
                            switch mode {
                            case .list: ListContent()
                            case .calendar: CalendarContent()
                            case .media: MediaGridContent()
                            case .map: EmptyView()
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y + geo.contentInsets.top > 96
                } action: { _, past in
                    withAnimation(.snappy) { scrolledPastHeader = past }
                }
                .background {
                    // 顶部回弹露出主题色，底部露出白色。
                    VStack(spacing: 0) { brand; Color(.systemBackground) }.ignoresSafeArea()
                }
            }
        }
        // 导航栏与头部同色：状态栏和按钮用浅色；头部滚出后在栏中显示标题。
        .toolbarBackground(brand, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("日记 · \(mode.title)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .opacity(scrolledPastHeader ? 1 : 0)
                    .accessibilityHidden(!scrolledPastHeader)
            }
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("日记")
                        .font(.system(size: 34, weight: .bold))
                        .tracking(-0.7)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: subtitle)
                }
                Spacer()
            }
            ModeSwitcher(mode: $mode)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 22)
    }

    private var subtitle: String {
        if case .scanning(let done, let total) = store.syncState, total > 0 {
            return "正在读取照片说明 \(Int(Double(done) / Double(total) * 100))%"
        }
        let month = DateFormatter.zh("LLLL").string(from: .now)
        let n = store.writtenThisMonth
        return n == 0 ? "\(month)还没写日记" : "\(month)写了 \(n) 篇"
    }

    private var moreMenu: some View {
        Menu {
            Button("标签", systemImage: "number") { router.push(.tags) }
            Button("其他来源的说明", systemImage: "doc.text") { router.push(.external) }
            Divider()
            Button("设置", systemImage: "gearshape") { router.showSettings = true }
        } label: {
            Label("更多选项", systemImage: "ellipsis")
        }
    }

    /// fill：地图模式下填满剩余高度，不再撑出最小高度把头部挤出屏幕。
    private func card<Content: View>(fill: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            if store.isLimited { LimitedAccessBanner() }
            content()
        }
        .frame(maxWidth: .infinity, minHeight: fill ? nil : 640, maxHeight: fill ? .infinity : nil, alignment: .top)
        .background(Color(.systemBackground), in: .rect(topLeadingRadius: 22, topTrailingRadius: 22))
    }
}

/// 列表 / 日历 / 照片 / 地图 切换：白色滑块用弹簧跟随。
private struct ModeSwitcher: View {
    @Binding var mode: JournalMode
    @Environment(\.brand) private var brand
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(JournalMode.allCases) { m in
                Button {
                    withAnimation(.snappy) { mode = m }
                } label: {
                    Text(m.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(mode == m ? brand : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if mode == m {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(.white)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.press)
                .accessibilityAddTraits(mode == m ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.black.opacity(0.16), in: .rect(cornerRadius: 12))
        .sensoryFeedback(.selection, trigger: mode)
    }
}

/// 只给了“有限访问”时：提示可以扩大范围。
struct LimitedAccessBanner: View {
    @Environment(\.brand) private var brand

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(brand)
            Text("只显示你允许访问的照片")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.ink)
            Spacer()
            Button("选择更多") { LimitedLibrary.present() }
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(brand.opacity(0.08), in: .rect(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }
}

enum LimitedLibrary {
    static func present() {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              var top = scene.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }
}
