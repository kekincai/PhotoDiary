import SwiftUI

/// “2 段”角标：照片上的深色毛玻璃小胶囊。
struct ParagraphBadge: View {
    let count: Int
    var compact = false

    var body: some View {
        Text("\(count) 段")
            .font(.system(size: compact ? 11 : 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 4)
            .background {
                Capsule().fill(.black.opacity(0.3)).background(.ultraThinMaterial, in: .capsule)
            }
            .environment(\.colorScheme, .dark)
    }
}

/// 视频、实况照片角标，和照片 App 的一样：白色符号加一点投影。
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
