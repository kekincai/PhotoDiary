import SwiftUI
import Photos

/// 写日记 / 追加感想 / 编辑说明。
/// 整页是一张翻过来的相纸：照片左右镜像、隔着纸隐约透出来，字就写在纸背上——人们本来就是这样在照片背面记日记的。
/// 以前写的几行留在纸上（退后一层），下面一条“今天”的分隔线，再往下是新写的字。
struct EditorView: View {
    let assetID: String
    let mode: DiaryStore.WriteMode
    /// 打开时先露出照片正面，再翻到纸背；关闭时翻回去（iPhone 全屏呈现时）。
    var flips = false
    /// saved = true 表示已写入照片说明。
    var onFinish: (_ saved: Bool) -> Void

    @Environment(DiaryStore.self) private var store
    @Environment(Intelligence.self) private var intelligence
    @Environment(\.brand) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controller: EditorController
    /// 0 = 照片正面朝上，1 = 翻到纸背。
    @State private var turned: Double
    @State private var closing = false
    /// 点 ✓ 后：字轻轻下沉、落定成正文颜色。写入失败时恢复。
    @State private var inkSettled = false
    /// 模型按正文建议的标签；点一下才写进正文。
    @State private var suggested: [String] = []
    @State private var original: String
    @State private var saving = false
    @State private var confirmDiscard = false
    @State private var confirmClear = false
    @State private var errorMessage: String?
    @State private var savedCount = 0

    init(assetID: String, mode: DiaryStore.WriteMode, existingCaption: String?, seed: String? = nil, flips: Bool = false,
         onFinish: @escaping (Bool) -> Void) {
        self.assetID = assetID
        self.mode = mode
        self.flips = flips
        self.onFinish = onFinish
        _turned = State(initialValue: flips ? 0 : 1)
        let initial = mode == .edit ? (existingCaption ?? "") : ""
        _controller = State(initialValue: EditorController(text: mode == .edit ? initial : (seed ?? "")))
        _original = State(initialValue: initial)
    }

    private var entry: DiaryEntry? { store.entry(assetID) }
    private var asset: PHAsset? { AssetImages.shared.asset(assetID) }
    private var photoDate: Date { entry?.displayDate ?? asset?.creationDate ?? .now }

    private var isDirty: Bool { controller.text != original }
    private var canSave: Bool {
        switch mode {
        case .new, .append: !controller.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .edit: isDirty
        }
    }

    private var isShared: Bool {
        entry?.isCloudShared ?? asset?.sourceType.contains(.typeCloudShared) ?? false
    }

    var body: some View {
        FlipCard(progress: turned, crossfade: reduceMotion) {
            photoFront
        } back: {
            paper
        }
            .padding(.horizontal, PhotoPaper.margin)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // 翻转时桌面跟着铺开，下面的页面隐去。
            .background { PhotoPaper.desk.opacity(turned).ignoresSafeArea() }
            .containerBackground(flips ? Color.clear : PhotoPaper.desk, for: .navigation)
            .safeAreaInset(edge: .bottom, spacing: 0) { accessory.opacity(turned) }
            .navigationBarBackButtonHidden()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .interactiveDismissDisabled(isDirty)
            .onAppear {
                // 键盘不等翻完：正文框一出现就拿焦点，纸在下面翻过来。
                guard flips, turned == 0 else { return }
                withAnimation(flipAnimation) { turned = 1 }
            }
            .confirmationDialog("放弃这次修改？", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("放弃", role: .destructive) { close(saved: false) }
                Button("继续写", role: .cancel) {}
            }
            .confirmationDialog("清除这张照片的说明？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清除说明", role: .destructive) { save() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("日记写在照片说明里，清除后在照片 App 里也看不到了。")
            }
            .alert("没有保存", isPresented: .constant(errorMessage != nil)) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sensoryFeedback(.success, trigger: savedCount)
            // 停笔不到一秒就按正文建议标签；追加时连同以前写的一起看。
            .task(id: controller.text) {
                let text = controller.text
                guard intelligence.isEnabled, text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 else {
                    if !suggested.isEmpty { suggested = [] }
                    return
                }
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                let input = mode == .append ? [entry?.caption ?? "", text].joined(separator: "\n") : text
                let tags = await intelligence.engine.suggestTags(for: input, existing: store.allTags)
                guard !Task.isCancelled, text == controller.text else { return }
                suggested = tags
            }
    }

    // MARK: 翻面

    private var flipAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .smooth(duration: 0.35)
    }

    /// 照片正面：和纸一样大的一张照片。
    private var photoFront: some View {
        Color.black
            .overlay { AssetImage(id: assetID, pointSize: CGSize(width: 360, height: 720)) }
            .clipShape(.rect(cornerRadius: PhotoPaper.radius, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
            .accessibilityHidden(true)
    }

    /// 关闭：全屏呈现时先翻回照片正面（和打开方向相反），再交给外面收起。
    private func close(saved: Bool) {
        guard flips else { onFinish(saved); return }
        guard !closing else { return }
        closing = true
        controller.dismissKeyboard()
        withAnimation(flipAnimation) {
            turned = 0
        } completion: {
            onFinish(saved)
        }
    }

    // MARK: 相纸

    /// 一张纸：以前写的字、今天的分隔线、正在写的字，都在同一张纸背上。
    private var paper: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isShared { sharedWarning.padding(.bottom, 18) }
            if mode != .edit {
                if let earlier = earlierWriting {
                    Text(earlier)
                        .font(.diary(16, relativeTo: .subheadline))
                        .lineSpacing(8)
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 20)
                        .accessibilityLabel(Text("之前写的：\(earlier)"))
                }
                SegmentDivider(primary: String(localized: "今天", bundle: .app, locale: .app), secondary: DiaryDates.short(.today))
                    .padding(.bottom, 14)
            }
            DiaryTextView(controller: controller, hint: placeholder)
                .offset(y: inkSettled && !reduceMotion ? 3 : 0)
                .overlay(alignment: .topLeading) {
                    if controller.text.isEmpty {
                        Text(placeholder)
                            .font(.diary(19))
                            .foregroundStyle(Color(.placeholderText))
                            .padding(.top, 4)
                            .allowsHitTesting(false)
                            // 提示已经作为正文框的提示读出来了。
                            .accessibilityHidden(true)
                    }
                }
        }
        .padding(.horizontal, PhotoPaper.inset)
        .padding(.top, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { PhotoPaper(assetID: assetID) }
    }

    private var placeholder: String {
        mode == .append
            ? String(localized: "过了些日子，再看这张照片…", bundle: .app, locale: .app)
            : String(localized: "写下当时的感受，用 #话题# 加标签", bundle: .app, locale: .app)
    }

    /// 纸上已经有的字：标题……最后一段。一篇日记只有一段时就是整段，最多露四行。
    private var earlierWriting: String? {
        guard let entry else { return nil }
        let segs = entry.displaySegments
        if segs.count > 1, let last = segs.last { return entry.title + "…… " + last.text }
        let text = segs.first?.text ?? entry.caption
        return text.isEmpty ? nil : text
    }

    private var sharedWarning: some View {
        Label {
            Text("这张照片在共享图库中，其他成员可能看到这段日记")
        } icon: {
            Image(systemName: "person.2")
        }
        .font(.footnote)
        .foregroundStyle(Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1, green: 0.8, blue: 0.5, alpha: 1) : UIColor(red: 0.42, green: 0.25, blue: 0, alpha: 1) }))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 顶栏：✕ / 日期 / ✓

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消", systemImage: "xmark") {
                if isDirty { confirmDiscard = true } else { close(saved: false) }
            }
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(DiaryDates.full(DayStamp(photoDate)))
                    .font(.callout.weight(.semibold))
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.meta)
            }
            .accessibilityElement(children: .combine)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button {
                if mode == .edit && controller.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    confirmClear = true
                } else {
                    save()
                }
            } label: {
                if saving {
                    ProgressView()
                } else {
                    Label("完成", systemImage: "checkmark")
                }
            }
            .buttonStyle(.glassProminent)
            .tint(brand)
            .disabled(!canSave || saving)
        }
    }

    private var subtitle: String {
        switch mode {
        case .new: entry == nil ? String(localized: "写日记", bundle: .app, locale: .app) : String(localized: "补写日记", bundle: .app, locale: .app)
        case .append: String(localized: "追加感想", bundle: .app, locale: .app)
        case .edit: String(localized: "编辑", bundle: .app, locale: .app)
        }
    }

    // MARK: 键盘上方：玻璃胶囊工具栏（# 按钮、横向标签联想、收起键盘）

    private var accessory: some View {
        // 正在输入 #… 时联想已有标签；没在输入时放模型建议的标签（前面一枚 Apple Intelligence 标记）。
        let typing = controller.tagQuery != nil
        let suggestions = typing ? tagSuggestions : suggested
        return HStack(spacing: 6) {
            Button { controller.insertHash() } label: {
                Text(verbatim: "#")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(brand)
                    .frame(width: 40, height: 40)
                    .background(brand.soft(), in: .circle)
            }
            .buttonStyle(.press)
            .accessibilityLabel("插入标签")
            .largeContent(String(localized: "插入标签", bundle: .app, locale: .app), systemImage: "number")

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    if !typing, !suggestions.isEmpty {
                        Image(systemName: "apple.intelligence")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.inkSecondary)
                            .padding(.leading, 6)
                            .accessibilityHidden(true)
                    }
                    ForEach(suggestions, id: \.self) { tag in
                        Button {
                            if typing {
                                controller.complete(tag)
                            } else {
                                controller.appendTag(tag)
                                suggested.removeAll { $0 == tag }
                            }
                        } label: {
                            Text(verbatim: "#\(tag)#")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(brand)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 34)
                                .background(Color(.systemBackground), in: .capsule)
                                .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.6), lineWidth: 0.5))
                        }
                        .buttonStyle(.press)
                        .accessibilityLabel(Spoken.tag(tag))
                        .accessibilityHint(typing ? Text("补全标签") : Text("加上这个标签"))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity)
            // 容器自己有名字、里面的每个标签照常能选到（直接给滚动视图加 label 会盖掉每个标签的名字）。
            .accessibilityElement(children: .contain)
            .accessibilityLabel(typing ? Text("用过的标签") : Text("建议的标签"))

            if controller.isEditing {
                Button { controller.dismissKeyboard() } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.ink)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.press)
                .accessibilityLabel("收起键盘")
                .largeContent(String(localized: "收起键盘", bundle: .app, locale: .app), systemImage: "keyboard.chevron.compact.down")
            }
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 50)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .animation(.drawer, value: suggestions)
    }

    private var tagSuggestions: [String] {
        guard let q = controller.tagQuery else { return [] }
        let all = store.allTags
        if q.isEmpty { return Array(all.prefix(8)) }
        let prefix = all.filter { $0.hasPrefix(q) && $0 != q }
        let contains = all.filter { !$0.hasPrefix(q) && $0.localizedStandardContains(q) }
        return Array((prefix + contains).prefix(8))
    }

    // MARK: 保存

    /// 墨水落定的时长：写入照片库同时进行，不等它。
    private static let settleDuration: Duration = .milliseconds(220)

    private func save() {
        saving = true
        controller.dismissKeyboard()
        withAnimation(.smooth(duration: 0.22)) { inkSettled = true }
        controller.settleInk(animated: true)
        let settling = Task { try? await Task.sleep(for: Self.settleDuration) }
        Task {
            defer { saving = false }
            do {
                try await store.save(text: controller.text, mode: mode, for: assetID)
                await settling.value
                // 字落定、写进照片的那一下配触感，然后关闭。
                savedCount += 1
                AccessibilityNotification.Announcement(String(localized: "已写进照片说明", bundle: .app, locale: .app)).post()
                original = controller.text
                close(saved: true)
            } catch {
                withAnimation(.snappy) { inkSettled = false }
                controller.restoreInk()
                let nsError = error as NSError
                if nsError.domain == PHPhotosErrorDomain, nsError.code == PHPhotosError.userCancelled.rawValue { return }
                errorMessage = String(localized: "写入照片说明失败：\(error.localizedDescription)", bundle: .app, locale: .app)
            }
        }
    }
}

/// 从详情页、回顾页打开的编辑器。
/// iPhone 上全屏、不带系统的上滑动画：照片在原地翻到纸背，关闭时翻回来再收起。iPad、Mac 上仍是表单。
struct EditorSheet: View {
    let request: EditorRequest
    var flips = false
    @Environment(DiaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EditorView(assetID: request.assetID, mode: request.mode,
                       existingCaption: store.entry(request.assetID)?.caption ?? store.currentCaption(for: request.assetID),
                       seed: request.seed, flips: flips) { _ in
                if flips {
                    // 翻面已经做完了退场，收起时不再滑下去。
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { dismiss() }
                } else {
                    dismiss()
                }
            }
        }
    }
}

/// 绕竖轴翻一张纸：前半程是正面，转到 90° 时换成背面。“减少动态效果”时只淡入淡出背面。
/// 背面一直在视图里（只是看不见），所以里面的输入框不用等翻完就能拿焦点。
struct FlipCard<Front: View, Back: View>: View, Animatable {
    var progress: Double
    var crossfade: Bool
    @ViewBuilder var front: Front
    @ViewBuilder var back: Back

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let backFacing = progress >= 0.5
        // 正面 0°→90°，背面 -90°→0°：翻到一半时两面都侧着，看不出换了。
        let angle = crossfade ? 0 : (backFacing ? (progress - 1) * 180 : progress * 180)
        ZStack {
            if !crossfade, progress < 1 {
                front
                    .opacity(backFacing ? 0 : 1)
                    .allowsHitTesting(false)
            }
            back
                .opacity(crossfade ? progress : (backFacing ? 1 : 0))
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
    }
}
