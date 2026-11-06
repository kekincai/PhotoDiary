import AppIntents

/// 给最新一张照片写日记：快捷指令、Siri、Spotlight、控制中心按钮、锁屏都用这一个。
/// 控制中心的按钮在小组件扩展里，所以这个文件两边都编译；supportedModes 是 .foreground，系统会先打开 App、在 App 里执行。
struct WriteLatestPhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "给最新一张照片写日记"
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkInbox.shared.open(.writeLatest)
        return .result()
    }
}
