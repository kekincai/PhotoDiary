import SwiftUI
import PhotosUI
import AVKit

/// 日记详情：照片、首句标题、正文；追加的段落用分隔线隔开；底部浮条为地点、标签和“追加”。
/// 不显示拍摄参数、相机、文件大小等照片元信息。
struct EntryDetailView: View {
    let id: String
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.brand) private var brand
    @Environment(\.zoomNamespace) private var namespace
    @Environment(\.dismiss) private var dismiss
    @State private var showViewer = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @Namespace private var viewerNamespace

    var body: some View {
        Group {
            if let entry = store.entry(id) {
                content(entry)
            } else {
                EmptyHint(title: "这张照片已经不在了", message: "它可能在照片 App 里被删除，或者说明被清空了。")
            }
        }
        .modifier(ZoomDestination(id: id, namespace: namespace))
        .toolbarBackground(brand, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let entry = store.entry(id) {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(DiaryDates.dayTitle(entry.displayDate)).font(.headline)
                        Text("\(String(entry.day.year))年")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .foregroundStyle(.white)
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("编辑") { router.editor = EditorRequest(assetID: id, mode: .edit) }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("在“照片”中打开", systemImage: "photo.on.rectangle") {
                            if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
                        }
                        Button("删除照片…", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Label("更多", systemImage: "ellipsis")
                    }
                }
            }
        }
        .confirmationDialog("删除这张照片？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除照片和日记", role: .destructive) { delete() }
        } message: {
            Text("日记写在这张照片的说明里，删除照片后日记也会一起删除。照片会移到“最近删除”。")
        }
        .alert("没有完成", isPresented: .constant(errorMessage != nil)) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func content(_ entry: DiaryEntry) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                MediaHeader(entry: entry)
                    .onTapGesture { if entry.mediaKind != .video { showViewer = true } }
                    .matchedTransitionSource(id: "viewer", in: viewerNamespace)
                article(entry)
            }
            .padding(.bottom, 120)
        }
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom) { bottomBar(entry) }
        .fullScreenCover(isPresented: $showViewer) {
            PhotoViewer(id: entry.id)
                .navigationTransition(.zoom(sourceID: "viewer", in: viewerNamespace))
        }
    }

    private func article(_ entry: DiaryEntry) -> some View {
        let segments = entry.displaySegments
        return VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index == 0 {
                    let split = CaptionFormat.splitTitle(segment.text)
                    VStack(alignment: .leading, spacing: 10) {
                        DiaryText(text: split.title, size: 23, bold: true)
                            .lineSpacing(6)
                            .accessibilityAddTraits(.isHeader)
                        if !split.rest.isEmpty {
                            DiaryText(text: split.rest, size: 18, color: Color.inkSecondary)
                                .lineSpacing(11)
                        }
                        // 写的日子和拍的日子不同时，才注明写于哪天。
                        if let written = segment.date, written != entry.day {
                            Text("写于 \(DiaryDates.full(written))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color.meta)
                                .padding(.top, 2)
                        }
                    }
                } else {
                    if let day = segment.date {
                        let gap = DiaryDates.gap(from: segments[index - 1].date, to: day)
                        SegmentDivider(primary: gap.relative, secondary: gap.date)
                    } else {
                        SegmentDivider(primary: "未注明日期")
                    }
                    DiaryText(text: segment.text, size: 18, color: Color.inkSecondary)
                        .lineSpacing(11)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 26)
    }

    @ViewBuilder
    private func bottomBar(_ entry: DiaryEntry) -> some View {
        let hasMeta = entry.placeName != nil || !entry.tags.isEmpty
        HStack(spacing: 10) {
            if hasMeta {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    if let place = entry.placeName {
                        Label(place, systemImage: "mappin")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(Color.ink.opacity(0.85))
                    }
                    ForEach(entry.tags, id: \.self) { tag in
                        Button("#\(tag)#") { router.push(.tag(tag)) }
                            .foregroundStyle(brand)
                    }
                }
                .font(.footnote.weight(.semibold))
                .padding(.leading, 16)
            }
            .scrollIndicators(.hidden)
            } else {
                Spacer()
            }

            Button {
                router.editor = EditorRequest(assetID: entry.id, mode: .append)
            } label: {
                Label("追加", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 6)
                    .frame(height: 30)
            }
            .buttonStyle(.glassProminent)
            .tint(brand)
            .padding(.trailing, 8)
        }
        .frame(height: 60)
        // 没有地点和标签时只留“追加”按钮，不铺一条空的玻璃底。
        .glassEffect(hasMeta ? .regular : .identity, in: .capsule)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
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
    @State private var player: AVPlayer?

    var body: some View {
        GeometryReader { geo in
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
                    LivePhotoView(id: entry.id, size: geo.size)
                        .overlay(alignment: .topLeading) {
                            Label("实况", systemImage: "livephoto")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .glassEffect(.regular, in: .capsule)
                                .padding(12)
                        }
                case .photo:
                    AssetImage(id: entry.id, contentMode: .fill, allowNetwork: true)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // 宽度铺满；竖图最高到 1.25 倍宽，超出部分裁切。
        .aspectRatio(max(entry.aspectRatio, 0.8), contentMode: .fit)
        .clipped()
        .task(id: entry.id) {
            guard entry.mediaKind == .video, player == nil,
                  let item = await AssetImages.shared.playerItem(for: entry.id) else { return }
            player = AVPlayer(playerItem: item)
        }
        .accessibilityLabel(entry.mediaKind == .video ? "视频" : "照片")
        .accessibilityAddTraits(.isImage)
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
