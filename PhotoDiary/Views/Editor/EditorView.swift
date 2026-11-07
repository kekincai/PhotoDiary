import SwiftUI
import Photos

/// 写日记 / 追加感想 / 编辑说明。
/// 一张纸：顶上是这张照片（按原来的横竖比例），下面是以前写的几行（退后一层）、一条“今天”的分隔线和新写的字。
struct EditorView: View {
    let assetID: String
    let mode: DiaryStore.WriteMode
    /// saved = true 表示已写入照片说明。
    var onFinish: (_ saved: Bool) -> Void

    @Environment(DiaryStore.self) private var store
    @Environment(Intelligence.self) private var intelligence
    @Environment(\.brand) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controller: EditorController
    /// 模型按正文建议的标签；点一下才写进正文。
    @State private var suggested: [String] = []
    @State private var original: String
    @State private var saving = false
    @State private var confirmDiscard = false
    @State private var confirmClear = false
    @State private var errorMessage: String?
    @State private var savedCount = 0

    init(assetID: String, mode: DiaryStore.WriteMode, existingCaption: String?, seed: String? = nil,
         onFinish: @escaping (Bool) -> Void) {
        self.assetID = assetID
        self.mode = mode
        self.onFinish = onFinish
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
        paper
            .padding(.horizontal, PhotoPaper.margin)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background { PhotoPaper.desk.ignoresSafeArea() }
            .containerBackground(PhotoPaper.desk, for: .navigation)
            .safeAreaInset(edge: .bottom, spacing: 0) { accessory }
            .navigationBarBackButtonHidden()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .interactiveDismissDisabled(isDirty)
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

    private func close(saved: Bool) {
        controller.dismissKeyboard()
        onFinish(saved)
    }

    // MARK: 相纸

    /// 一张纸：以前写的字、今天的分隔线、正在写的字，都在同一张纸背上。
    private var paper: some View {
        VStack(alignment: .leading, spacing: 0) {
            photo.padding(.bottom, 18)
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
        .background { PhotoPaper() }
    }

    /// 这张照片，按它自己的横竖比例：横图就是一条横的，竖图不超过纸宽的一半高。
    private var photo: some View {
        let ratio = asset.map { CGFloat($0.pixelWidth) / CGFloat(max($0.pixelHeight, 1)) } ?? 4 / 3
        return AssetImage(id: assetID, pointSize: CGSize(width: 400, height: 400 / ratio))
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxHeight: ratio >= 1 ? 200 : 150, alignment: .leading)
            .clipShape(.rect(cornerRadius: 4, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
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
                                adoptSuggestion(tag)
                            }
                        } label: {
                            chipLabel(tag)
                        }
                        .buttonStyle(.press)
                        .accessibilityLabel(Spoken.tag(tag))
                        .accessibilityHint(typing ? Text("补全标签") : Text("加上这个标签"))
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
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
        .animation(.snappy, value: suggestions)
    }

    private func chipLabel(_ tag: String) -> some View {
        Text(verbatim: "#\(tag)#")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(brand)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(Color(.systemBackground), in: .capsule)
            .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.6), lineWidth: 0.5))
    }

    /// 采纳建议：标签接到正文末尾（正文里马上高亮出来），胶囊淡出。
    private func adoptSuggestion(_ tag: String) {
        controller.appendTag(tag)
        suggested.removeAll { $0 == tag }
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

    private func save() {
        saving = true
        controller.dismissKeyboard()
        Task {
            defer { saving = false }
            do {
                try await store.save(text: controller.text, mode: mode, for: assetID)
                // 写进照片的那一下配触感，然后收回按钮；新的那段在详情页上洇出来。
                savedCount += 1
                AccessibilityNotification.Announcement(String(localized: "已写进照片说明", bundle: .app, locale: .app)).post()
                original = controller.text
                close(saved: true)
            } catch {
                let nsError = error as NSError
                if nsError.domain == PHPhotosErrorDomain, nsError.code == PHPhotosError.userCancelled.rawValue { return }
                errorMessage = String(localized: "写入照片说明失败：\(error.localizedDescription)", bundle: .app, locale: .app)
            }
        }
    }
}

/// 从详情页、回顾页打开的编辑器：表单。从“追加感想”按钮打开时，按钮放大成表单，关闭时收回按钮（系统的 zoom 转场，全程可以拖着中途放回去）。
struct EditorSheet: View {
    let request: EditorRequest
    @Environment(DiaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.zoomNamespace) private var namespace

    var body: some View {
        NavigationStack {
            EditorView(assetID: request.assetID, mode: request.mode,
                       existingCaption: store.entry(request.assetID)?.caption ?? store.currentCaption(for: request.assetID),
                       seed: request.seed) { _ in
                dismiss()
            }
        }
        .modifier(ZoomFromSource(sourceID: request.zoomSource, namespace: namespace))
    }
}

/// 有来源按钮时从按钮放大出来；没有（长按菜单、通知、快捷指令）就是普通的表单上滑。
private struct ZoomFromSource: ViewModifier {
    let sourceID: String?
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let sourceID, let namespace {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}
