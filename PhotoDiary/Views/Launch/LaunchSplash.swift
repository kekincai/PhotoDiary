import SwiftUI

/// 开屏动画，接在系统启动画面（Info.plist 的 UILaunchScreen）后面，第一帧和它完全一样：
/// 书签先往下一蹲再弹起来，太阳“啵”地弹出，山从下面冒上来，App 名一个字一个字跳出来；
/// 本地索引读好后书签缩一下蓄力，镜头穿过太阳的圆孔，露出日记。等得久时书签原地蹦跳，表示没卡住。
/// “减少动态效果”时不移动、不缩放，只做淡入淡出。
struct LaunchSplash: View {
    /// 本地索引已读入（或没有照片权限，直接去权限页）。
    let ready: Bool
    let onFinish: () -> Void

    static private(set) var finished = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// ready 的副本。.task 里拿到的是开始时的 self，直接读 ready 永远是旧值；
    /// 索引在开场动画播完前就读好时，就会一直停在开屏上。
    @State private var isReady = false
    @State private var introDone = false
    @State private var popped = false
    @State private var sunIn = false
    @State private var hillsIn = false
    @State private var letters = 0
    /// 起跳前下蹲、退场前蓄力时整体缩小。
    @State private var crouch = false
    /// 等待时的蹦跳：竖直位移和压扁程度（<1 压扁，>1 拉长）。
    @State private var hopY: CGFloat = 0
    @State private var squash: CGFloat = 1
    @State private var leaving = false
    @State private var exit: CGFloat = 0

    private let title = Array(String(localized: "照片日记"))
    /// 启动画面里书签的宽度（Tools/AppIcon/make-icon.swift 生成的 LaunchMark）。
    private static let markWidth: CGFloat = 64

    private var palette: SplashPalette { colorScheme == .dark ? .dark : .light }
    private var markScale: CGFloat {
        guard !reduceMotion else { return 1 }
        return (popped ? 1.25 : 1) * (crouch ? 0.88 : 1)
    }
    private var lift: CGFloat { popped && !reduceMotion ? -36 : 0 }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2 + lift)
            let unit = Self.markWidth * markScale / MarkGeometry.bounds.width
            let sun = MarkGeometry.sunCenter
            let focus = CGPoint(x: center.x + sun.x * unit, y: center.y + sun.y * unit)

            ZStack {
                // 不读 LaunchBackground：那个颜色集为启动画面快照的色差做过补偿（见 make-icon.swift），
                // 这里直接画原色，和系统显示出来的启动画面一致。
                palette.background
                mark
                    .frame(width: Self.markWidth, height: Self.markWidth * MarkGeometry.aspect)
                    .scaleEffect(x: 2 - squash, y: squash, anchor: .bottom)
                    .scaleEffect(markScale)
                    .offset(y: hopY)
                    .position(center)
                titleView
                    .position(x: center.x, y: center.y + Self.markWidth * MarkGeometry.aspect * markScale / 2 + 34)
                    .opacity(leaving ? 0 : 1)
            }
            .frame(width: size.width, height: size.height)
            .modifier(IrisZoom(progress: exit, focus: focus, holeRadius: MarkGeometry.sunRadius * unit + 0.5, size: size))
            .opacity(reduceMotion && leaving ? 0 : 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(!leaving)
        .accessibilityHidden(true)
        // 启动画面不显示状态栏（Info.plist），这里也藏起来，退场后再出现，免得白字变黑字。
        .statusBarHidden(!leaving)
        .task { await playIntro() }
        .onChange(of: ready, initial: true) {
            isReady = ready
            leaveIfReady()
        }
    }

    /// 书签减去镂空；镂空下面垫着弹出来的太阳和冒上来的山，从镂空里看得到。
    private var mark: some View {
        ZStack {
            MarkPart.sun.fill(palette.sun).stroke(palette.sun, lineWidth: 1)
                .scaleEffect(sunIn || reduceMotion ? 1 : 0.2, anchor: MarkGeometry.sunAnchor)
                .opacity(sunIn ? 1 : 0)
            MarkPart.mountains.fill(palette.mountains).stroke(palette.mountainEdge, lineWidth: 1)
                .offset(y: hillsIn || reduceMotion ? 0 : 18)
                .opacity(hillsIn ? 1 : 0)
            MarkPart.glyph.fill(palette.glyph, style: FillStyle(eoFill: true))
        }
    }

    private var titleView: some View {
        HStack(spacing: title.allSatisfy(\.isASCII) ? 1 : 6) {
            ForEach(title.indices, id: \.self) { i in
                let shown = i < letters || reduceMotion
                Text(String(title[i]))
                    .scaleEffect(shown ? 1 : 0.3, anchor: .bottom)
                    .offset(y: shown ? 0 : 18)
                    .opacity(i < letters ? 1 : 0)
            }
        }
        .font(.diary(26, bold: true, relativeTo: .title))
        .foregroundStyle(palette.glyph)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .fixedSize()
    }

    private func playIntro() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.4)) {
                sunIn = true
                hillsIn = true
                letters = title.count
            }
            try? await Task.sleep(for: .milliseconds(600))
        } else {
            // 先停一下，让启动画面到 App 的交接看不出来；然后下蹲、弹起。
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.12)) { crouch = true }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(duration: 0.6, bounce: 0.45)) {
                crouch = false
                popped = true
            }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(duration: 0.5, bounce: 0.6)) { sunIn = true }
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.spring(duration: 0.55, bounce: 0.45)) { hillsIn = true }
            try? await Task.sleep(for: .milliseconds(120))
            // 字多（英文）时每个字间隔短一点，总时长差不多。
            let step = min(70, 300 / max(title.count, 1))
            for i in title.indices {
                withAnimation(.spring(duration: 0.45, bounce: 0.55)) { letters = i + 1 }
                try? await Task.sleep(for: .milliseconds(step))
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        introDone = true
        leaveIfReady()
        while !reduceMotion && !leaving && !Task.isCancelled {
            await hop()
        }
    }

    /// 原地蹦一下：下蹲、拉长起跳、落地压扁再弹回。每一步前都看一眼是否已经开始退场。
    private func hop() async {
        func step(_ animation: Animation, _ ms: Int, _ change: () -> Void) async {
            guard !leaving else { return }
            withAnimation(animation, change)
            try? await Task.sleep(for: .milliseconds(ms))
        }
        await step(.easeOut(duration: 0.12), 120) { squash = 0.88 }
        await step(.easeOut(duration: 0.22), 220) { squash = 1.06; hopY = -18 }
        await step(.easeIn(duration: 0.18), 180) { squash = 1; hopY = 0 }
        await step(.easeOut(duration: 0.08), 80) { squash = 0.9 }
        await step(.spring(duration: 0.45, bounce: 0.6), 700) { squash = 1 }
    }

    private func leaveIfReady() {
        guard isReady, introDone, !leaving else { return }
        Self.finished = true
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.3)) { leaving = true } completion: { onFinish() }
            return
        }
        // 蓄力：缩一下（顺便收回蹦跳），再一头扎进太阳。
        withAnimation(.easeOut(duration: 0.16)) {
            leaving = true
            crouch = true
            hopY = 0
            squash = 1
        }
        withAnimation(.timingCurve(0.55, 0, 0.75, 0.6, duration: 0.75).delay(0.14)) { exit = 1 } completion: {
            onFinish()
        }
    }
}

/// 穿过太阳：先在太阳处开一个圆孔，再以它为中心放大并移到屏幕中央，直到孔盖住整个屏幕。
/// 缩放按指数增长，看起来是匀速向前推进。
private struct IrisZoom: ViewModifier, Animatable {
    var progress: CGFloat
    let focus: CGPoint
    let holeRadius: CGFloat
    let size: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let open = min(1, progress / 0.15)
        let reach = hypot(size.width, size.height) / 2 * 1.15
        let scale = pow(reach / holeRadius, progress)
        content
            .mask {
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: size).insetBy(dx: -1, dy: -1))
                    let r = holeRadius * open
                    p.addEllipse(in: CGRect(x: focus.x - r, y: focus.y - r, width: r * 2, height: r * 2))
                }
                .fill(style: FillStyle(eoFill: true))
            }
            .scaleEffect(scale, anchor: UnitPoint(x: focus.x / size.width, y: focus.y / size.height))
            .offset(x: (size.width / 2 - focus.x) * progress, y: (size.height / 2 - focus.y) * progress)
    }
}

private struct SplashPalette {
    let background: Color
    let glyph: Color
    let sun: Color
    let mountains: LinearGradient
    let mountainEdge: Color

    static let light = SplashPalette(
        background: Color(hex: "#2F6690"),
        glyph: .white,
        sun: Color(hex: "#FFC65C"),
        mountains: LinearGradient(colors: [Color(hex: "#8FD3B6"), Color(hex: "#3E8F78")], startPoint: .top, endPoint: .bottom),
        mountainEdge: Color(hex: "#5FAF95"))
    static let dark = SplashPalette(
        background: Color(hex: "#0E151C"),
        glyph: Color(hex: "#8EC0E6"),
        sun: Color(hex: "#F2B85B"),
        mountains: LinearGradient(colors: [Color(hex: "#4F9C86"), Color(hex: "#2D6457")], startPoint: .top, endPoint: .bottom),
        mountainEdge: Color(hex: "#3F8070"))
}

/// 和 App 图标同一个图形（Tools/AppIcon/make-icon.swift），坐标是 1024 画布上的。
nonisolated private enum MarkGeometry {
    static let bounds = CGRect(x: 322, y: 176, width: 380, height: 672)
    static var aspect: CGFloat { bounds.height / bounds.width }
    static let sunRect = CGRect(x: 548, y: 286, width: 92, height: 92)
    static var sunRadius: CGFloat { sunRect.width / 2 }
    /// 太阳中心在书签框里的位置（缩放锚点）。
    static var sunAnchor: UnitPoint {
        UnitPoint(x: (sunRect.midX - bounds.minX) / bounds.width, y: (sunRect.midY - bounds.minY) / bounds.height)
    }
    /// 太阳中心相对书签中心的偏移。
    static var sunCenter: CGPoint { CGPoint(x: sunRect.midX - bounds.midX, y: sunRect.midY - bounds.midY) }
    static let mountains: [CGPoint] = [
        CGPoint(x: 376, y: 590), CGPoint(x: 476, y: 432), CGPoint(x: 540, y: 520),
        CGPoint(x: 586, y: 466), CGPoint(x: 648, y: 590),
    ]

    static func bookmark(_ p: inout Path) {
        let left: CGFloat = 322, right: CGFloat = 702, top: CGFloat = 176, bottom: CGFloat = 848, notch: CGFloat = 132, r: CGFloat = 46
        p.move(to: CGPoint(x: left, y: top + r))
        p.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: left + r, y: top), radius: r)
        p.addArc(tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right, y: top + r), radius: r)
        p.addLine(to: CGPoint(x: right, y: bottom))
        p.addLine(to: CGPoint(x: (left + right) / 2, y: bottom - notch))
        p.addLine(to: CGPoint(x: left, y: bottom))
        p.closeSubpath()
    }
}

nonisolated private enum MarkPart: Shape {
    case glyph, sun, mountains

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch self {
        case .glyph:
            MarkGeometry.bookmark(&p)
            p.addEllipse(in: MarkGeometry.sunRect)
            p.addLines(MarkGeometry.mountains)
            p.closeSubpath()
        case .sun:
            p.addEllipse(in: MarkGeometry.sunRect)
        case .mountains:
            p.addLines(MarkGeometry.mountains)
            p.closeSubpath()
        }
        let b = MarkGeometry.bounds
        let s = rect.width / b.width
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: s, y: s)
            .translatedBy(x: -b.minX, y: -b.minY))
    }
}

#Preview("开屏动画") {
    @Previewable @State var run = 0
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        Button("重播") { run += 1 }
        LaunchSplash(ready: true) {}
            .id(run)
    }
}
