import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

/// 日记详情：照片顶到屏幕最上，按钮浮在照片上；正文之后是地点和标签胶囊；底部分享和“追加感想”。
/// 不显示拍摄参数、相机、文件大小等照片元信息。
struct EntryDetailView: View {
    let id: String
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Intelligence.self) private var intelligence
    @Environment(\.brand) private var brand
    @Environment(\.zoomNamespace) private var namespace
    /// 没有标签的日记：模型建议的标签，点一下写进说明。
    @State private var suggested: [String] = []
    @Environment(\.dismiss) private var dismiss
    @State private var showViewer = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var headerHeight: CGFloat = 312
    @State private var articleHeight: CGFloat = 0
    @State private var pastPhoto = false
    @Namespace private var viewerNamespace

    var body: some View {
        Group {
            if let entry = store.entry(id) {
                content(entry)
            } else {
                EmptyHint(title: "这张照片已经不在了")
            }
        }
        .modifier(ZoomDestination(id: id, namespace: namespace))
        .navigationBarTitleDisplayMode(.inline)
        // 浮在照片上时按钮用浅色；滚过照片后回到系统默认。
        .toolbarColorScheme(store.entry(id) != nil && !pastPhoto ? .dark : nil, for: .navigationBar)
        .toolbar {
            if let entry = store.entry(id) {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(DiaryDates.dayTitle(entry.displayDate)).font(.headline)
                        Text(DiaryDates.year(entry.displayDate))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.meta)
                    }
                    .opacity(pastPhoto ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: pastPhoto)
                    .accessibilityElement(children: .combine)
                    .accessibilityHidden(!pastPhoto)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("编辑", systemImage: "square.and.pencil") {
                        router.editor = EditorRequest(assetID: id, mode: .edit)
                    }
                    Menu {
                        Button("删除照片…", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Label("更多", systemImage: "ellipsis")
                    }
                }
            }
        }
        .confirmationDialog("删除这张照片？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除照片和日记", role: .destructive) { delete() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("日记写在这张照片的说明里，删除照片后日记也会一起删除。照片会移到“最近删除”。")
        }
        .alert("没有完成", isPresented: .constant(errorMessage != nil)) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// 照片的高度跟着正文走：正文短时照片长高，把底部按钮以上的空间铺满（整张照片放在模糊底上），
    /// 不在正文下面留一大片空白；正文长时照片保持原来的比例，整页滚动。
    private func content(_ entry: DiaryEntry) -> some View {
        GeometryReader { viewport in
            let topInset = viewport.safeAreaInsets.top
            let width = viewport.size.width
            // iPad 上照片不按屏宽算高度，最多占到视口的六成。
            let natural = min(width / min(max(entry.aspectRatio, 0.8), 1.25), viewport.size.height * 0.62)
            let available = viewport.size.height + topInset
            let height = max(natural, available - articleHeight - Self.articleBottomPadding)
            ScrollView {
                VStack(spacing: 0) {
                    MediaHeader(entry: entry, height: height, topInset: topInset)
                        .overlay(alignment: .top) {
                            // 让浮在照片上的按钮和状态栏看得清。
                            PhotoScrim(edge: .top, strength: 0.28).frame(height: 120)
                        }
                        // 下拉时照片跟着拉伸。
                        .stretchyHeader()
                        .onTapGesture { if entry.mediaKind != .video { showViewer = true } }
                        // 点照片看大图：VoiceOver 读成按钮，双击就打开。
                        .modifier(ViewerAction(enabled: entry.mediaKind != .video) { showViewer = true })
                        .matchedTransitionSource(id: "viewer", in: viewerNamespace)
                    article(entry)
                        .padding(.bottom, Self.articleBottomPadding)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { articleHeight = $0 }
                }
            }
            .ignoresSafeArea(edges: .top)
            .scrollEdgeEffectHidden(!pastPhoto, for: .top)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y > height - 110
            } action: { _, past in
                pastPhoto = past
            }
            .onChange(of: height, initial: true) { headerHeight = height }
        }
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom) { bottomBar(entry) }
        .fullScreenCover(isPresented: $showViewer) {
            PhotoViewer(id: entry.id)
                .navigationTransition(.zoom(sourceID: "viewer", in: viewerNamespace))
        }
    }

    private static let articleBottomPadding: CGFloat = 28

    private func article(_ entry: DiaryEntry) -> some View {
        let segments = entry.displaySegments
        return VStack(alignment: .leading, spacing: 0) {
            Text(metaLine(entry))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.meta)
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index == 0 {
                    let split = CaptionFormat.splitTitle(segment.text)
                    DiaryText(text: split.title, size: 24, bold: true)
                        .lineSpacing(9)
                        .padding(.top, 10)
                        .accessibilityAddTraits(.isHeader)
                    if !split.rest.isEmpty {
                        DiaryText(text: split.rest, size: 18, color: Color.inkSecondary)
                            .lineSpacing(11)
                            .padding(.top, 12)
                    }
                    // 写的日子和拍的日子不同时，才注明写于哪天。
                    if let written = segment.date, written != entry.day {
                        Text("写于 \(DiaryDates.full(written))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.meta)
                            .padding(.top, 8)
                    }
                } else {
                    Group {
                        if let day = segment.date {
                            let gap = DiaryDates.gap(from: segments[index - 1].date, to: day)
                            SegmentDivider(primary: gap.relative, secondary: gap.date)
                        } else {
                            SegmentDivider(primary: String(localized: "未注明日期", bundle: .app, locale: .app))
                        }
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 24)
                    DiaryText(text: segment.text, size: 18, color: Color.inkSecondary)
                        .lineSpacing(11)
                }
            }
            chips(entry)
            suggestedTags(entry)
        }
        .textSelection(.enabled)
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Metrics.reading)
        .padding(.top, Metrics.reading)
    }

    /// 2023年10月31日 周二 · 3 年前
    private func metaLine(_ entry: DiaryEntry) -> String {
        let date = DiaryDates.fullWithWeekday(entry.displayDate)
        guard entry.day.year < DayStamp.today.year else { return date }
        return "\(date) · \(DiaryDates.yearsAgo(entry.day))"
    }

    /// 地点（灰底）和标签（主题色浅底）胶囊。
    @ViewBuilder
    private func chips(_ entry: DiaryEntry) -> some View {
        if entry.placeName != nil || !entry.tags.isEmpty {
            FlowLayout(spacing: 8) {
                if let place = entry.placeName {
                    // 点地点看同一地点的其他日记（只有一篇时不跳转）。
                    Button { router.push(.place(place)) } label: {
                        Chip(height: 34) {
                            Image(systemName: "mappin.and.ellipse").font(.footnote.weight(.semibold))
                            Text(place)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ink)
                    }
                    .buttonStyle(.press)
                    .disabled(store.entries(at: place).count < 2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Spoken.place(place))
                    .accessibilityAddTraits(store.entries(at: place).count < 2 ? [] : .isButton)
                }
                ForEach(entry.tags, id: \.self) { tag in
                    Button { router.push(.tag(tag)) } label: {
                        Chip(height: 34, fill: brand.soft()) {
                            Text("#\(tag)#")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(brand)
                    }
                    .buttonStyle(.press)
                    .accessibilityLabel(Spoken.tag(tag))
                }
            }
            .padding(.top, 32)
        }
    }

    /// 还没有标签时，模型按正文建议几个：浅底胶囊（待确认态），前面一枚 Apple Intelligence 标记。点一下写进说明。
    @ViewBuilder
    private func suggestedTags(_ entry: DiaryEntry) -> some View {
        let wanted = intelligence.isEnabled && entry.tags.isEmpty
        FlowLayout(spacing: 8) {
            if wanted, !suggested.isEmpty {
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(height: 34)
                    .accessibilityHidden(true)
                ForEach(suggested, id: \.self) { tag in
                    Button { accept(tag) } label: {
                        Chip(height: 34, fill: brand.soft()) {
                            Text("#\(tag)#")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(brand)
                    }
                    .buttonStyle(.press)
                    .accessibilityLabel(Spoken.tag(tag))
                    .accessibilityHint(Text("加上这个标签"))
                }
            }
        }
        .padding(.top, wanted && !suggested.isEmpty ? (entry.placeName == nil ? 32 : 8) : 0)
        .animation(.drawer, value: suggested)
        .task(id: wanted ? entry.caption : "") {
            guard wanted else { suggested = []; return }
            let tags = await intelligence.engine.suggestTags(for: entry.caption, existing: store.allTags)
            guard !Task.isCancelled else { return }
            suggested = tags
        }
    }

    private func accept(_ tag: String) {
        suggested.removeAll { $0 == tag }
        Task {
            do {
                try await store.addTag(tag, to: id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 左边分享，右边主题色“追加感想”。
    private func bottomBar(_ entry: DiaryEntry) -> some View {
        HStack {
            // 分享一张图：照片和日记排在一起。
            let shared = SharedDiary(entry: entry, brand: brand)
            ShareLink(item: shared, preview: SharePreview(entry.title, image: shared)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .frame(width: 52, height: 52)
                    .contentShape(.circle)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("分享")
            .largeContent(String(localized: "分享", bundle: .app, locale: .app), systemImage: "square.and.arrow.up")

            Spacer()

            Button {
                router.editor = EditorRequest(assetID: entry.id, mode: .append, zoomSource: EditorRequest.appendButton(entry.id))
            } label: {
                Label("追加感想", systemImage: "plus")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.leading, 16)
                    .padding(.trailing, 24)
                    .frame(minHeight: 52)
                    .contentShape(.capsule)
            }
            .buttonStyle(.press)
            .glassEffect(.regular.tint(brand).interactive(), in: .capsule)
            .zoomSource(EditorRequest.appendButton(entry.id), in: namespace, cornerRadius: 26)
            .largeContent(String(localized: "追加感想", bundle: .app, locale: .app), systemImage: "plus")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        // 浮在正文上，最多长到辅助功能第一档；再大的长按看大字。
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background(alignment: .bottom) {
            BottomFade(height: 130).ignoresSafeArea(edges: .bottom)
        }
    }

    private func delete() {
        Task {
            do {
                try await store.delete(id: id)
                dismiss()
            } catch {
                // 用户在系统确认里取消也会走到这里，不提示。
                let code = (error as NSError).code
                if code != PHPhotosError.userCancelled.rawValue {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

/// 照片可以点开看大图：给辅助功能加上按钮的身份和默认操作。
private struct ViewerAction: ViewModifier {
    let enabled: Bool
    let open: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text("全屏查看"))
                .accessibilityAction(.default, open)
        } else {
            content
        }
    }
}

private struct ZoomDestination: ViewModifier {
    let id: String
    let namespace: Namespace.ID?
    func body(content: Content) -> some View {
        if let namespace {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

// MARK: 照片 / 实况照片 / 视频

private struct MediaHeader: View {
    let entry: DiaryEntry
    let height: CGFloat
    /// 状态栏 + 导航按钮的高度；照片完整显示时从这下面开始放。
    let topInset: CGFloat
    @State private var player: AVPlayer?

    var body: some View {
        GeometryReader { geo in
            let containerAspect = geo.size.width / max(geo.size.height, 1)
            // 照片比区域宽很多（区域被拉高了）时完整显示，背后铺一层模糊的同一张照片；否则铺满裁切。
            let fits = entry.mediaKind != .video && entry.aspectRatio > containerAspect * 1.15
            ZStack {
                if fits {
                    AssetImage(id: entry.id, pointSize: CGSize(width: 80, height: 80))
                        .blur(radius: 40, opaque: true)
                        .overlay(Color.black.opacity(0.12))
                }
                media(size: fits ? fittedSize(in: geo.size) : geo.size, mode: fits ? .fit : .fill)
                    .padding(.top, fits ? topInset / 2 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: height)
        .clipped()
        .task(id: entry.id) {
            guard entry.mediaKind == .video, player == nil,
                  let item = await AssetImages.shared.playerItem(for: entry.id) else { return }
            player = AVPlayer(playerItem: item)
        }
        // 照片本身对辅助功能是隐藏的，要在这里自己成为一个元素，否则 VoiceOver 摸不到它、也就点不开大图。
        // 视频保留播放器自己的控件。
        .accessibilityElement(children: entry.mediaKind == .video ? .contain : .ignore)
        .accessibilityLabel(entry.mediaKind == .video ? Text("视频") : Text("照片"))
        .accessibilityAddTraits(.isImage)
    }

    private func fittedSize(in size: CGSize) -> CGSize {
        let w = size.width
        return CGSize(width: w, height: min(w / max(entry.aspectRatio, 0.01), size.height - topInset / 2))
    }

    @ViewBuilder
    private func media(size: CGSize, mode: ContentMode) -> some View {
        Group {
            switch entry.mediaKind {
            case .video:
                if let player {
                    VideoPlayer(player: player)
                } else {
                    AssetImage(id: entry.id, allowNetwork: true)
                        .overlay { ProgressView().tint(.white) }
                }
            case .livePhoto:
                LivePhotoView(id: entry.id, size: size)
                    .overlay(alignment: .topLeading) {
                        Label("实况", systemImage: "livephoto")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .glassEffect(.regular, in: .capsule)
                            .padding(12)
                    }
            case .photo:
                AssetImage(id: entry.id, contentMode: mode, allowNetwork: true)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

private struct LivePhotoView: UIViewRepresentable {
    let id: String
    let size: CGSize
    @Environment(\.displayScale) private var scale

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        guard view.livePhoto == nil, size.width > 0 else { return }
        let px = CGSize(width: size.width * scale, height: size.height * scale)
        Task {
            view.livePhoto = await AssetImages.shared.livePhoto(for: id, pixelSize: px)
        }
    }
}
