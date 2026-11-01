import SwiftUI
import UIKit

/// 长按一篇日记：预览照片和标题，可以直接追加感想、分享、在照片 App 里打开。
/// 列表卡片、日历格子、照片网格都挂这一个。
struct EntryContextMenu: ViewModifier {
    let entry: DiaryEntry
    @Environment(Router.self) private var router

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("追加感想", systemImage: "plus.bubble") {
                router.editor = EditorRequest(assetID: entry.id, mode: .append)
            }
            Button("编辑", systemImage: "square.and.pencil") {
                router.editor = EditorRequest(assetID: entry.id, mode: .edit)
            }
            Divider()
            ShareLink(item: SharedPhoto(id: entry.id), message: Text(entry.caption), preview: SharePreview(entry.title)) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
            Button("在“照片”中打开", systemImage: "photo.on.rectangle") {
                if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
            }
        } preview: {
            EntryPreview(entry: entry)
        }
    }
}

/// 上下文菜单的预览：照片按原比例，下面一行日期和标题。
private struct EntryPreview: View {
    let entry: DiaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.m) {
            Color.clear
                .aspectRatio(min(max(entry.aspectRatio, 0.75), 1.6), contentMode: .fit)
                .overlay { AssetImage(id: entry.id, allowNetwork: true) }
                .clipped()
            VStack(alignment: .leading, spacing: Metrics.Spacing.xs) {
                Text(metaLine)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.meta)
                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(.diary(18, bold: true, relativeTo: .headline))
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                }
                if !entry.preview.isEmpty {
                    Text(entry.preview)
                        .font(.diary(15, relativeTo: .subheadline))
                        .lineSpacing(5)
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(3)
                }
            }
            .padding(.horizontal, Metrics.Spacing.l)
            .padding(.bottom, Metrics.Spacing.l)
        }
        .frame(width: 320)
        .background(Color(.systemBackground))
    }

    private var metaLine: String {
        [DiaryDates.fullWithWeekday(entry.displayDate), entry.placeName].compactMap { $0 }.joined(separator: " · ")
    }
}

extension View {
    func entryContextMenu(_ entry: DiaryEntry) -> some View {
        modifier(EntryContextMenu(entry: entry))
    }
}
