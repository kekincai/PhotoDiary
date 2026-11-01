import SwiftUI
import Photos
import UniformTypeIdentifiers

/// 分享出去的是一张图：照片和日记排在同一张相纸上，像 App 图标里的拍立得。
/// 固定浅色，不跟深色模式；多段日记按详情页的样子排，段落之间是同样的分隔线。
struct ShareCard: View {
    let entry: DiaryEntry
    let photo: UIImage

    static let width: CGFloat = 390
    private static let margin: CGFloat = 18

    var body: some View {
        let inner = Self.width - Self.margin * 2
        let ratio = min(max(photo.size.width / max(photo.size.height, 1), 0.75), 1.6)
        VStack(alignment: .leading, spacing: 0) {
            Image(uiImage: photo)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: inner, height: inner / ratio)
                .clipShape(.rect(cornerRadius: 4, style: .continuous))
            article
                .padding(.horizontal, 6)
                .padding(.top, 22)
            signature
                .padding(.top, 16)
        }
        .padding(Self.margin)
        .frame(width: Self.width)
        .background(Color(red: 0.99, green: 0.985, blue: 0.975))
        .environment(\.colorScheme, .light)
    }

    private var article: some View {
        let segments = entry.displaySegments
        return VStack(alignment: .leading, spacing: 0) {
            Text(metaLine)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.meta)
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index == 0 {
                    let split = CaptionFormat.splitTitle(segment.text)
                    DiaryText(text: split.title, size: 21, bold: true)
                        .lineSpacing(7)
                        .padding(.top, 8)
                    if !split.rest.isEmpty {
                        DiaryText(text: split.rest, size: 16, color: Color.inkSecondary)
                            .lineSpacing(9)
                            .padding(.top, 10)
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
                    .padding(.vertical, 20)
                    DiaryText(text: segment.text, size: 16, color: Color.inkSecondary)
                        .lineSpacing(9)
                }
            }
            if !entry.tags.isEmpty {
                TagLine(tags: entry.tags)
                    .padding(.top, 16)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 右下角一个小拍立得，代替 App 名。
    private var signature: some View {
        BrandMark(width: 16, palette: .light, shadow: false)
            .opacity(0.8)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// 2023年10月31日 周二 · 杉并区
    private var metaLine: String {
        [DiaryDates.fullWithWeekday(entry.displayDate), entry.placeName].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct TagLine: View {
    let tags: [String]
    @Environment(\.brand) private var brand

    var body: some View {
        Text(tags.map { "#\($0)#" }.joined(separator: "  "))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(brand)
    }
}

/// 分享面板里的“照片 + 日记”图片：分享时才取照片、排版、渲染。
nonisolated struct SharedDiary: Transferable, Sendable {
    let entry: DiaryEntry
    let brand: Color

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { item in
            try await item.jpegData()
        }
        .suggestedFileName { $0.entry.title.isEmpty ? String(localized: "照片日记", bundle: .app, locale: .app) : $0.entry.title }
    }

    @MainActor private func jpegData() async throws -> Data {
        var photo: UIImage?
        // 卡片宽 390pt，按 3 倍渲染，照片取 1600px 足够。
        let size = CGSize(width: 1600, height: 1600)
        for await image in AssetImages.shared.images(for: entry.id, pixelSize: size, contentMode: .aspectFit, allowNetwork: true) {
            photo = image
        }
        guard let photo else { throw CocoaError(.fileReadUnknown) }
        let renderer = ImageRenderer(content: ShareCard(entry: entry, photo: photo).environment(\.brand, brand))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: ShareCard.width, height: nil)
        guard let data = renderer.uiImage?.jpegData(compressionQuality: 0.9) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
