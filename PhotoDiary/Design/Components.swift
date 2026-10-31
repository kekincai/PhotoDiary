import SwiftUI
import Photos

/// 照片库里的一张图。只请求需要的像素尺寸；加载完成时淡入。
struct AssetImage: View {
    let id: String
    var contentMode: ContentMode = .fill
    var allowNetwork = false
    /// 不传则按视图实际大小请求。
    var pointSize: CGSize? = nil

    @State private var image: UIImage?
    @State private var size: CGSize = .zero
    @Environment(\.displayScale) private var scale

    var body: some View {
        Color(.secondarySystemFill)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .transition(.opacity.animation(.easeOut(duration: 0.2)))
                }
            }
            .clipped()
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { size = $0 }
            .task(id: TaskKey(id: id, size: pointSize ?? size)) {
                let pts = pointSize ?? size
                guard pts.width > 0, pts.height > 0 else { return }
                let px = CGSize(width: pts.width * scale, height: pts.height * scale)
                let mode: PHImageContentMode = contentMode == .fill ? .aspectFill : .aspectFit
                for await img in AssetImages.shared.images(for: id, pixelSize: px, contentMode: mode, allowNetwork: allowNetwork) {
                    image = img
                }
            }
            .accessibilityHidden(true)
    }

    private struct TaskKey: Equatable {
        var id: String
        var size: CGSize
    }
}

/// 段落之间的分隔线：两侧细线，中间是相对时间（略重）和日期。
struct SegmentDivider: View {
    let primary: String
    var secondary: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            line
            HStack(spacing: 6) {
                Text(primary).fontWeight(.semibold).foregroundStyle(Color.inkSecondary)
                if let secondary { Text(secondary).foregroundStyle(Color.meta) }
            }
            .font(.caption.monospacedDigit())
            .fixedSize()
            line
        }
        .accessibilityElement(children: .combine)
    }

    private var line: some View {
        Rectangle().fill(Color.hairline).frame(height: 1)
    }
}

/// 正文里的标签高亮显示（主题色、半粗）。
struct DiaryText: View {
    let text: String
    var size: CGFloat
    var bold = false
    var color: Color = .ink
    @Environment(\.brand) private var brand

    var body: some View {
        Text(attributed)
            .font(.diary(size, bold: bold))
            .foregroundStyle(color)
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        for match in CaptionFormat.tagMatches(in: text) {
            guard let lower = AttributedString.Index(match.range.lowerBound, within: result),
                  let upper = AttributedString.Index(match.range.upperBound, within: result) else { continue }
            result[lower..<upper].foregroundColor = brand
        }
        return result
    }
}

/// “2 段”角标：照片上的深色毛玻璃小胶囊。
struct ParagraphBadge: View {
    let count: Int
    var compact = false

    var body: some View {
        Text("\(count) 段")
            .font(.system(size: compact ? 11 : 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.vertical, compact ? 1 : 3)
            .background {
                Capsule().fill(.black.opacity(0.3)).background(.ultraThinMaterial, in: .capsule)
            }
            .environment(\.colorScheme, .dark)
    }
}

/// 视频、实况照片角标
struct MediaBadge: View {
    let kind: MediaKind
    var body: some View {
        switch kind {
        case .photo: EmptyView()
        case .video:
            Image(systemName: "video.fill").font(.caption2).foregroundStyle(.white).shadow(radius: 2)
        case .livePhoto:
            Image(systemName: "livephoto").font(.caption).foregroundStyle(.white).shadow(radius: 2)
        }
    }
}

/// 照片日记里的一行：左侧星期与日期，中间首句标题、预览、地点与标签，右侧缩略图。
struct EntryRow: View {
    let entry: DiaryEntry
    var showsSeparator = true
    var namespace: Namespace.ID?
    @Environment(\.brand) private var brand

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 1) {
                Text(DiaryDates.weekday(entry.displayDate))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.meta)
                Text("\(entry.day.day)")
                    .font(.system(.title2, design: .default, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Color.ink)
            }
            .frame(width: 36)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(.diary(16, bold: true, relativeTo: .headline))
                        .lineSpacing(3)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                }
                if !entry.preview.isEmpty {
                    Text(entry.preview)
                        .font(.diary(14, relativeTo: .subheadline))
                        .lineSpacing(5)
                        .lineLimit(2)
                        .foregroundStyle(Color.inkSecondary)
                        .multilineTextAlignment(.leading)
                }
                metaLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 14)
            .overlay(alignment: .bottom) {
                if showsSeparator { Rectangle().fill(Color.hairline).frame(height: 1) }
            }

            thumbnail
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(DiaryDates.dayTitle(entry.displayDate))的日记：\(entry.title)")
    }

    @ViewBuilder private var metaLine: some View {
        if let line = metaText {
            Text(line)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.meta)
                .lineLimit(1)
        }
    }

    private var metaText: AttributedString? {
        let place = entry.placeName
        let tags = entry.tagLine
        guard place != nil || !tags.isEmpty else { return nil }
        // 地点和标签之间用空隙分开，不用“·”拼接。
        var line = AttributedString(place.map { tags.isEmpty ? $0 : $0 + "\u{2003}" } ?? "")
        var tagPart = AttributedString(tags)
        tagPart.foregroundColor = brand
        line += tagPart
        return line
    }

    private var thumbnail: some View {
        AssetImage(id: entry.id, pointSize: CGSize(width: 78, height: 78))
            .frame(width: 78, height: 78)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) {
                if entry.segments.count > 1 {
                    ParagraphBadge(count: entry.segments.count).padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                MediaBadge(kind: entry.mediaKind).padding(6)
            }
            .modifier(TransitionSource(id: entry.id, namespace: namespace))
    }
}

struct TransitionSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?
    var cornerRadius: CGFloat = 12
    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace) { $0.clipShape(.rect(cornerRadius: cornerRadius, style: .continuous)) }
        } else {
            content
        }
    }
}

/// 空状态：说清楚是什么空了，最多给一个动作。不放大图标。
struct EmptyHint: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var action: (label: LocalizedStringKey, perform: () -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.meta)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.label, action: action.perform)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 40)
    }
}

/// 首页的大照片卡片：4:3 照片，下面是日期地点、标题、预览和标签。
struct EntryCard: View {
    let entry: DiaryEntry
    var namespace: Namespace.ID?
    @Environment(\.brand) private var brand

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay { AssetImage(id: entry.id) }
                .clipShape(.rect(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if entry.segments.count > 1 {
                        ParagraphBadge(count: entry.segments.count).padding(10)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    MediaBadge(kind: entry.mediaKind).padding(12)
                }
                .modifier(TransitionSource(id: entry.id, namespace: namespace, cornerRadius: 22))

            VStack(alignment: .leading, spacing: 5) {
                Text(metaLine)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.meta)
                    .lineLimit(1)
                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(.diary(20, bold: true, relativeTo: .title3))
                        .lineSpacing(4)
                        .foregroundStyle(Color.ink)
                }
                if !entry.preview.isEmpty {
                    Text(entry.preview)
                        .font(.diary(15.5, relativeTo: .subheadline))
                        .lineSpacing(7)
                        .lineLimit(3)
                        .foregroundStyle(Color.inkSecondary)
                }
                if !entry.tags.isEmpty {
                    Text(entry.tags.map { "#\($0)#" }.joined(separator: "  "))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(brand)
                        .padding(.top, 2)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 4)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// 周五 · 10月30日 · 杉并区
    private var metaLine: String {
        [DiaryDates.weekday(entry.displayDate), DiaryDates.short(entry.day), entry.placeName]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// 浮在内容上的玻璃分段控件（日记的四种视图、从照片添加的范围）。
struct GlassSegmented<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.system(size: 14, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.ink : Color.inkSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 58, minHeight: 32)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Color.primary.opacity(0.075))
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.press)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .animation(.snappy, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// 分组标题（22pt 粗体）；可点的组带灰色箭头。
struct SectionTitle: View {
    let title: String
    var chevron = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.ink)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 胶囊：灰底（地点、时间）或主题色浅底（标签）。
struct Chip<Content: View>: View {
    var height: CGFloat = 36
    var fill: Color = .tile
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) { content }
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(fill, in: .capsule)
    }
}

/// 底部浮动控件后面的渐隐，让下面的内容退后。
struct BottomFade: View {
    var height: CGFloat = 190

    var body: some View {
        let bg = Color(.systemBackground)
        LinearGradient(stops: [
            .init(color: bg.opacity(0), location: 0),
            .init(color: bg.opacity(0.75), location: 0.55),
            .init(color: bg.opacity(0.92), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 占位内容上从左到右扫过的高光；“减少动态效果”时不动。
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, Color(.systemBackground).opacity(0.65), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.5)
                            .offset(x: phase * geo.size.width * 1.5)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}
