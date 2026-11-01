import SwiftUI
import Photos
import UniformTypeIdentifiers

/// 设置：系统分组列表，每行一个带底色的图标（和系统“设置”一样）。
struct SettingsView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("brand") private var brand: BrandColor = .lake
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @State private var confirmRebuild = false
    @State private var hiddenCaptions = CaptionFilter.patterns
    @State private var addingCaption = false
    @State private var newCaption = ""

    var body: some View {
        NavigationStack {
            Form {
                themeSection
                Section {
                    Picker(selection: languageBinding) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    } label: {
                        SettingsLabel("界面语言", symbol: "globe", color: .indigo)
                    }
                }
                watchSection
                captionFilterSection
                accessSection
                dataSection
                formatSection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", systemImage: "checkmark") { dismiss() }
                }
            }
            .alert("隐藏这段说明", isPresented: $addingCaption) {
                TextField("说明文字，例如 0", text: $newCaption)
                Button("取消", role: .cancel) { newCaption = "" }
                Button("隐藏") { hide(newCaption); newCaption = "" }
            } message: {
                Text("说明和这段文字完全一样的照片，不再出现在日记里。")
            }
            .confirmationDialog("重建索引？", isPresented: $confirmRebuild, titleVisibility: .visible) {
                Button("重新读取整个照片库") { store.rebuildIndex(); dismiss() }
            } message: {
                Text("会重新读取所有照片的说明，照片多时需要一些时间。")
            }
        }
        .tint(brand.color)
    }

    // MARK: 主题色

    private var themeSection: some View {
        Section("主题色") {
            HStack(spacing: 0) {
                ForEach(BrandColor.allCases) { option in
                    let selected = brand == option
                    Button {
                        withAnimation(.snappy) { brand = option }
                    } label: {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(option.color.gradient)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.white)
                                        .opacity(selected ? 1 : 0)
                                        .scaleEffect(selected ? 1 : 0.5)
                                }
                                .padding(3)
                                .overlay(Circle().strokeBorder(selected ? option.color : .clear, lineWidth: 2))
                            Text(option.name)
                                .font(.caption)
                                .foregroundStyle(selected ? Color.ink : Color.meta)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.press)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, Metrics.Spacing.xs)
            .sensoryFeedback(.selection, trigger: brand)
        }
    }

    // MARK: Apple Watch

    @ViewBuilder private var watchSection: some View {
        let bridge = WatchBridge.shared
        if bridge.status != .unsupported {
            Section {
                LabeledContent {
                    Text(watchStatusText(bridge))
                        .foregroundStyle(Color.meta)
                } label: {
                    SettingsLabel("Apple Watch", symbol: "applewatch", color: .black)
                }
                if bridge.status == .ready {
                    Button {
                        Task { await bridge.syncNow() }
                    } label: {
                        SettingsLabel(bridge.isSending ? "正在发送…" : "立即同步到手表", symbol: "arrow.triangle.2.circlepath", color: .green)
                    }
                    .disabled(bridge.isSending)
                }
            } footer: {
                if bridge.status == .ready {
                    Text("最近的日记、那年今日和还没写的照片会自动发到手表上；在手表上口述的感想会写进照片说明。")
                } else if bridge.status == .appNotInstalled {
                    Text("在 iPhone 的 Watch App 里安装“照片日记”，就能在手表上回看日记、口述感想。")
                }
            }
        }
    }

    private func watchStatusText(_ bridge: WatchBridge) -> String {
        switch bridge.status {
        case .unsupported: ""
        case .notPaired: String(localized: "未配对")
        case .appNotInstalled: String(localized: "未安装")
        case .ready:
            if let sent = bridge.lastSent {
                String(localized: "已同步 · \(sent.formatted(.relative(presentation: .named)))")
            } else {
                String(localized: "已连接")
            }
        }
    }

    // MARK: 照片访问

    private var accessSection: some View {
        Section {
            LabeledContent {
                Text(accessText).foregroundStyle(Color.meta)
            } label: {
                SettingsLabel("照片访问", symbol: "photo.on.rectangle", color: .blue)
            }
            if store.isLimited {
                Button {
                    LimitedLibrary.present()
                } label: {
                    SettingsLabel("选择更多照片", symbol: "photo.badge.plus", color: .blue)
                }
            }
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                SettingsLabel("在“设置”中修改", symbol: "gear", color: .gray)
            }
        }
    }

    private var accessText: String {
        switch store.authorization {
        case .authorized: String(localized: "完整访问")
        case .limited: String(localized: "有限访问")
        case .denied, .restricted: String(localized: "未允许")
        default: String(localized: "未设置")
        }
    }

    // MARK: 数据

    private var dataSection: some View {
        Section {
            let export = MarkdownExport(text: store.markdownExport(), filename: String(localized: "照片日记") + ".md")
            ShareLink(item: export, preview: SharePreview(export.filename, image: Image(systemName: "doc.text"))) {
                SettingsLabel("导出全部日记（Markdown）", symbol: "square.and.arrow.up", color: .orange)
            }
            ShareLink(item: DiagnosticLog(), preview: SharePreview(DiagnosticLog.filename, image: Image(systemName: "ladybug"))) {
                SettingsLabel("导出诊断日志", symbol: "ladybug", color: .brown)
            }
            Button {
                confirmRebuild = true
            } label: {
                SettingsLabel("重建索引", symbol: "arrow.clockwise", color: .gray)
            }
        } footer: {
            Text("日记保存在照片的“说明”里，随照片经 iCloud 同步。本 App 只保存可以随时重建的索引，删除 App 不会丢失日记。")
        }
    }

    // MARK: 说明格式

    private var formatSection: some View {
        Section("说明格式") {
            Text("风很舒服，第一次用新镜头拍日落 #旅行#\n— 2026.10.31\n\n三年后再看，还是喜欢这张\n— 2029.11.02")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Color.meta)
            Text("每段末尾一行是写作日期；#话题# 会同步为照片关键词。在照片 App 的说明栏里按这个格式写，也会出现在日记里。")
                .font(.footnote)
                .foregroundStyle(Color.meta)
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent {
                Text(Self.versionText).foregroundStyle(Color.meta).monospacedDigit()
            } label: {
                SettingsLabel("版本", symbol: "info.circle", color: .gray)
            }
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// 先切换语言再写入设置，App 按新语言重建界面。
    private var languageBinding: Binding<AppLanguage> {
        Binding {
            language
        } set: { new in
            AppLanguage.apply(new)
            language = new
        }
    }

    // MARK: 隐藏的说明

    private var captionFilterSection: some View {
        Section {
            ForEach(hiddenCaptions, id: \.self) { caption in
                Text(verbatim: caption)
                    .font(.body.monospaced())
            }
            .onDelete { offsets in
                hiddenCaptions.remove(atOffsets: offsets)
                saveHiddenCaptions()
            }
            Button {
                addingCaption = true
            } label: {
                SettingsLabel("添加…", symbol: "plus", color: .gray)
            }
            ForEach(store.frequentShortCaptions(), id: \.caption) { item in
                Button {
                    hide(item.caption)
                } label: {
                    LabeledContent {
                        Text("\(item.count) 张").monospacedDigit()
                    } label: {
                        Label {
                            Text(verbatim: item.caption).font(.body.monospaced()).foregroundStyle(Color.ink)
                        } icon: {
                            Image(systemName: "eye.slash")
                        }
                    }
                }
                .accessibilityLabel("隐藏“\(item.caption)”，\(item.count) 张照片")
            }
        } header: {
            Text("隐藏的说明")
        } footer: {
            Text("说明和这些文字完全一样的照片不算日记，不会出现在列表、日历和搜索里；给它们写日记时会直接覆盖。下方带眼睛图标的是照片库里常见的短说明，点一下就隐藏。")
        }
    }

    private func hide(_ caption: String) {
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              !hiddenCaptions.contains(where: { CaptionFilter.normalized($0) == CaptionFilter.normalized(text) }) else { return }
        withAnimation(.snappy) { hiddenCaptions.append(text) }
        saveHiddenCaptions()
    }

    private func saveHiddenCaptions() {
        CaptionFilter.patterns = hiddenCaptions
        store.captionFilterChanged()
    }
}

/// 设置行的标签：29pt 圆角方块底色 + 白色符号，和系统“设置”一致。
struct SettingsLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color

    init(_ title: LocalizedStringKey, symbol: String, color: Color) {
        self.title = title
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        Label {
            Text(title).foregroundStyle(Color.ink)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(color.gradient, in: .rect(cornerRadius: 7, style: .continuous))
        }
    }
}

/// 本次运行以来的日志，分享时才读取。日志里从不记说明正文。
struct DiagnosticLog: Transferable {
    static let filename = "PhotoDiary-log.txt"

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { _ in
            let url = URL.temporaryDirectory.appending(path: filename)
            try await Log.export().write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

struct MarkdownExport: Transferable {
    let text: String
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { export in
            let url = URL.temporaryDirectory.appending(path: export.filename)
            try export.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
