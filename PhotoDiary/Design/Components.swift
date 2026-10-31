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

/// “2 段”角标
struct ParagraphBadge: View {
    let count: Int
    var body: some View {
        Text("\(count) 段")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.black.opacity(0.55), in: .capsule)
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
    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace) { $0.clipShape(.rect(cornerRadius: 12)) }
        } else {
            content
        }
    }
}

/// 空状态：说清楚是什么空了，最多给一个动作。不放大图标。
struct EmptyHint: View {
    let title: String
    let message: String
    var action: (label: String, perform: () -> Void)? = nil

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

/// 圆角卡片里的一行（回顾页、设置）
struct CardRow<Leading: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 14) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Color.ink)
                Text(subtitle).font(.footnote).foregroundStyle(Color.meta).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(.rect)
    }
}
