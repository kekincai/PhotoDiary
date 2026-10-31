<p align="center">
  <img src="docs/screenshots/icon.png" width="128" alt="照片日记图标">
</p>

<h1 align="center">照片日记 · PhotoDiary</h1>

<p align="center">把日记直接写在 iPhone 照片的“说明”里。<br>
不复制、不存储照片；日记随照片经 iCloud 同步，在系统照片 App 里也能看到、能搜到。</p>

<p align="center">
  <img src="docs/screenshots/journal.png" width="260" alt="日记列表">
  <img src="docs/screenshots/detail.png" width="260" alt="日记详情">
  <img src="docs/screenshots/review.png" width="260" alt="回顾">
</p>

## 为什么

Apple 的“手记”App 会为附加的照片保存一份副本，内容锁在手记里。照片日记反过来：**在原照片上标注**，日记就是照片说明本身。微单拍的大文件不会多占一份空间，删掉本 App 也不会丢日记。

写日记有两个入口：本 App，或者照片 App 的说明栏。两边的修改互相同步，始终以照片说明为准。

## 功能

- **双向同步**：照片 App 里改的说明，打开本 App 就能看到（运行中实时，关闭期间按 change token 增量）
- **日记**：按月分组的时间线，另有日历、照片网格、地图三种视图
- **编辑器**：微博式 `#话题#` 标签，输入 `#` 弹出用过的标签；保存时自动补写作日期；可以给旧照片“追加感想”
- **回顾**：那年今日、本周写作、还没写日记的照片
- **标签**：标签自动同步为照片关键词；支持批量改名、合并
- **搜索**：全文、标签、日期范围
- 照片、视频、实况照片都可以写；支持“有限访问”；全部日记可导出为 Markdown

## 说明格式

纯文本，脱离 App 在照片 App 里看也自然：

```
风很舒服，第一次用新镜头拍日落 #旅行# #镜头测试#
— 2026.10.31

三年后再看，还是喜欢这张
— 2029.11.02
```

- 每段末尾一行 `— YYYY.MM.DD` 是写作日期；追加感想时空一行再写新段落
- `#话题#` 是标签，半角、全角 `＃` 都能识别，最长 20 字；照片关键词完全由标签生成
- 没有日期行的说明（例如 Lightroom 导入的 IPTC 说明）算“其他来源的说明”，默认不进日记流；在本 App 编辑后转为日记
- 解析失败时原文照常显示，App 不会擅自改写用户在别处写的文字

## 技术

- SwiftUI + Swift 6，最低 **iOS 27**：PhotoKit 从 iOS 27 起才公开说明和关键词的读写接口（`PHAsset.extendedMetadata`、`PHAssetChangeRequest.caption`、`addKeyword(_:)`）
- 照片说明是唯一正本，本地只保存可重建的索引（`Application Support/diary-index.json`）
- 首次启动后台分批遍历照片库，建好的部分先显示；之后用 `PHPhotoLibraryChangeObserver` 和 `fetchPersistentChanges(since:)` 增量同步
- 照片日期按拍摄地当地时区计算，和照片 App 一致
- 界面遵循 Apple 的设计原则：Liquid Glass 浮动标签栏、临界阻尼弹簧动画、zoom 转场、日记正文用宋体（系统按需下载）；适配深色模式、动态字体、“减少动态效果”和“降低透明度”

```
PhotoDiary/
├── App/          入口、导航
├── Model/        说明格式解析（CaptionFormat）、日记条目
├── Library/      照片库扫描与写入、本地索引、缩略图、地名
├── Design/       主题色、字体、动效、通用组件
└── Views/        日记、详情、编辑器、从照片添加、回顾、搜索、设置
```

## 构建

需要 Xcode 27 和 iOS 27 SDK。

```bash
open PhotoDiary.xcodeproj
```

工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成，改了工程配置后重新生成：

```bash
xcodegen generate
```

运行单元测试（说明格式解析）：

```bash
xcodebuild test -project PhotoDiary.xcodeproj -scheme PhotoDiary -destination 'platform=iOS Simulator,name=<你的模拟器>'
```

### 测试照片

`Tools/TestPhotos/fetch.sh` 会从 Unsplash 下载 24 张照片，写入拍摄日期、GPS 和日记说明，然后导入到已启动的模拟器：

```bash
Tools/TestPhotos/fetch.sh
```

照片来自 [Unsplash](https://unsplash.com/t/wallpapers)，遵循 [Unsplash License](https://unsplash.com/license)。

### 图标

`Tools/AppIcon/make-icon.swift` 生成浅色、深色、着色三个版本的图标：

```bash
swift Tools/AppIcon/make-icon.swift PhotoDiary/Assets.xcassets/AppIcon.appiconset
```

## 待在真机上验证

- 修改说明时是否每张都弹出系统确认（模拟器上不弹）
- 照片 App 能否搜到 `#话题#` 和长说明靠后的文字
- 共享图库中照片的说明对其他成员是否可见（目前用 `sourceType` 判断是否显示提醒，可能不准）
- 数万张照片规模下首次建索引的耗时

## 许可

[MIT](LICENSE)
