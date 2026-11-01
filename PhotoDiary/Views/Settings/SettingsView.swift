import SwiftUI
import Photos
import UniformTypeIdentifiers

/// 设置：系统分组列表，每行一个带底色的图标（和系统“设置”一样）。
struct SettingsView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(BrandColor.storageKey) private var brandHex = BrandColor.lake.rawValue
    @AppStorage(BrandColor.customKey) private var customHex = "#C0603A"
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @State private var confirmRebuild = false

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
            .confirmationDialog("重建索引？", isPresented: $confirmRebuild, titleVisibility: .visible) {
                Button("重新读取整个照片库") { store.rebuildIndex(); dismiss() }
                Button("取消", role: .cancel) {}
            }
        }
        .tint(.brand(hex: brandHex))
    }

    // MARK: 外观：浅色 / 深色 + 主题色

    private var themeSection: some View {
        Section("外观") {
            Picker("外观", selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Image(systemName: option.symbol)
                        .accessibilityLabel(option.name)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.vertical, Metrics.Spacing.xs)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 5), spacing: Metrics.Spacing.m) {
                ForEach(BrandColor.allCases) { option in
                    swatch(option)
                }
                customSwatch
            }
            .padding(.vertical, Metrics.Spacing.xs)
            .sensoryFeedback(.selection, trigger: brandHex)
        }
    }

    private func swatch(_ option: BrandColor) -> some View {
        let selected = brandHex == option.rawValue
        return Button {
            withAnimation(.snappy) { brandHex = option.rawValue }
        } label: {
            Circle()
                .fill(option.color.gradient)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(selected ? 1 : 0)
                        .scaleEffect(selected ? 1 : 0.5)
                }
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? option.color : .clear, lineWidth: 2))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.press)
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 最后一格是系统调色板，圆环里显示自选的颜色。
    private var customSwatch: some View {
        let selected = !BrandColor.allCases.contains { $0.rawValue == brandHex }
        return ColorPicker("自定义颜色", selection: Binding {
            Color(hex: selected ? brandHex : customHex)
        } set: { color in
            customHex = color.hex
            brandHex = customHex
        }, supportsOpacity: false)
        .labelsHidden()
        .scaleEffect(1.45)
        .frame(width: 40, height: 40)
        .padding(3)
        .overlay(Circle().strokeBorder(selected ? Color(hex: brandHex) : .clear, lineWidth: 2))
        .frame(maxWidth: .infinity)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                if bridge.status == .appNotInstalled {
                    Text("在 iPhone 的 Watch App 里安装“照片日记”，就能在手表上回看日记、口述感想。")
                }
            }
        }
    }

    private func watchStatusText(_ bridge: WatchBridge) -> String {
        switch bridge.status {
        case .unsupported: ""
        case .notPaired: String(localized: "未配对", bundle: .app, locale: .app)
        case .appNotInstalled: String(localized: "未安装", bundle: .app, locale: .app)
        case .ready:
            if let sent = bridge.lastSent {
                // 相对时间按界面语言写，不跟系统语言。
                String(localized: "已同步 · \(sent.formatted(.relative(presentation: .named).locale(AppLanguage.current.locale)))", bundle: .app, locale: .app)
            } else {
                String(localized: "已连接", bundle: .app, locale: .app)
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
        case .authorized: String(localized: "完整访问", bundle: .app, locale: .app)
        case .limited: String(localized: "有限访问", bundle: .app, locale: .app)
        case .denied, .restricted: String(localized: "未允许", bundle: .app, locale: .app)
        default: String(localized: "未设置", bundle: .app, locale: .app)
        }
    }

    // MARK: 数据

    private var dataSection: some View {
        Section {
            let export = MarkdownExport(text: store.markdownExport(), filename: String(localized: "照片日记", bundle: .app, locale: .app) + ".md")
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
            Text("日记在照片的说明里，删除 App 不会丢失。")
        }
    }

    // MARK: 说明格式

    private var formatSection: some View {
        Section("说明格式") {
            Text("风很舒服，第一次用新镜头拍日落 #旅行#\n— 2026.10.31\n\n三年后再看，还是喜欢这张\n— 2029.11.02")
                .font(.system(.footnote, design: .monospaced))
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
            NavigationLink {
                HiddenCaptionsView()
            } label: {
                LabeledContent {
                    let count = store.hiddenCaptionCounts().values.reduce(0, +)
                    if count > 0 { Text("\(count) 张").monospacedDigit() }
                } label: {
                    SettingsLabel("隐藏的说明", symbol: "eye.slash", color: .gray)
                }
            }
        }
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
