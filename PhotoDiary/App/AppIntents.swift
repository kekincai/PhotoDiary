import AppIntents

// MARK: 快捷指令、Siri、Spotlight
//
// 每一条都只是把 App 打开到某个地方（交给 DeepLinkInbox，再由 Router 打开），不在后台读写照片库。
// 短语在 AppShortcuts.xcstrings 里，中英日各一套。

struct OpenTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "打开今天的日记"
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkInbox.shared.open(.today)
        return .result()
    }
}

struct OpenOnThisDayIntent: AppIntent {
    static let title: LocalizedStringResource = "那年今日"
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkInbox.shared.open(.onThisDay)
        return .result()
    }
}

struct SearchDiaryIntent: AppIntent {
    static let title: LocalizedStringResource = "搜索日记"
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "搜索的文字")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("搜索日记里的\(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkInbox.shared.open(.search(text))
        return .result()
    }
}

struct PhotoDiaryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WriteLatestPhotoIntent(), phrases: [
            "用\(.applicationName)给最新一张照片写日记",
            "在\(.applicationName)写日记",
        ], shortTitle: "写日记", systemImageName: "square.and.pencil")
        AppShortcut(intent: OpenTodayIntent(), phrases: [
            "打开\(.applicationName)里今天的日记",
        ], shortTitle: "今天的日记", systemImageName: "calendar")
        AppShortcut(intent: OpenOnThisDayIntent(), phrases: [
            "\(.applicationName)里的那年今日",
            "打开\(.applicationName)的那年今日",
        ], shortTitle: "那年今日", systemImageName: "clock.arrow.circlepath")
        AppShortcut(intent: SearchDiaryIntent(), phrases: [
            "在\(.applicationName)里搜索日记",
        ], shortTitle: "搜索日记", systemImageName: "magnifyingglass")
    }
}
