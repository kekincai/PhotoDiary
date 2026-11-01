import SwiftUI
import Photos
import UniformTypeIdentifiers

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
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("主题色") {
                    HStack(spacing: 0) {
                        ForEach(BrandColor.allCases) { option in
                            Button {
                                withAnimation(.snappy) { brand = option }
                            } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(option.color)
                                        .frame(width: 40, height: 40)
                                        .overlay {
                                            if brand == option {
                                                Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(.white)
                                            }
                                        }
                                        .padding(3)
                                        .overlay(Circle().strokeBorder(brand == option ? option.color : .clear, lineWidth: 2))
                                    Text(option.name).font(.caption).foregroundStyle(Color.ink)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.press)
                            .accessibilityAddTraits(brand == option ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                    .sensoryFeedback(.selection, trigger: brand)
                }

                Section("语言") {
                    Picker("界面语言", selection: languageBinding) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                }

                captionFilterSection

                Section("照片访问") {
                    LabeledContent("权限", value: accessText)
                    if store.isLimited {
                        Button("选择更多照片") { LimitedLibrary.present() }
                    }
                    Button("在“设置”中修改") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }

                Section {
                    let export = MarkdownExport(text: store.markdownExport(), filename: String(localized: "照片日记") + ".md")
                    ShareLink(item: export,
                              preview: SharePreview(export.filename, image: Image(systemName: "doc.text"))) {
                        Label("导出全部日记（Markdown）", systemImage: "square.and.arrow.up")
                    }
                    ShareLink(item: DiagnosticLog(),
                              preview: SharePreview(DiagnosticLog.filename, image: Image(systemName: "ladybug"))) {
                        Label("导出诊断日志", systemImage: "ladybug")
                    }
                    Button {
                        confirmRebuild = true
                    } label: {
                        Label("重建索引", systemImage: "arrow.clockwise")
                    }
                } footer: {
                    Text("日记保存在照片的“说明”里，随照片经 iCloud 同步。本 App 只保存可以随时重建的索引，删除 App 不会丢失日记。")
                }

                Section("说明格式") {
                    Text("风很舒服，第一次用新镜头拍日落 #旅行#\n— 2026.10.31\n\n三年后再看，还是喜欢这张\n— 2029.11.02")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color.meta)
                    Text("每段末尾一行是写作日期；#话题# 会同步为照片关键词。在照片 App 的说明栏里按这个格式写，也会出现在日记里。")
                        .font(.footnote)
                        .foregroundStyle(Color.meta)
                }
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

    private var accessText: String {
        switch store.authorization {
        case .authorized: String(localized: "完整访问")
        case .limited: String(localized: "有限访问")
        case .denied, .restricted: String(localized: "未允许")
        default: String(localized: "未设置")
        }
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
            Button("添加…", systemImage: "plus") { addingCaption = true }
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
