import SwiftUI
import Photos

/// 写日记 / 追加感想 / 编辑说明。
struct EditorView: View {
    let assetID: String
    let mode: DiaryStore.WriteMode
    /// saved = true 表示已写入照片说明。
    var onFinish: (_ saved: Bool) -> Void

    @Environment(DiaryStore.self) private var store
    @Environment(\.brand) private var brand
    @State private var controller: EditorController
    @State private var original: String
    @State private var saving = false
    @State private var confirmDiscard = false
    @State private var confirmClear = false
    @State private var errorMessage: String?
    @State private var savedCount = 0

    init(assetID: String, mode: DiaryStore.WriteMode, existingCaption: String?, onFinish: @escaping (Bool) -> Void) {
        self.assetID = assetID
        self.mode = mode
        self.onFinish = onFinish
        let initial = mode == .edit ? (existingCaption ?? "") : ""
        _controller = State(initialValue: EditorController(text: initial))
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
        VStack(alignment: .leading, spacing: 0) {
            if mode != .edit { context.padding(.bottom, 22) }
            if isShared { sharedWarning.padding(.bottom, 16) }
            if mode != .edit {
                SegmentDivider(primary: String(localized: "今天"), secondary: DiaryDates.short(.today))
                    .padding(.horizontal, 6)
                    .padding(.bottom, 14)
            }
            DiaryTextView(controller: controller)
                .overlay(alignment: .topLeading) {
                    if controller.text.isEmpty {
                        Group {
                            if mode == .append { Text("过了些日子，再看这张照片…") } else { Text("写下当时的感受，用 #话题# 加标签") }
                        }
                        .font(.diary(19))
                        .foregroundStyle(Color(.placeholderText))
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 6)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { accessory }
        .navigationBarBackButtonHidden()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .interactiveDismissDisabled(isDirty)
        .confirmationDialog("放弃这次修改？", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("放弃", role: .destructive) { onFinish(false) }
            Button("继续写", role: .cancel) {}
        }
        .confirmationDialog("清除这张照片的说明？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清除说明", role: .destructive) { save() }
        } message: {
            Text("日记写在照片说明里，清除后在照片 App 里也看不到了。")
        }
        .alert("没有保存", isPresented: .constant(errorMessage != nil)) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sensoryFeedback(.success, trigger: savedCount)
    }

    // MARK: 顶栏：✕ / 日期 / ✓

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消", systemImage: "xmark") {
                if isDirty { confirmDiscard = true } else { onFinish(false) }
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
        case .new: entry == nil ? String(localized: "写日记") : String(localized: "补写日记")
        case .append: String(localized: "追加感想")
        case .edit: String(localized: "编辑")
        }
    }

    // MARK: 内容

    /// 原照片和已有的日记，灰底卡片。
    private var context: some View {
        HStack(spacing: 12) {
            AssetImage(id: assetID, pointSize: CGSize(width: 76, height: 76))
                .frame(width: 76, height: 76)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
            Text(contextText)
                .font(.diary(14, relativeTo: .subheadline))
                .lineSpacing(7)
                .foregroundStyle(Color.meta)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.tile, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private var contextText: String {
        guard let entry else {
            return String(localized: "拍摄于 \(DiaryDates.full(DayStamp(photoDate)))")
        }
        let segs = entry.displaySegments
        if segs.count > 1, let last = segs.last { return entry.title + "…… " + last.text }
        return segs.first?.text ?? entry.caption
    }

    private var sharedWarning: some View {
        Label {
            Text("这张照片在共享图库中，其他成员可能看到这段日记。")
        } icon: {
            Image(systemName: "person.2")
        }
        .font(.footnote)
        .foregroundStyle(Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1, green: 0.8, blue: 0.5, alpha: 1) : UIColor(red: 0.42, green: 0.25, blue: 0, alpha: 1) }))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 12))
    }

    // MARK: 键盘上方：玻璃胶囊工具栏（# 按钮、横向标签联想、收起键盘）

    private var accessory: some View {
        let suggestions = tagSuggestions
        return HStack(spacing: 6) {
            Button { controller.insertHash() } label: {
                Text(verbatim: "#")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(brand)
                    .frame(width: 40, height: 40)
                    .background(brand.soft(), in: .circle)
            }
            .buttonStyle(.press)
            .accessibilityLabel("插入标签")

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.self) { tag in
                        Button {
                            controller.complete(tag)
                        } label: {
                            Text(verbatim: "#\(tag)#")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(brand)
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(Color(.systemBackground), in: .capsule)
                                .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.6), lineWidth: 0.5))
                        }
                        .buttonStyle(.press)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("用过的标签")

            if controller.isEditing {
                Button { controller.dismissKeyboard() } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.ink)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.press)
                .accessibilityLabel("收起键盘")
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 50)
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

    private func save() {
        saving = true
        controller.dismissKeyboard()
        Task {
            defer { saving = false }
            do {
                try await store.save(text: controller.text, mode: mode, for: assetID)
                savedCount += 1
                original = controller.text
                onFinish(true)
            } catch {
                let nsError = error as NSError
                if nsError.domain == PHPhotosErrorDomain, nsError.code == PHPhotosError.userCancelled.rawValue { return }
                errorMessage = String(localized: "写入照片说明失败：\(error.localizedDescription)")
            }
        }
    }
}

/// 从详情页、回顾页打开的编辑器（模态，配暗色遮罩）。
struct EditorSheet: View {
    let request: EditorRequest
    @Environment(DiaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EditorView(assetID: request.assetID, mode: request.mode,
                       existingCaption: store.entry(request.assetID)?.caption ?? store.currentCaption(for: request.assetID)) { _ in
                dismiss()
            }
        }
    }
}
