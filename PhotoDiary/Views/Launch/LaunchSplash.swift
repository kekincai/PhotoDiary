import SwiftUI

/// 开屏动画，接在系统启动画面（Info.plist 的 UILaunchScreen）后面，第一帧和它完全一样：
/// 一张还没显影的拍立得。然后照片慢慢显影（太阳从山后升起来），白边上的一行字自己写出来，
/// App 名一个字一个字浮上来；本地索引读好后，镜头推进照片里，露出日记。
/// 等得久时太阳的光晕缓缓呼吸，表示没卡住。“减少动态效果”时只做淡入淡出。
struct LaunchSplash: View {
    /// 本地索引已读入（或没有照片权限，直接去权限页）。
    let ready: Bool
    let onFinish: () -> Void

    static private(set) var finished = false
    private static let holdForDebugging = ProcessInfo.processInfo.arguments.contains("-holdSplash")

    @Environment(\.accessibilityReduceMotion) private var motionReduced
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.colorScheme) private var colorScheme
    /// “减少动态效果”或 VoiceOver 开着：不做开场表演，淡入淡出后直接进 App。
    private var reduceMotion: Bool { motionReduced || voiceOver }
    /// ready 的副本。.task 里拿到的是开始时的 self，直接读 ready 永远是旧值；
    /// 索引在开场动画播完前就读好时，就会一直停在开屏上。
    @State private var isReady = false
    @State private var introDone = false
    @State private var developed: Double = 0
    @State private var written: Double = 0
    @State private var letters = 0
    @State private var glow: Double = 0
    @State private var leaving = false
    @State private var exit: CGFloat = 0

    private let title = Array(String(localized: "照片日记", bundle: .app, locale: .app))
    /// 启动画面里拍立得的宽度（Tools/AppIcon/make-icon.swift 生成的 LaunchMark）。
    static let markWidth: CGFloat = 88

    private var palette: MarkPalette { colorScheme == .dark ? .dark : .light }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            ZStack {
                // 不读 LaunchBackground：那个颜色集为启动画面快照的色差做过补偿（见 make-icon.swift），
                // 这里直接画原色，和系统显示出来的启动画面一致。
                palette.background
                sunGlow
                    .position(center)
                mark
                    .position(center)
                titleView
                    .position(x: center.x, y: center.y + Self.markWidth * MarkGeometry.aspect / 2 + 44)
                    .opacity(leaving ? 0 : 1)
            }
            .frame(width: size.width, height: size.height)
            // 退场：推进照片里。整个画面以照片区域为中心放大，同时淡出。
            .scaleEffect(reduceMotion ? 1 : 1 + exit * 5, anchor: photoAnchor(in: size, center: center))
            .opacity(1 - exit)
        }
        .ignoresSafeArea()
        .allowsHitTesting(!leaving)
        .accessibilityHidden(true)
        // 启动画面不显示状态栏（Info.plist），这里也藏起来，退场后再出现，免得白字变黑字。
        .statusBarHidden(!leaving)
        .task { await playIntro() }
        .onChange(of: ready, initial: true) {
            // 调试：带 -holdSplash 启动时多停几秒，方便截图和录屏。
            if ready, Self.holdForDebugging { Task { try? await Task.sleep(for: .seconds(6)); isReady = true; leaveIfReady() }; return }
            isReady = ready
            leaveIfReady()
        }
    }

    /// 照片区域在屏幕上的位置（白框居中、微微倾斜，近似取未旋转的位置）。
    private func photoAnchor(in size: CGSize, center: CGPoint) -> UnitPoint {
        let w = Self.markWidth, h = w * MarkGeometry.aspect
        let anchor = MarkGeometry.photoAnchor
        let x = center.x - w / 2 + anchor.x * w
        let y = center.y - h / 2 + anchor.y * h
        return UnitPoint(x: x / size.width, y: y / size.height)
    }

    private var mark: some View {
        BrandMark(width: Self.markWidth, palette: palette, developed: developed, written: written)
    }

    /// 太阳背后的暖光：显影时亮起来，等待时缓缓呼吸。
    private var sunGlow: some View {
        let w = Self.markWidth, h = w * MarkGeometry.aspect
        let anchor = MarkGeometry.sunAnchor
        return RadialGradient(colors: [palette.sun.opacity(0.42), palette.sun.opacity(0)], center: .center,
                              startRadius: 0, endRadius: w * 2.2)
            .frame(width: w * 4.4, height: w * 4.4)
            .offset(x: (anchor.x - 0.5) * w, y: (anchor.y - 0.5) * h)
            .opacity(glow)
            .blendMode(colorScheme == .dark ? .screen : .plusLighter)
    }

    private var titleView: some View {
        HStack(spacing: title.allSatisfy(\.isASCII) ? 1 : 6) {
            ForEach(title.indices, id: \.self) { i in
                let shown = i < letters || reduceMotion
                Text(String(title[i]))
                    .offset(y: shown ? 0 : 10)
                    .blur(radius: shown ? 0 : 4)
                    .opacity(i < letters ? 1 : 0)
            }
        }
        .font(.diary(26, bold: true, relativeTo: .title))
        .foregroundStyle(palette.frame)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .fixedSize()
    }

    private func playIntro() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.5)) {
                developed = 1
                written = 1
                letters = title.count
                glow = 0.6
            }
            try? await Task.sleep(for: .milliseconds(700))
        } else {
            // 先停一下，让启动画面到 App 的交接看不出来；然后显影。
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.easeInOut(duration: 1.0)) { developed = 1 }
            withAnimation(.easeOut(duration: 0.9).delay(0.2)) { glow = 0.6 }
            try? await Task.sleep(for: .milliseconds(620))
            // 笔迹：先慢后快再收笔。
            withAnimation(.timingCurve(0.4, 0, 0.3, 1, duration: 0.7)) { written = 1 }
            try? await Task.sleep(for: .milliseconds(320))
            // 字多（英文）时每个字间隔短一点，总时长差不多。
            let step = min(60, 260 / max(title.count, 1))
            for i in title.indices {
                withAnimation(.easeOut(duration: 0.35)) { letters = i + 1 }
                try? await Task.sleep(for: .milliseconds(step))
            }
            try? await Task.sleep(for: .milliseconds(380))
        }
        introDone = true
        leaveIfReady()
        // 等待：光晕呼吸。
        while !reduceMotion && !leaving && !Task.isCancelled {
            withAnimation(.easeInOut(duration: 1.1)) { glow = 0.3 }
            try? await Task.sleep(for: .milliseconds(1100))
            guard !leaving else { break }
            withAnimation(.easeInOut(duration: 1.1)) { glow = 0.7 }
            try? await Task.sleep(for: .milliseconds(1100))
        }
    }

    private func leaveIfReady() {
        guard isReady, introDone, !leaving else { return }
        Self.finished = true
        leaving = true
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.3)) { exit = 1 } completion: { onFinish() }
            return
        }
        // 推进照片里：先微微停一下再加速。
        withAnimation(.timingCurve(0.6, 0, 0.8, 0.4, duration: 0.62).delay(0.08)) { exit = 1 } completion: {
            onFinish()
        }
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
