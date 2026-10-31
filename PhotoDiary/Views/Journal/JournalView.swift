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
///
/// 结构始终不变：大标题随内容滚走，切换条吸顶，切换时只替换白色卡片里的内容，
/// 背景和卡片本身不参与过渡，所以不会闪。
struct JournalView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.brand) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SceneStorage("journalMode") private var mode: JournalMode = .list
    @State private var position = ScrollPosition(edge: .top)
    @State private var titleHeight: CGFloat = 96
    @State private var barHeight: CGFloat = 60
    @State private var pastTitle = false

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    titleBlock
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { titleHeight = $0 }
                    Section {
                        // 地图铺到屏幕底边（越过底部安全区，从浮动标签栏下面透出来）。
                        content(viewportHeight: viewport.size.height, bottomInset: viewport.safeAreaInsets.bottom)
                    } header: {
                        pinnedBar
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { barHeight = $0 }
                    }
                }
            }
            .scrollPosition($position)
            .scrollDisabled(mode == .map)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > titleHeight - 8
            } action: { _, past in
                pastTitle = past
            }
            .background {
                // 顶部回弹露出主题色，底部露出卡片的白色。
                VStack(spacing: 0) { brand; Color(.systemBackground) }.ignoresSafeArea()
            }
        }
        .onChange(of: mode) { _, new in
            // 地图不滚动，回到顶部铺满；其他视图保持切换条吸顶的状态。
            if new == .map {
                position.scrollTo(edge: .top)
            } else if pastTitle {
                position.scrollTo(y: titleHeight)
            }
        }
        .toolbarBackground(brand, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("日记")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .opacity(pastTitle ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: pastTitle)
                    .accessibilityHidden(!pastTitle)
            }
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
    }

    // MARK: 头部

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("日记")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.7)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .contentTransition(.numericText())
                .animation(.snappy, value: subtitle)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 16)
    }

    private var subtitle: String {
        if case .scanning(let done, let total) = store.syncState, total > 0 {
            return "正在读取照片说明 \(Int(Double(done) / Double(total) * 100))%"
        }
        let month = DateFormatter.zh("LLLL").string(from: .now)
        let n = store.writtenThisMonth
        return n == 0 ? "\(month)还没写" : "\(month)写了 \(n) 篇"
    }

    /// 吸顶部分：切换条，以及卡片的圆角上沿（日历视图里同时是星期行）。
    private var pinnedBar: some View {
        VStack(spacing: 0) {
            ModeSwitcher(mode: $mode)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .background(brand)
            if mode != .map {
                Group {
                    if mode == .calendar {
                        WeekdayRow()
                            .padding(.horizontal, 12)
                            .padding(.top, 14)
                            .padding(.bottom, 6)
                    } else {
                        Color.clear.frame(height: 10)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground), in: .rect(topLeadingRadius: 22, topTrailingRadius: 22))
                .background(brand)
            }
        }
    }

    @ViewBuilder
    private func content(viewportHeight: CGFloat, bottomInset: CGFloat) -> some View {
        Group {
            switch mode {
            case .list: ListContent()
            case .calendar: CalendarContent()
            case .media: MediaGridContent()
            case .map:
                MapContent()
                    .frame(height: max(320, viewportHeight + bottomInset - titleHeight - barHeight))
                    .clipShape(.rect(topLeadingRadius: 22, topTrailingRadius: 22))
                    .background(brand)
            }
        }
        .frame(maxWidth: .infinity, minHeight: mode == .map ? 0 : viewportHeight, alignment: .top)
        .background(Color(.systemBackground))
        .id(mode)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: mode)
    }

    private var moreMenu: some View {
        Menu {
            Button("标签", systemImage: "number") { router.push(.tags) }
            Divider()
            Button("设置", systemImage: "gearshape") { router.showSettings = true }
        } label: {
            Label("更多选项", systemImage: "ellipsis")
        }
    }
}

/// 列表 / 日历 / 照片 / 地图 切换：白色滑块跟着弹簧走，内容立即替换。
private struct ModeSwitcher: View {
    @Binding var mode: JournalMode
    @Environment(\.brand) private var brand
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(JournalMode.allCases) { m in
                Button {
                    mode = m
                } label: {
                    Text(m.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(mode == m ? brand : .white.opacity(0.92))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if mode == m {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
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
        .background(.black.opacity(0.16), in: .rect(cornerRadius: 12, style: .continuous))
        .animation(.snappy, value: mode)
        .sensoryFeedback(.selection, trigger: mode)
    }
}

/// 只给了“有限访问”时：提示可以扩大范围。
struct LimitedAccessBanner: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("只显示了你允许访问的照片。")
                .font(.footnote)
                .foregroundStyle(Color.meta)
            Spacer(minLength: 0)
            Button("选择更多") { LimitedLibrary.present() }
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 1) }
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
