import SwiftUI

/// 一年回顾：全屏、左右翻的一叠卡片。封面（年份、篇数）→ 写得最多的月份 → 标签 → 地点 → 挑出来的几篇 → 分享图。
///
/// 这是 App 里唯一“有表演”的地方：每张照片第一次翻到时像拍立得一样显影（DevelopingPhoto）。
/// 翻页是分页滚动视图，全程跟手、可以中途抓回来；点右边下一张、点左边上一张，都不等显影。
/// “减少动态效果”时不滑动、不显影，卡片之间淡入淡出。
struct YearReviewView: View {
    let review: YearInReview

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: YearCard?
    /// “减少动态效果”时的当前页。
    @State private var index = 0
    /// 一页的宽度：点左边三分之一上一张，其余下一张。
    @State private var pageWidth: CGFloat = 390

    private var cards: [YearCard] { YearCard.cards(for: review) }
    private var current: Int {
        reduceMotion ? index : (position.flatMap(cards.firstIndex(of:)) ?? 0)
    }

    var body: some View {
        let cards = cards
        ZStack {
            Color.black.ignoresSafeArea()
            backdrop(cards[min(current, cards.count - 1)])
            if reduceMotion {
                fading(cards)
            } else {
                paging(cards)
            }
        }
        .overlay(alignment: .top) { header(count: cards.count) }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .sensoryFeedback(.selection, trigger: current)
    }

    // MARK: 翻页

    private func paging(_ cards: [YearCard]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(cards, id: \.self) { card in
                    page(card, active: card == (position ?? cards.first))
                        .containerRelativeFrame(.horizontal)
                        // 翻到一半时略微缩小、变暗，松手后落定。
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(1 - abs(phase.value) * 0.06)
                                .opacity(1 - abs(phase.value) * 0.35)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $position)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
    }

    private func fading(_ cards: [YearCard]) -> some View {
        page(cards[index], active: true)
            .id(cards[index])
            .transition(.opacity)
            .gesture(DragGesture(minimumDistance: 24).onEnded { value in
                if value.translation.width < -40 { go(by: 1) } else if value.translation.width > 40 { go(by: -1) }
            })
            // 没有滚动视图时，VoiceOver（三指轻扫）和切换控制靠这个翻页，不然只能停在封面上。
            .accessibilityScrollAction { edge in
                switch edge {
                case .trailing, .bottom: go(by: 1)
                case .leading, .top: go(by: -1)
                }
            }
    }

    private func page(_ card: YearCard, active: Bool) -> some View {
        YearCardView(card: card, review: review, active: active)
            .padding(.top, 64)
            .padding(.bottom, 32)
            .contentShape(.rect)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
            // 点右边三分之二下一张，左边三分之一上一张（和“快拍”一样）。卡片里的按钮先拿到点按。
            .onTapGesture(coordinateSpace: .local) { location in
                go(by: location.x < pageWidth / 3 ? -1 : 1)
            }
            .accessibilityElement(children: .contain)
    }

    private func go(by step: Int) {
        let cards = cards
        let target = min(max(current + step, 0), cards.count - 1)
        guard target != current else { return }
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.25)) { index = target }
        } else {
            withAnimation(.move) { position = cards[target] }
        }
    }

    // MARK: 顶部：页码条、关闭

    private func header(count: Int) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(.white.opacity(i <= current ? 0.9 : 0.25))
                        .frame(height: 3)
                }
            }
            .animation(.snappy, value: current)
            .accessibilityHidden(true)
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.press)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("关闭")
                .accessibilityIdentifier("yearReviewClose")
                .largeContent(String(localized: "关闭", bundle: .app, locale: .app), systemImage: "xmark")
            }
        }
        .padding(.horizontal, Metrics.page)
        .padding(.top, 8)
    }

    /// 背后铺一层这张卡片的照片，虚化压暗：颜色交给照片。
    private func backdrop(_ card: YearCard) -> some View {
        Group {
            if let id = card.photo(in: review) {
                AssetImage(id: id, pointSize: CGSize(width: 48, height: 48))
                    .blur(radius: 40)
                    .overlay(Color.black.opacity(0.5))
                    .id(id)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: card)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 回顾里的一张卡片。
enum YearCard: Hashable {
    case cover, months, tags, places
    case entry(String)
    case share

    /// 有内容的卡片才出现：只写过一个月就不讲“哪个月最多”，没有标签、地点就跳过。
    static func cards(for review: YearInReview) -> [YearCard] {
        var cards: [YearCard] = [.cover]
        if review.activeMonths > 1 { cards.append(.months) }
        if !review.tags.isEmpty { cards.append(.tags) }
        if !review.places.isEmpty { cards.append(.places) }
        cards += review.highlights.map { .entry($0.id) }
        cards.append(.share)
        return cards
    }

    /// 这张卡片的主照片（背景也用它）。
    func photo(in review: YearInReview) -> String? {
        switch self {
        case .cover: review.cover
        case .months: review.highlights.first { $0.day.month == review.busiestMonth }?.id ?? review.cover
        case .tags: review.tags.first?.cover
        case .places: review.places.first?.cover
        case .entry(let id): id
        case .share: review.cover
        }
    }
}

// MARK: 卡片

private struct YearCardView: View {
    let card: YearCard
    let review: YearInReview
    let active: Bool

    var body: some View {
        switch card {
        case .cover:
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                Polaroid(id: review.cover, active: active, width: 260, tilt: -4) {
                    Text(verbatim: String(review.year))
                        .font(.diary(30, bold: true, relativeTo: .largeTitle))
                }
                Text("\(review.count) 篇")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        case .months:
            MonthsCard(review: review, active: active)
        case .tags:
            RankedCard(title: String(localized: "标签", bundle: .app, locale: .app), items: review.tags,
                       isTag: true, active: active)
        case .places:
            RankedCard(title: String(localized: "地点", bundle: .app, locale: .app), items: review.places,
                       isTag: false, active: active)
        case .entry(let id):
            if let entry = review.highlights.first(where: { $0.id == id }) {
                EntryCardPage(entry: entry, active: active)
            }
        case .share:
            ShareCardPage(review: review)
        }
    }
}

/// 拍立得：白框、正方形照片、下面宽一点的白边，白边上可以写一行字。整张微微倾斜。
private struct Polaroid<Caption: View>: View {
    let id: String
    let active: Bool
    var width: CGFloat
    var tilt: Double = 0
    @ViewBuilder var caption: Caption

    var body: some View {
        let border = width * 0.06
        let photo = width - border * 2
        VStack(spacing: 0) {
            DevelopingPhoto(id: id, active: active, pointSize: CGSize(width: photo, height: photo))
                .frame(width: photo, height: photo)
                .clipShape(.rect(cornerRadius: 3, style: .continuous))
            caption
                .foregroundStyle(Color(white: 0.2))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: width * 0.22)
                .padding(.horizontal, border)
        }
        .padding([.top, .horizontal], border)
        .padding(.bottom, border * 0.5)
        .frame(width: width)
        .background(MarkPalette.light.frame, in: .rect(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        .rotationEffect(.degrees(tilt))
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// 写得最多的月份：一行十二根柱子，那个月是白的。
private struct MonthsCard: View {
    let review: YearInReview
    let active: Bool

    var body: some View {
        let month = Calendar.diary.date(from: DateComponents(year: review.year, month: review.busiestMonth, day: 1)) ?? .now
        let monthName = DiaryDates.monthName(month)
        VStack(spacing: 32) {
            Spacer(minLength: 0)
            if let id = YearCard.months.photo(in: review) {
                Polaroid(id: id, active: active, width: 200, tilt: 3) { EmptyView() }
            }
            Text("\(monthName)写得最多")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            bars
                .frame(height: 96)
                .padding(.horizontal, 32)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var bars: some View {
        let top = max(review.monthCounts.max() ?? 1, 1)
        let symbols = Self.monthSymbols
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<12, id: \.self) { i in
                let count = review.monthCounts[i]
                VStack(spacing: 6) {
                    Capsule()
                        .fill(.white.opacity(i + 1 == review.busiestMonth ? 0.95 : 0.3))
                        .frame(height: max(4, 72 * CGFloat(count) / CGFloat(top)))
                        .frame(maxHeight: 72, alignment: .bottom)
                    Text(verbatim: symbols[i])
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenCounts(review))
    }

    /// 柱子下面的月份：J F M… / 1 2 3…（太长的就用数字）。
    private static var monthSymbols: [String] {
        let symbols = DiaryDates.veryShortMonthSymbols
        if symbols.count == 12, symbols.allSatisfy({ $0.count <= 2 }) { return symbols }
        return (1...12).map(String.init)
    }

    /// 读屏：“1月，2 篇、3月，1 篇和……”（只读写过的月份，按界面语言连起来）。
    private static func spokenCounts(_ review: YearInReview) -> String {
        review.monthCounts.enumerated().filter { $0.element > 0 }.map { i, count in
            let date = Calendar.diary.date(from: DateComponents(year: review.year, month: i + 1, day: 1)) ?? .now
            return String(localized: "\(DiaryDates.monthName(date))，\(count) 篇", bundle: .app, locale: .app)
        }.formatted(.list(type: .and).locale(.app))
    }
}

/// 标签、地点：封面拍立得 + 前几名和篇数。
private struct RankedCard: View {
    let title: String
    let items: [YearInReview.Ranked]
    let isTag: Bool
    let active: Bool
    @Environment(\.brand) private var brand

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            if let cover = items.first?.cover {
                Polaroid(id: cover, active: active, width: 200, tilt: isTag ? -3 : 2) { EmptyView() }
            }
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                ForEach(items, id: \.name) { item in
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: isTag ? "#\(item.name)#" : item.name)
                            .font(.headline)
                            .foregroundStyle(isTag ? brand : .white)
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        Text("\(item.count) 篇")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 40)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 挑出来的一篇：照片铺满，底部压日期和第一行（宋体）。
private struct EntryCardPage: View {
    let entry: DiaryEntry
    let active: Bool

    var body: some View {
        GeometryReader { proxy in
            DevelopingPhoto(id: entry.id, active: active, pointSize: proxy.size)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipShape(.rect(cornerRadius: Metrics.Radius.hero, style: .continuous))
                .overlay(alignment: .bottom) {
                    PhotoScrim(edge: .bottom, strength: 0.7)
                        .frame(height: min(320, proxy.size.height * 0.55))
                        .clipShape(.rect(cornerRadius: Metrics.Radius.hero, style: .continuous))
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text([DiaryDates.dayTitle(entry.displayDate), entry.placeName].compactMap { $0 }.joined(separator: " · "))
                            .font(.footnote.weight(.semibold))
                            .opacity(0.85)
                        Text(entry.title)
                            .font(.diary(26, bold: true, relativeTo: .title))
                            .lineSpacing(8)
                            .lineLimit(4)
                    }
                    .foregroundStyle(.white)
                    .padding(24)
                    .padding(.bottom, 8)
                }
        }
        .padding(.horizontal, Metrics.page)
        .accessibilityElement(children: .combine)
    }
}

/// 最后一张：分享图的预览和分享按钮。
private struct ShareCardPage: View {
    let review: YearInReview
    @Environment(\.brand) private var brand

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            YearShareCard(review: review) { id in AssetImage(id: id) }
                .frame(width: SharePaper.width)
                .clipShape(.rect(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                .scaleEffect(0.78)
                .frame(height: 470)
                .accessibilityHidden(true)
            let shared = SharedYear(review: review, brand: brand)
            ShareLink(item: shared, preview: SharePreview(String(review.year), image: shared)) {
                Label("分享", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 52)
            }
            .buttonStyle(.press)
            .glassEffect(.regular.interactive(), in: .capsule)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}
