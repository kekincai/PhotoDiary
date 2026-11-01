# PhotoDiary

照片日记：日记写在照片的“说明”里。工程用 XcodeGen（`project.yml`），改了文件结构后运行 `xcodegen generate`，并确认 pbxproj 的签名设置没变。

## 界面约束

- **能用画面说明的，就不写文字说明。** 空状态只有一句标题，分组标题下不加副标题，设置 footer 只留画面表达不了的事实。新增一行说明前先问：去掉它用户会不会做错？详见 `docs/ui-redesign.md` 的“原则”。
- 主题色只用在标签、“+”按钮、追加感想、选中态、今天的日期圆上，颜色交给照片。

## 文字和多语言

- 所有界面文字都要进 `PhotoDiary/Resources/Localizable.xcstrings`，并补齐 `en`、`ja` 翻译（源语言是简体中文）。命令行构建不会自动把新文字写进 catalog，要手动加；去掉的文字也从 catalog 删掉。
- 数量用复数变体（英文 one / other）。
- Info.plist 里的文字（App 名、权限说明）在 `InfoPlist.xcstrings`，iPhone 和 Watch 共用。系统语言不在支持之列时回退到英语（`CFBundleDevelopmentRegion = en`）。
- 日期一律用 `DiaryDates` 按界面语言格式化，不写死中文格式。
