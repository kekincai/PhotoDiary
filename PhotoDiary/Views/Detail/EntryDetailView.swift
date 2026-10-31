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
                EmptyHint(symbol: "photo", title: "这张照片已不在照片库中", message: "可能已在照片 App 中删除，或说明被清空。")
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
                    }
                } else {
                    if let day = segment.date {
                        SegmentDivider(label: DiaryDates.gap(from: segments[index - 1].date, to: day))
                    } else {
                        SegmentDivider(label: "未注明日期")
                    }
                    DiaryText(text: segment.text, size: 18, color: Color.inkSecondary)
                        .lineSpacing(11)
                }
            }
            if !entry.isDiary {
                Label("这段说明来自其他地方（如导入时自带），编辑后会成为日记。", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.meta)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 26)
    }

    private func bottomBar(_ entry: DiaryEntry) -> some View {
        HStack(spacing: 10) {
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
                    if entry.placeName == nil && entry.tags.isEmpty {
                        Text(entry.isDiary ? "没有地点和标签" : "其他来源的说明")
                            .foregroundStyle(Color.meta)
                    }
                }
                .font(.footnote.weight(.semibold))
                .padding(.leading, 16)
            }
            .scrollIndicators(.hidden)

            Button {
                router.editor = EditorRequest(assetID: entry.id, mode: entry.isDiary ? .append : .edit)
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
        .glassEffect(.regular, in: .capsule)
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
