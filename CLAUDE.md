# PhotoDiary

照片日记：日记写在照片的“说明”里。工程用 XcodeGen（`project.yml`），改了文件结构后运行 `xcodegen generate`，并确认 pbxproj 的签名设置没变。

## 界面约束

- **能用画面说明的，就不写文字说明。** 空状态只有一句标题，分组标题下不加副标题，设置 footer 只留画面表达不了的事实。新增一行说明前先问：去掉它用户会不会做错？详见 `docs/ui-redesign.md` 的“原则”。
- 主题色只用在标签、“+”按钮、追加感想、选中态、今天的日期圆上，颜色交给照片。

## 文字和多语言

- 所有界面文字都要进 `PhotoDiary/Resources/Localizable.xcstrings`，并补齐 `en`、`ja` 翻译（源语言是简体中文）。命令行构建不会自动把新文字写进 catalog，要手动加；去掉的文字也从 catalog 删掉。
- 代码里取文字写 `String(localized: …, bundle: .app, locale: .app)`：系统的 `String(localized:)` 按启动时的语言查表，不传 bundle 的话 App 内切换语言后不会变（见 `Shared/Model/AppLocalization.swift`）。SwiftUI 的 `Text("…")` 不受影响。
- 不用系统自带文字的控件（`ContentUnavailableView.search`、`onDelete` 的“删除”、不写取消按钮的 confirmationDialog、不带标题的 `Tab(role: .search)`）：它们跟系统语言走。
- 数量用复数变体（英文 one / other）。
- Info.plist 里的文字（App 名、权限说明）在 `InfoPlist.xcstrings`，iPhone 和 Watch 共用。App 内界面在系统语言不受支持时用英语（`AppLanguage.resolved`）；系统显示的文字（App 名、权限说明、Watch、小组件）回退到开发语言简体中文。`DEVELOPMENT_LANGUAGE` 必须是 zh-Hans：源语言的文字编译后不单独成表，改成 en 的话中文界面里 SwiftUI 的文字会变成英文。
- 日期一律用 `DiaryDates` 按界面语言格式化，不写死中文格式。

## 测试

- 每一条用户操作都要有测试：改了写入、同步、界面流程，就在 `PhotoDiaryTests`（逻辑）或 `PhotoDiaryUITests`（流程）里补上，交付前跑 `Tools/test.sh`。
- 系统在后台队列上调用的代码（PhotoKit 的观察者和回调、`performChanges` 的闭包、WCSession 代理、`requestPlayerItem` 等）必须是 `nonisolated` 或 `@Sendable` 闭包：工程默认主线程隔离，写错了不会编译报错，运行时直接闪退。新加这类回调要在 `PhotoKitIntegrationTests` 里真的触发一次。
