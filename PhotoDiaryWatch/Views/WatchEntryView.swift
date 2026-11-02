import SwiftUI

/// 一篇日记：照片、日期、正文（衬线体），底部“追加感想”。
struct WatchEntryView: View {
    let id: String
    @Environment(WatchStore.self) private var store

    var body: some View {
        if let entry = store.entry(id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    photo(entry)
                    Text(metaLine(entry))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    article(entry)
                    chips(entry)
                    NavigationLink(value: ComposeRequest(assetID: entry.id)) {
                        Label("追加感想", systemImage: "mic.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle(DiaryDates.short(entry.day))
            .navigationDestination(for: ComposeRequest.self) { request in
                WatchComposeView(assetID: request.assetID, mode: .append, day: entry.day)
            }
        } else {
            ContentUnavailableView("这篇不在手表上", systemImage: "iphone", description: Text("在 iPhone 上打开照片日记重新同步"))
        }
    }

    @ViewBuilder private func photo(_ entry: DiaryEntry) -> some View {
        if let image = store.image(entry.id) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if entry.mediaKind == .video {
                        Image(systemName: "video.fill").font(.caption2).foregroundStyle(.white).shadow(radius: 2).padding(8)
                    }
                }
                .accessibilityLabel("照片")
        }
    }

    private func metaLine(_ entry: DiaryEntry) -> String {
        [DiaryDates.fullWithWeekday(entry.displayDate), entry.placeName].compactMap { $0 }.joined(separator: " · ")
    }

    private func article(_ entry: DiaryEntry) -> some View {
        let segments = entry.displaySegments
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index == 0 {
                    let split = CaptionFormat.splitTitle(segment.text)
                    Text(split.title)
                        .font(.system(.title3, design: .serif, weight: .bold))
                    if !split.rest.isEmpty {
                        Text(split.rest)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(.primary.opacity(0.85))
                    }
                } else {
                    let label = segment.date.map { DiaryDates.gap(from: segments[index - 1].date, to: $0) }
                    HStack(spacing: 6) {
                        Rectangle().fill(.white.opacity(0.15)).frame(height: 1).accessibilityHidden(true)
                        Text(label.map { $0.relative } ?? String(localized: "未注明日期"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Rectangle().fill(.white.opacity(0.15)).frame(height: 1).accessibilityHidden(true)
                    }
                    .padding(.vertical, 4)
                    Text(segment.text)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.primary.opacity(0.85))
                }
            }
        }
    }

    @ViewBuilder private func chips(_ entry: DiaryEntry) -> some View {
        if !entry.tags.isEmpty {
            Text(entry.tags.map { "#\($0)#" }.joined(separator: "  "))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel(String(localized: "标签：\(entry.tags.formatted(.list(type: .and)))"))
        }
    }
}

struct ComposeRequest: Hashable {
    var assetID: String
}
