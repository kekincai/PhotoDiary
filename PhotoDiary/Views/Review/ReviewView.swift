import SwiftUI
import Photos
#if canImport(JournalingSuggestions) && JOURNALING_SUGGESTIONS
@preconcurrency import JournalingSuggestions
#endif

/// 回顾：参照照片 App 的精选集。那年今日、本周写作、一年回顾、还没写的照片、手记建议、标签。
struct ReviewView: View {
    @Environment(Router.self) private var router

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                OnThisDaySection()
                    .id("review-top")
                WeekSection()
                YearsSection()
                UnwrittenSection()
                SuggestionsSection()
                TagsSection()
            }
            .padding(.top, 8)
            .padding(.bottom, 150)
        }
        .collapsesTabBarOnScroll()
        // 再点“回顾”标签时滚回顶部（大标题重新展开）。
        .onChange(of: router.scrollToTopRequests[.review]) {
            withAnimation(.move) { proxy.scrollTo("review-top", anchor: .top) }
        }
        }
        .background(Color(.systemBackground))
        .navigationTitle("回顾")
        .toolbarTitleDisplayMode(.large)
        .toolbar { WideAddButton() }
        // 一年回顾的显影着色器先编好，点开第一张时不卡。
        .task { await ShaderWarmup.developing() }
    }
}

// MARK: 那年今日：横向翻页的大卡片，露出下一张的边缘

private struct OnThisDaySection: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.zoomNamespace) private var namespace
    @State private var page: String?

    var body: some View {
        let memories = store.onThisDay
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: String(localized: "那年今日", bundle: .app, locale: .app))
                .padding(.horizontal, 20)
            if memories.isEmpty {
                Text("往年的今天还没有日记")
                    .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Color.tile, in: .rect(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(memories) { entry in
                            card(entry)
                                .containerRelativeFrame(.horizontal) { width, _ in
                                    min(memories.count > 1 ? width - 60 : width - 32, 480)
                                }
                                .frame(height: 420)
                                // 不在中间的卡片略小一点；“减少动态效果”时不变。
                                .scrollTransition(.interactive, axis: .horizontal) { [reduceMotion] content, phase in
                                    content.scaleEffect(phase.isIdentity || reduceMotion ? 1 : 0.96)
                                }
                                .id(entry.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $page)
                .scrollIndicators(.hidden)

                if memories.count > 1 {
                    PageDots(count: memories.count, index: memories.firstIndex { $0.id == page } ?? 0)
                }
            }
        }
    }

    private func card(_ entry: DiaryEntry) -> some View {
        NavigationLink(value: Route.entry(entry.id)) {
            Color.black
                .overlay {
                    // 视差：翻页时照片比卡片走得慢一点，像隔着一扇窗（WWDC23“Beyond scroll views”的做法）。
                    AssetImage(id: entry.id, allowNetwork: true)
                        .scaleEffect(reduceMotion ? 1 : 1.2)
                        .scrollTransition(.interactive, axis: .horizontal) { [reduceMotion] content, phase in
                            content.offset(x: reduceMotion ? 0 : phase.value * -50)
                        }
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0), location: 0),
                        .init(color: .black.opacity(0.35), location: 0.4),
                        .init(color: .black.opacity(0.72), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: 260)
                }
                .overlay(alignment: .bottomLeading) { caption(entry) }
                .clipShape(.rect(cornerRadius: 24, style: .continuous))
                .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.press)
        .overlay(alignment: .bottomTrailing) {
            Button {
                router.editor = EditorRequest(assetID: entry.id, mode: .append, zoomSource: EditorRequest.appendButton(entry.id))
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.press)
            .glassEffect(.regular.interactive(), in: .circle)
            .zoomSource(EditorRequest.appendButton(entry.id), in: namespace, cornerRadius: 22)
            .environment(\.colorScheme, .dark)
            .padding(.trailing, 16)
            .padding(.bottom, 20)
            .accessibilityLabel("追加感想")
            .largeContent(String(localized: "追加感想", bundle: .app, locale: .app), systemImage: "plus")
        }
    }

    private func caption(_ entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(DiaryDates.onThisDay(entry.day))
                .font(.footnote.weight(.semibold))
                .tracking(0.3)
                .opacity(0.88)
            Text(entry.title)
                .font(.diary(23, bold: true, relativeTo: .title2))
                .lineSpacing(8)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            if let detail = detail(entry) {
                Text(detail)
                    .font(.footnote)
                    .opacity(0.82)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(.leading, 24)
        .padding(.trailing, 72)
        .padding(.bottom, 24)
    }

    /// Höfn í Hornafirði · 2 段
    private func detail(_ entry: DiaryEntry) -> String? {
        var parts: [String] = []
        if let place = entry.placeName { parts.append(place) }
        if entry.segments.count > 1 { parts.append(String(localized: "\(entry.segments.count) 段", bundle: .app, locale: .app)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color.ink.opacity(0.65) : Color.ink.opacity(0.18))
                    .frame(width: i == index ? 16 : 6, height: 6)
            }
        }
        .animation(.snappy, value: index)
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("第 \(index + 1) 篇，共 \(count) 篇")
    }
}

// MARK: 本周写作：按说明里的写作日期，写过的日子下面有一个点

private struct WeekSection: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Intelligence.self) private var intelligence
    @Environment(\.brand) private var brand
    /// 日期圆跟着字号一起变大。
    @ScaledMetric(relativeTo: .callout) private var circle: CGFloat = 34

    var body: some View {
        let week = store.weekWriting
        let today = DayStamp.today
        let names = DiaryDates.weekdaySymbols
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: headline)
                .contentTransition(.numericText())
                .padding(.horizontal, 20)
            HStack(spacing: 0) {
                ForEach(Array(week.enumerated()), id: \.offset) { i, item in
                    let isToday = item.day == today
                    VStack(spacing: 6) {
                        Text(names[i])
                            .font(.caption)
                            .foregroundStyle(Color.meta)
                        Text("\(item.day.day)")
                            .font(.callout.weight(isToday ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(isToday ? .white : (item.day > today ? Color(.tertiaryLabel) : Color.ink))
                            .frame(width: circle, height: circle)
                            .background(isToday ? brand : .clear, in: .circle)
                        Circle()
                            .fill(item.wrote ? brand : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(dayLabel(item, isToday: isToday))
                }
            }
            // 一行七天，字号封顶在辅助功能第一档，再大就挤不下了。
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.horizontal, 8)
            .padding(.vertical, 16)
            .background(Color.tile, in: .rect(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 16)
            if intelligence.isEnabled, !store.weekEntries.isEmpty {
                WeeklyReviewText(entries: store.weekEntries)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func dayLabel(_ item: DiaryStore.WeekDay, isToday: Bool) -> String {
        let date = DiaryDates.short(item.day)
        let label = item.wrote ? String(localized: "\(date)，写了日记", bundle: .app, locale: .app) : date
        return isToday ? String(localized: "今天，\(label)", bundle: .app, locale: .app) : label
    }

    private var headline: String {
        let n = store.writtenThisWeek
        return n == 0 ? String(localized: "这周还没写", bundle: .app, locale: .app) : String(localized: "这周写了 \(n) 篇", bundle: .app, locale: .app)
    }
}

/// 本周回顾：模型按这周的日记写两三句，宋体，像日记本身；逐字流出来。
/// 每次打开重新生成，只在内存里按“这周 + 这些日记”缓存，不写进照片。
private struct WeeklyReviewText: View {
    let entries: [DiaryEntry]
    @Environment(Intelligence.self) private var intelligence
    @State private var text = ""

    private var key: Int {
        var hasher = Hasher()
        hasher.combine(DayStamp.today.year)
        hasher.combine(Calendar.diary.component(.weekOfYear, from: .now))
        for e in entries { hasher.combine(e.id); hasher.combine(e.caption) }
        return hasher.finalize()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "apple.intelligence")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, 3)
                .accessibilityHidden(true)
            Text(text)
                .font(.diary(17, relativeTo: .body))
                .lineSpacing(7)
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.interpolate)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .opacity(text.isEmpty ? 0 : 1)
        .animation(.move, value: text.isEmpty)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("本周回顾"))
        .accessibilityValue(text)
        .task(id: key) {
            if let cached = intelligence.reviewCache, cached.key == key {
                text = cached.text
                return
            }
            text = ""
            let input = WeeklyReviewInput(entries: entries, language: Intelligence.languageName)
            do {
                for try await partial in intelligence.engine.weeklyReview(input) {
                    guard !Task.isCancelled else { return }
                    text = partial
                }
                if !text.isEmpty { intelligence.reviewCache = (key, text) }
            } catch {
                text = ""
            }
        }
    }
}

// MARK: 一年回顾：每个能回顾的年份一张封面（往年都有；今年到 12 月、或刚写满一年时才有）

private struct YearsSection: View {
    @Environment(DiaryStore.self) private var store
    @State private var open: YearInReview?

    var body: some View {
        let reviews = YearInReview.all(entries: store.diaries, today: .today)
        if !reviews.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: String(localized: "一年回顾", bundle: .app, locale: .app))
                    .padding(.horizontal, 20)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(reviews) { review in
                            tile(review)
                        }
                    }
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollIndicators(.hidden)
            }
            .fullScreenCover(item: $open) { review in
                YearReviewView(review: review)
            }
        }
    }

    private func tile(_ review: YearInReview) -> some View {
        Button { open = review } label: {
            AssetImage(id: review.cover, pointSize: CGSize(width: 160, height: 210))
                .frame(width: 160, height: 210)
                .overlay(alignment: .bottom) { PhotoScrim(edge: .bottom, strength: 0.6).frame(height: 120) }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: String(review.year))
                            .font(.diary(28, bold: true, relativeTo: .title))
                        Text("\(review.count) 篇")
                            .font(.footnote.weight(.semibold))
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                }
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.press)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(String(review.year))，\(review.count) 篇", bundle: .app, locale: .app))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("year-\(review.year)")
    }
}

// MARK: 还没写的照片：横排，点“写”直接打开编辑器

private struct UnwrittenSection: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @State private var photos: [(id: String, date: Date?)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { router.showAddFromPhotos = true } label: {
                SectionTitle(title: String(localized: "还没写的照片", bundle: .app, locale: .app), chevron: true)
            }
            .buttonStyle(.press)
            .padding(.horizontal, 20)
            if !photos.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(photos, id: \.id) { photo in
                            tile(photo)
                        }
                    }
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollIndicators(.hidden)
                .frame(height: 150)
                .padding(.top, 12)
            }
        }
        .task(id: store.diaries.count) {
            let recent = await Task.detached { AssetImages.recentAssets(limit: 60) }.value
            photos = Array(recent.filter { store.entry($0.id) == nil }.prefix(12))
        }
    }

    private func tile(_ photo: (id: String, date: Date?)) -> some View {
        let label = photo.date.map(dateLabel)
        return Button {
            router.editor = EditorRequest(assetID: photo.id, mode: .new)
        } label: {
            AssetImage(id: photo.id, pointSize: CGSize(width: 150, height: 150))
                .frame(width: 150, height: 150)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if let label {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 6)
                            .padding(.leading, 10)
                            .padding(.top, 8)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Text("写")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .glassEffect(.regular, in: .capsule)
                        .environment(\.colorScheme, .dark)
                        .padding(8)
                }
        }
        .buttonStyle(.press)
        .accessibilityLabel(label.map { Text("给\($0)的照片写日记") } ?? Text("给这张照片写日记"))
    }

    private func dateLabel(_ date: Date) -> String {
        let day = DayStamp(date)
        return day == .today ? String(localized: "今天", bundle: .app, locale: .app) : DiaryDates.short(day)
    }
}

// MARK: 手记建议：系统整理的最近时刻（地点、照片、听过的歌），挑一个就打开那张照片的编辑器

/// 系统只开放挑选面板，App 读不到建议列表，所以这里是一个打开面板的入口。
/// 需要付费开发者账号的权限，没开 JOURNALING_SUGGESTIONS 时整组不编译（见 project.yml）；模拟器的 SDK 也没有这个框架。
private struct SuggestionsSection: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Router.self) private var router
    @State private var picking = false
    @State private var noPhoto = false

    var body: some View {
        #if canImport(JournalingSuggestions) && JOURNALING_SUGGESTIONS
        Button { picking = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: 12, style: .continuous)
                    )
                Text("手记建议")
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(14)
            .background(Color.tile, in: .rect(cornerRadius: 24, style: .continuous))
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.press)
        .padding(.horizontal, 16)
        .journalingSuggestionsPicker(isPresented: $picking) { suggestion in
            await open(suggestion)
        }
        .alert("这段时间没有照片", isPresented: $noPhoto) {
            Button("好") {}
        }
        #endif
    }

    #if canImport(JournalingSuggestions) && JOURNALING_SUGGESTIONS
    /// 找回建议里那张照片（或那段时间的第一张），歌曲、播客预先写进正文。
    private func open(_ suggestion: JournalingSuggestion) async {
        let photos = await suggestion.content(forType: JournalingSuggestion.Photo.self)
        let livePhotos = await suggestion.content(forType: JournalingSuggestion.LivePhoto.self)
        let dates = photos.compactMap(\.date) + livePhotos.compactMap(\.date)
        let interval = suggestion.date
        let id = await Task.detached { AssetImages.asset(takenAt: dates, orIn: interval) }.value
        guard let id else { noPhoto = true; return }

        let songs = await suggestion.content(forType: JournalingSuggestion.Song.self)
            .map { [$0.song, $0.artist].compactMap { $0 }.joined(separator: " – ") }
        let podcasts = await suggestion.content(forType: JournalingSuggestion.Podcast.self)
            .map { [$0.episode, $0.show].compactMap { $0 }.joined(separator: " – ") }
        let lines = (songs + podcasts).filter { !$0.isEmpty }.map { "♪ \($0)" }
        router.editor = EditorRequest(assetID: id, mode: store.entry(id) == nil ? .new : .append,
                                      seed: lines.isEmpty ? nil : lines.joined(separator: "\n") + "\n")
    }
    #endif
}

// MARK: 标签：两列封面（前 4 个）

private struct TagsSection: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.isWide) private var wide
    private var columns: [GridItem] {
        wide ? [GridItem(.adaptive(minimum: 200), spacing: 16)] : Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)
    }

    var body: some View {
        let tags = store.tagCounts
        // 没有标签时整组不显示。
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink(value: Route.tags) {
                    SectionTitle(title: String(localized: "标签", bundle: .app, locale: .app), chevron: true)
                }
                .buttonStyle(.press)
                .padding(.horizontal, 20)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(tags.prefix(4), id: \.name) { tag in
                        NavigationLink(value: Route.tag(tag.name)) {
                            TagCover(name: tag.name, detail: String(localized: "\(tag.count) 篇", bundle: .app, locale: .app))
                        }
                        .buttonStyle(.press)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
