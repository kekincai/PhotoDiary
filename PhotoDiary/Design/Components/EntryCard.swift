import SwiftUI

/// 首页的大照片卡片：4:3 照片，下面是日期地点、标题、预览和标签。
struct EntryCard: View {
    let entry: DiaryEntry
    var namespace: Namespace.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.m) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                // 首页的主画面：原图在 iCloud 时也下载清晰的，不停在模糊的本地预览上。
                .overlay { AssetImage(id: entry.id, allowNetwork: true) }
                .clipShape(.rect(cornerRadius: Metrics.Radius.hero, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if entry.segments.count > 1 {
                        ParagraphBadge(count: entry.segments.count).padding(Metrics.Spacing.m)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    MediaBadge(kind: entry.mediaKind).padding(Metrics.Spacing.m)
                }
                .modifier(TransitionSource(id: entry.id, namespace: namespace, cornerRadius: Metrics.Radius.hero))

            VStack(alignment: .leading, spacing: Metrics.Spacing.xs) {
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
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.meta)
                        .padding(.top, 2)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, Metrics.Spacing.xs)
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

/// 照片日记里的一行：左侧星期与日期，中间首句标题、预览、地点与标签，右侧缩略图。
struct EntryRow: View {
    let entry: DiaryEntry
    var showsSeparator = true
    var namespace: Namespace.ID?

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.Spacing.m) {
            VStack(spacing: 1) {
                Text(DiaryDates.weekday(entry.displayDate))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.meta)
                Text("\(entry.day.day)")
                    .font(.system(.title2, design: .default, weight: .semibold))
                    .foregroundStyle(Color.ink)
            }
            .frame(width: 36)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: Metrics.Spacing.xs) {
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
                if let line = metaText {
                    Text(line)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.meta)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Metrics.Spacing.l)
            .overlay(alignment: .bottom) {
                if showsSeparator { Rectangle().fill(Color.hairline).frame(height: 1) }
            }

            thumbnail
        }
        .padding(.horizontal, Metrics.text)
        .padding(.vertical, Metrics.Spacing.l)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(DiaryDates.dayTitle(entry.displayDate))的日记：\(entry.title)")
    }

    /// 标签在列表里和地点一样用灰色，主题色留给正文和编辑器。
    private var metaText: String? {
        let place = entry.placeName
        let tags = entry.tagLine
        guard place != nil || !tags.isEmpty else { return nil }
        // 地点和标签之间用空隙分开，不用“·”拼接。
        return place.map { tags.isEmpty ? $0 : $0 + "\u{2003}" + tags } ?? tags
    }

    private var thumbnail: some View {
        let side = Metrics.rowThumb
        return AssetImage(id: entry.id, pointSize: CGSize(width: side, height: side))
            .frame(width: side, height: side)
            .clipShape(.rect(cornerRadius: Metrics.Radius.tile, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if entry.segments.count > 1 {
                    ParagraphBadge(count: entry.segments.count).padding(Metrics.Spacing.xs)
                }
            }
            .overlay(alignment: .topTrailing) {
                MediaBadge(kind: entry.mediaKind).padding(6)
            }
            .modifier(TransitionSource(id: entry.id, namespace: namespace))
    }
}
