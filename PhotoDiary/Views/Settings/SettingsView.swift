import SwiftUI
import Photos
import UniformTypeIdentifiers
import UIKit

/// 设置：系统分组列表，每行一个带底色的图标（和系统“设置”一样）。
struct SettingsView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(Intelligence.self) private var intelligence
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(BrandColor.storageKey) private var brandHex = BrandColor.lake.rawValue
    @AppStorage(BrandColor.customKey) private var customHex = "#C0603A"
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @AppStorage(WeekStart.storageKey) private var weekStart: WeekStart = .default
    @AppStorage(Reminder.enabledKey) private var reminderOn = false
    @AppStorage(Reminder.timeKey) private var reminderMinutes = Reminder.defaultMinutes
    @State private var confirmRebuild = false
    /// 正在问通知权限：开关先显示成打开的，等系统弹窗的结果。
    @State private var requestingNotifications = false
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                themeSection
                generalSection
                diarySection
                accessSection
                watchSection
                supportSection
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
            .alert("通知未允许", isPresented: $notificationsDenied) {
                Button("打开设置") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
                Button("取消", role: .cancel) {}
            }
            // 在系统设置里关了通知：开关跟着关掉，不显示成还在提醒。
            .task {
                if reminderOn, await ReminderScheduler.shared.isDenied() { reminderOn = false }
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

    // MARK: 通用：语言、一周起始日

    private var generalSection: some View {
        Section("通用") {
            Picker(selection: languageBinding) {
                ForEach(AppLanguage.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            } label: {
                SettingsLabel("界面语言", symbol: "globe", color: .indigo)
            }
            Picker(selection: $weekStart) {
                ForEach(WeekStart.allCases) { option in
                    Text(option.name).tag(option)
                }
            } label: {
                SettingsLabel("一周从", symbol: "calendar", color: .red)
            }
            // 机型支持 Apple Intelligence 才有这一行：搜索、建议标签、本周回顾的总开关。
            if intelligence.isEligible {
                @Bindable var intelligence = intelligence
                Toggle(isOn: $intelligence.enabled) {
                    SettingsLabel("Apple Intelligence", symbol: "apple.intelligence", color: .purple)
                }
            }
        }
    }

    // MARK: 日记：隐藏的说明、说明格式、导出

    private var diarySection: some View {
        Section {
            Toggle(isOn: reminderBinding) {
                SettingsLabel("晚间提醒", symbol: "bell.badge", color: .red)
            }
            if reminderOn {
                DatePicker(selection: reminderTime, displayedComponents: .hourAndMinute) {
                    SettingsLabel("提醒时间", symbol: "clock", color: .purple)
                }
            }
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
            NavigationLink {
                CaptionFormatView()
            } label: {
                SettingsLabel("说明格式", symbol: "text.quote", color: .teal)
            }
            let export = MarkdownExport(store: store, filename: String(localized: "照片日记", bundle: .app, locale: .app) + ".md")
            ShareLink(item: export, preview: SharePreview(export.filename, image: Image(systemName: "doc.text"))) {
                SettingsLabel("导出全部日记（Markdown）", symbol: "square.and.arrow.up", color: .orange)
            }
        } header: {
            Text("日记")
        } footer: {
            Text("日记在照片的说明里，删除 App 不会丢失。")
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
                    SettingsLabel("状态", symbol: "applewatch", color: .black)
                }
                if bridge.status == .ready {
                    Button {
                        Task { await bridge.syncNow() }
                    } label: {
                        SettingsLabel(bridge.isSending ? "正在发送…" : "立即同步到手表", symbol: "arrow.triangle.2.circlepath", color: .green)
                    }
                    .disabled(bridge.isSending)
                }
            } header: {
                Text(verbatim: "Apple Watch")
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
                String(localized: "已同步 · \(DiaryDates.relative(sent))", bundle: .app, locale: .app)
            } else {
                String(localized: "已连接", bundle: .app, locale: .app)
            }
        }
    }

    // MARK: 照片访问

    private var accessSection: some View {
        Section("照片") {
            LabeledContent {
                Text(accessText).foregroundStyle(Color.meta)
            } label: {
                SettingsLabel("照片访问", symbol: "photo.on.rectangle", color: .blue)
            }
            if store.isLimited {
                Button {
                    LimitedLibrary.present(store: store)
                } label: {
                    SettingsLabel("选择更多照片", symbol: "photo.badge.plus", color: .blue)
                }
            }
            Button {
                if let url = URL.photoAccessSettings { openURL(url) }
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

    // MARK: 帮助：诊断日志、重建索引

    private var supportSection: some View {
        Section {
            ShareLink(item: DiagnosticLog(), preview: SharePreview(DiagnosticLog.filename, image: Image(systemName: "ladybug"))) {
                SettingsLabel("导出诊断日志", symbol: "ladybug", color: .brown)
            }
            Button {
                confirmRebuild = true
            } label: {
                SettingsLabel("重建索引", symbol: "arrow.clockwise", color: .gray)
            }
        } header: {
            Text("帮助")
        } footer: {
            Text("联系开发者时附上诊断日志，里面没有日记正文。")
        }
    }

    private var aboutSection: some View {
        Section("关于") {
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

    // MARK: 晚间提醒

    /// 打开时先问通知权限；没允许就弹回关闭。
    private var reminderBinding: Binding<Bool> {
        Binding {
            reminderOn || requestingNotifications
        } set: { on in
            guard on else {
                reminderOn = false
                Task { await ReminderScheduler.shared.reschedule(store: store) }
                return
            }
            requestingNotifications = true
            Task {
                let granted = await ReminderScheduler.shared.requestAuthorization()
                withAnimation { reminderOn = granted }
                requestingNotifications = false
                notificationsDenied = !granted
                await ReminderScheduler.shared.reschedule(store: store)
            }
        }
    }

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            reminderMinutes = (c.hour ?? 21) * 60 + (c.minute ?? 0)
            ReminderScheduler.shared.rescheduleSoon(store: store)
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

/// 全部日记的 Markdown，分享时才拼（拼一遍要遍历全部日记，不能在设置页每次重绘时做）。
struct MarkdownExport: Transferable {
    let store: DiaryStore
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { export in
            let text = await export.store.markdownExport()
            let url = URL.temporaryDirectory.appending(path: export.filename)
            try text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

/// 说明格式：一段示例，照片 App 里看到的就是这个样子。
struct CaptionFormatView: View {
    var body: some View {
        Form {
            Section {
                Text("风很舒服，第一次用新镜头拍日落 #旅行#\n— 2026.10.31\n\n三年后再看，还是喜欢这张\n— 2029.11.02")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color.ink)
                    .padding(.vertical, Metrics.Spacing.xs)
            }
        }
        .navigationTitle("说明格式")
        .navigationBarTitleDisplayMode(.inline)
    }
}
