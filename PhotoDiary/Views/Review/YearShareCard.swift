import SwiftUI
import Photos
import UniformTypeIdentifiers

/// 一年回顾最后一张：分享出去的图。和单篇的分享图（ShareCard）是同一张相纸：
/// 上面是这一年的几张照片（9、4 或 1 张），下面是年份、篇数和常用的标签，右下角一个小拍立得。
/// 固定浅色，不跟深色模式。
struct YearShareCard<Photo: View>: View {
    let review: YearInReview
    @ViewBuilder let photo: (String) -> Photo

    static var width: CGFloat { 390 }
    private static var margin: CGFloat { 18 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mosaic
                .clipShape(.rect(cornerRadius: 4, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: String(review.year))
                    .font(.diary(34, bold: true, relativeTo: .largeTitle))
                    .foregroundStyle(Color.ink)
                Text("\(review.count) 篇")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.meta)
                if !review.tags.isEmpty {
                    YearTagLine(tags: review.tags.prefix(3).map(\.name))
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 20)
            BrandMark(width: 16, palette: .light, shadow: false)
                .opacity(0.8)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 8)
        }
        .padding(Self.margin)
        .background(Color(red: 0.99, green: 0.985, blue: 0.975))
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.large)
    }

    /// 正方形的照片墙，格子之间 2pt。
    private var mosaic: some View {
        let ids = review.mosaic
        let side = ids.count >= 9 ? 3 : ids.count >= 4 ? 2 : 1
        return Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(0..<side, id: \.self) { row in
                GridRow {
                    ForEach(0..<side, id: \.self) { column in
                        let index = row * side + column
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay { if index < ids.count { photo(ids[index]) } }
                            .clipped()
                    }
                }
            }
        }
    }
}

private struct YearTagLine: View {
    let tags: [String]
    @Environment(\.brand) private var brand

    var body: some View {
        Text(tags.map { "#\($0)#" }.joined(separator: "  "))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(brand)
    }
}

/// 分享面板里的一年回顾图：分享时才取照片、排版、渲染。
nonisolated struct SharedYear: Transferable, Sendable {
    let review: YearInReview
    let brand: Color

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { item in
            try await item.jpegData()
        }
        .suggestedFileName { String($0.review.year) }
    }

    @MainActor private func jpegData() async throws -> Data {
        // 卡片宽 390pt、按 3 倍渲染；九宫格每格不到 400px，单张取 1200px。
        let side: CGFloat = review.mosaic.count >= 9 ? 400 : review.mosaic.count >= 4 ? 600 : 1200
        var photos: [String: UIImage] = [:]
        for id in review.mosaic {
            for await image in AssetImages.shared.images(for: id, pixelSize: CGSize(width: side, height: side),
                                                          contentMode: .aspectFill, allowNetwork: true) {
                photos[id] = image
            }
        }
        let card = YearShareCard(review: review) { id in
            if let image = photos[id] {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        let renderer = ImageRenderer(content: card.frame(width: YearShareCard<EmptyView>.width).environment(\.brand, brand))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: YearShareCard<EmptyView>.width, height: nil)
        guard let data = renderer.uiImage?.jpegData(compressionQuality: 0.9) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
